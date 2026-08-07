classdef SoundFile < stimgen.StimType

    % obj = stimgen.SoundFile
    % obj = stimgen.SoundFile(Name,Value,...)
    % Playback of pregenerated sound files (vocalizations, phonemes, natural
    % scenes) from a labelled catalog.
    %
    % Class guide: documentation/stimgen_SoundFile.md
    %
    % One SoundFile object owns a catalog of sound files and presents them the
    % same way stimgen.Tone presents a vector of frequencies: FileIndex is a
    % vectorizable property, so FileIndex = 1:8 produces eight variants that
    % cycle under the usual Serial/ShuffleUniform/ShuffleLeastUsed selection,
    % and cross with SoundLevel like any other axis.
    %
    % Each entry may be stored either as a reference to a file on disk
    % (default) or with its samples embedded in the object, so that a saved
    % bank is self-contained. See embed/unembed.
    %
    % Duration is derived from the selected file and is not user-editable.
    %
    % Calibration of spectrotemporally complex sounds is selected by
    % CalibrationMode:
    %   "Filtered" - equalize the whole spectrum with the calibration FIR,
    %                then apply a scalar level. Best for broadband material.
    %   "Direct"   - no equalization; scalar level taken from the tone LUT at
    %                AnchorFrequency (0 = the waveform's spectral centroid).
    %                Preserves the recording's native spectrum.
    %   "None"     - normalize only; no calibration voltage is applied.
    %
    % Example:
    %   s = stimgen.SoundFile;
    %   s.add_folder('C:\vocalizations');
    %   s.select_all;                    % FileIndex = 1:NFiles
    %   s.SoundLevel = [50 60 70];       % 3 * NFiles variants
    %   s.VariantSelectionMode = "ShuffleLeastUsed";
    %   s.catalog_table

    properties (SetObservable, AbortSet)
        FileIndex       (1,:) double {mustBePositive, mustBeInteger} = 1
        Channel         (1,:) double {mustBeNonnegative, mustBeInteger} = 0 % 0 = mix to mono
        CalibrationMode (1,1) string {mustBeMember(CalibrationMode, ...
                            ["Filtered","Direct","None"])} = "Filtered"
        AnchorFrequency (1,1) double {mustBeNonnegative, mustBeFinite} = 0 % Hz; 0 = auto
        LevelReference  (1,1) string {mustBeMember(LevelReference, ...
                            ["rms","peak"])} = "rms"
    end

    properties (SetObservable)
        % Scalar struct of parallel 1-by-N arrays. Scalar so that it is never
        % mistaken for a variant axis, absent from propMeta so no widget is
        % generated for it, and present in UserProperties so that it (and any
        % embedded samples) survive toStruct/fromStruct and save_bank.
        % Fields: Label, Path, SourceFs, NativeSamples, NChannels, Embedded, Data
        Catalog (1,1) struct = struct()
    end

    properties (Constant)
        IsMultiObj      = false;
        % "filter" routes compute_adjusted_voltage to the tone LUT, which is
        % what both Filtered and Direct modes need. apply_calibration is
        % overridden below, so this constant only names the LUT family.
        CalibrationType = "filter";
        % Base value only; apply_normalization is overridden to honour
        % LevelReference, which cannot be a Constant.
        Normalization   = "rms";
    end

    properties (Dependent)
        NFiles
        Labels
        FileNames
        CurrentIndex
        CurrentLabel
        CurrentFileName
    end

    properties (Access = private)
        waveformCache_   (1,1) struct = struct('key', {string.empty(1,0)}, 'data', {cell(1,0)})
        syncingDuration_ (1,1) logical = false
        lastBrowseDir_   (1,1) string = ""
    end

    properties (Constant, Access = private)
        MaxCachedWaveforms = 64
    end

    methods

        function obj = SoundFile(varargin)
            % Defaults first, caller's pairs last, so a caller's value wins.
            % The empty catalog is prepended for the same reason it is listed
            % first in UserProperties: a caller passing FileIndex needs a
            % catalog to already exist.
            obj = obj@stimgen.StimType( ...
                'DisplayName', 'Sound File', ...
                'Catalog', stimgen.SoundFile.empty_catalog(), ...
                ... % Catalog is listed FIRST: load_bank and fromStruct assign
                ... % UserProperties in order, and every one of them triggers a
                ... % regeneration, so the catalog must exist before FileIndex is
                ... % restored. Duration is omitted because it is derived from the
                ... % selected file.
                'UserProperties', ["Catalog","FileIndex","Channel", ...
                                   "CalibrationMode","AnchorFrequency", ...
                                   "LevelReference","SoundLevel", ...
                                   "WindowDuration","ApplyWindow"], ...
                varargin{:});
        end


        function set.Catalog(obj, c)
            c = stimgen.SoundFile.normalize_catalog_(c);
            obj.Catalog = c;
            % Cached waveforms describe the entries being replaced, so they
            % must not outlive them. Safe despite MCSUP: property defaults do
            % not run set methods, so waveformCache_ is always initialized here.
            obj.waveformCache_ = struct('key', {string.empty(1,0)}, 'data', {cell(1,0)}); %#ok<MCSUP>
        end


        % --- Dependent accessors -----------------------------------------

        function n = get.NFiles(obj)
            if isfield(obj.Catalog, 'Path')
                n = numel(obj.Catalog.Path);
            else
                n = 0;
            end
        end

        function s = get.Labels(obj)
            if isfield(obj.Catalog, 'Label')
                s = obj.Catalog.Label;
            else
                s = string.empty(1,0);
            end
        end

        function s = get.FileNames(obj)
            s = strings(1, obj.NFiles);
            for k = 1:obj.NFiles
                [~, n, e] = fileparts(obj.Catalog.Path(k));
                s(k) = n + e;
            end
        end

        function i = get.CurrentIndex(obj)
            i = obj.active_file_index_();
        end

        function s = get.CurrentLabel(obj)
            i = obj.active_file_index_();
            if i < 1 || i > obj.NFiles
                s = "";
            else
                s = obj.Catalog.Label(i);
            end
        end

        function s = get.CurrentFileName(obj)
            i = obj.active_file_index_();
            if i < 1 || i > obj.NFiles
                s = "";
            else
                [~, n, e] = fileparts(obj.Catalog.Path(i));
                s = n + e;
            end
        end


        % --- Signal generation --------------------------------------------

        function update_signal(obj)
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            fsTarget = double(obj.selected_value("Fs"));

            % An empty catalog must be a no-op, never an error: StimPlayer's
            % add_stim constructs the class and immediately builds its panel
            % and signal plot.
            if obj.NFiles == 0
                obj.Signal = zeros(1, obj.N);
                stimgen.util.vprintf(2, 'SoundFile: catalog is empty; no signal generated.');
                return
            end

            i = round(double(obj.selected_value("FileIndex")));
            if i < 1 || i > obj.NFiles
                error('stimgen:SoundFile:IndexOutOfRange', ...
                    'FileIndex %d is outside the catalog (%d file(s)).', i, obj.NFiles);
            end

            ch = round(double(obj.selected_value("Channel")));

            y = obj.load_waveform_(i, ch, fsTarget);

            % Duration follows the file so that Time, N and Signal always agree.
            obj.sync_duration_(numel(y) ./ fsTarget);

            % apply_gate indexes Signal(1:n/2) and Signal(end-n/2+1:end) with
            % no length check of its own.
            if logical(obj.selected_value("ApplyWindow"))
                nWin = numel(obj.Window);
                if nWin > numel(y)
                    error('stimgen:SoundFile:WindowTooLong', ...
                        ['Window (%.2f ms total) is longer than "%s" (%.2f ms). ' ...
                         'Reduce Window Duration or clear Apply Window.'], ...
                        1e3 * nWin / fsTarget, obj.Catalog.Label(i), ...
                        1e3 * numel(y) / fsTarget);
                end
            end

            obj.Signal = reshape(y, 1, []);

            obj.apply_normalization;

            obj.apply_calibration;

            obj.apply_gate;
        end


        % --- Catalog management -------------------------------------------

        function add_files(obj, paths, labels)
            % add_files(obj, paths)
            % add_files(obj, paths, labels)
            % Append sound files to the catalog as on-disk references.
            % Labels default to each file name without its extension, made
            % unique by appending _2, _3, ... where they collide.
            arguments
                obj (1,1) stimgen.SoundFile
                paths (1,:) string
                labels (1,:) string = string.empty(1,0)
            end

            if isempty(paths), return; end
            if ~isempty(labels) && numel(labels) ~= numel(paths)
                error('stimgen:SoundFile:LabelCountMismatch', ...
                    'Supplied %d label(s) for %d file(s).', numel(labels), numel(paths));
            end

            c = obj.Catalog;
            for k = 1:numel(paths)
                ffn = string(paths(k));
                if ~isfile(ffn)
                    error('stimgen:SoundFile:FileNotFound', ...
                        'Audio file not found: %s', ffn);
                end
                try
                    info = audioinfo(char(ffn));
                catch ME
                    error('stimgen:SoundFile:FileNotReadable', ...
                        'Could not read audio file "%s": %s', ffn, ME.message);
                end

                if isempty(labels)
                    [~, base] = fileparts(ffn);
                else
                    base = labels(k);
                end

                c.Label(end+1)         = stimgen.SoundFile.unique_label_(base, c.Label);
                c.Path(end+1)          = string(stimgen.SoundFile.absolute_path_(ffn));
                c.SourceFs(end+1)      = info.SampleRate;
                c.NativeSamples(end+1) = info.TotalSamples;
                c.NChannels(end+1)     = info.NumChannels;
                c.Embedded(end+1)      = false;
                c.Data{end+1}          = [];
            end

            obj.Catalog = c;
            stimgen.util.vprintf(1, 'SoundFile: added %d file(s); catalog now has %d.', ...
                numel(paths), obj.NFiles);
        end


        function add_folder(obj, folder, pattern)
            % add_folder(obj, folder)
            % add_folder(obj, folder, pattern)
            % Append every matching sound file in a folder, sorted by name.
            arguments
                obj (1,1) stimgen.SoundFile
                folder (1,1) string
                pattern (1,:) string = "*.wav"
            end

            if ~isfolder(folder)
                error('stimgen:SoundFile:FolderNotFound', ...
                    'Folder not found: %s', folder);
            end

            found = string.empty(1,0);
            for k = 1:numel(pattern)
                d = dir(fullfile(folder, pattern(k)));
                d = d(~[d.isdir]);
                if ~isempty(d)
                    found = [found, string(fullfile(folder, {d.name}))]; %#ok<AGROW>
                end
            end
            found = unique(found, 'stable');
            found = sort(found);

            if isempty(found)
                error('stimgen:SoundFile:NoMatchingFiles', ...
                    'No files matching %s in %s', strjoin(pattern, ', '), folder);
            end

            obj.add_files(found);
        end


        function remove_files(obj, sel)
            % remove_files(obj, sel)
            % Remove entries selected by index, label, or file name.
            % Remaining entries are renumbered, so FileIndex is clamped to the
            % new catalog size.
            idx  = obj.find_file(sel);
            keep = setdiff(1:obj.NFiles, idx);

            c = obj.Catalog;
            c.Label         = c.Label(keep);
            c.Path          = c.Path(keep);
            c.SourceFs      = c.SourceFs(keep);
            c.NativeSamples = c.NativeSamples(keep);
            c.NChannels     = c.NChannels(keep);
            c.Embedded      = c.Embedded(keep);
            c.Data          = c.Data(keep);

            % Clamp FileIndex BEFORE the catalog shrinks, so the regeneration
            % triggered by set.Catalog never sees an out-of-range index.
            fi = unique(obj.FileIndex(obj.FileIndex <= numel(keep)), 'stable');
            if isempty(fi), fi = 1; end
            obj.FileIndex = fi;

            obj.Catalog = c;
        end


        function set_label(obj, sel, label)
            % set_label(obj, sel, label) - Rename a catalog entry.
            arguments
                obj (1,1) stimgen.SoundFile
                sel
                label (1,1) string
            end
            i = obj.find_file(sel);
            if ~isscalar(i)
                error('stimgen:SoundFile:AmbiguousSelection', ...
                    'set_label requires a selection that matches exactly one file.');
            end
            c = obj.Catalog;
            other = c.Label;  other(i) = "";
            c.Label(i) = stimgen.SoundFile.unique_label_(label, other);
            obj.Catalog = c;
        end


        function embed(obj, sel)
            % embed(obj)
            % embed(obj, sel)
            % Store the samples of the selected files in the object so that a
            % saved bank no longer depends on the files on disk. Samples are
            % kept at their native rate and channel count.
            if obj.NFiles == 0, return; end
            if nargin < 2, sel = 1:obj.NFiles; end
            idx = obj.find_file(sel);

            c = obj.Catalog;
            for k = reshape(idx, 1, [])
                if c.Embedded(k), continue; end
                ffn = c.Path(k);
                if ~isfile(ffn)
                    error('stimgen:SoundFile:FileNotFound', ...
                        'Cannot embed "%s": file not found: %s', c.Label(k), ffn);
                end
                [x, fs] = audioread(char(ffn));
                c.Data{k}          = double(x);
                c.SourceFs(k)      = fs;
                c.NativeSamples(k) = size(x, 1);
                c.NChannels(k)     = size(x, 2);
                c.Embedded(k)      = true;
            end
            obj.Catalog = c;
        end


        function unembed(obj, sel)
            % unembed(obj)
            % unembed(obj, sel)
            % Drop embedded samples and revert to reading from disk. Errors
            % rather than discarding data if the original file is missing.
            if obj.NFiles == 0, return; end
            if nargin < 2, sel = 1:obj.NFiles; end
            idx = obj.find_file(sel);

            c = obj.Catalog;
            for k = reshape(idx, 1, [])
                if ~c.Embedded(k), continue; end
                if ~isfile(c.Path(k))
                    error('stimgen:SoundFile:FileNotFound', ...
                        ['Cannot unembed "%s": the original file is missing, ' ...
                         'and dropping the embedded samples would lose it: %s'], ...
                        c.Label(k), c.Path(k));
                end
                c.Data{k}     = [];
                c.Embedded(k) = false;
            end
            obj.Catalog = c;
        end


        function select_all(obj)
            % select_all(obj) - Present every catalog entry as a variant.
            if obj.NFiles == 0
                obj.FileIndex = 1;
            else
                obj.FileIndex = 1:obj.NFiles;
            end
        end


        function browse_files(obj)
            % browse_files(obj) - Multi-select file dialog; target of the
            % "Sound Files" button in the generated parameter panel.
            startDir = obj.lastBrowseDir_;
            if strlength(startDir) == 0 || ~isfolder(startDir)
                startDir = pwd;
            end

            [fn, pn] = uigetfile( ...
                {'*.wav;*.flac;*.ogg;*.mp3;*.m4a;*.mp4;*.au', 'Audio Files'; ...
                 '*.wav', 'WAVE Files (*.wav)'; ...
                 '*.*',   'All Files'}, ...
                'Add Sound Files', char(startDir), 'MultiSelect', 'on');

            if isequal(fn, 0), return; end

            obj.lastBrowseDir_ = string(pn);
            obj.add_files(string(fullfile(pn, cellstr(fn))));
            obj.select_all;
        end


        function idx = find_file(obj, sel)
            % idx = find_file(obj, sel)
            % Resolve a selection to catalog indices. sel may be numeric
            % indices, label(s), file name(s) with or without extension, or
            % full path(s). Matching is case-insensitive for text.
            if obj.NFiles == 0
                error('stimgen:SoundFile:EmptyCatalog', ...
                    'The sound file catalog is empty. Use add_files or add_folder first.');
            end

            if isnumeric(sel) || islogical(sel)
                if islogical(sel)
                    idx = find(sel);
                else
                    idx = round(double(reshape(sel, 1, [])));
                end
                bad = idx < 1 | idx > obj.NFiles;
                if any(bad)
                    error('stimgen:SoundFile:IndexOutOfRange', ...
                        'Index %d is outside the catalog (%d file(s)).', ...
                        idx(find(bad, 1)), obj.NFiles);
                end
                return
            end

            sel   = string(sel);
            sel   = reshape(sel, 1, []);
            names = obj.FileNames;
            stems = strings(1, obj.NFiles);
            for k = 1:obj.NFiles
                [~, stems(k)] = fileparts(obj.Catalog.Path(k));
            end

            idx = zeros(1, 0);
            for k = 1:numel(sel)
                s = sel(k);
                hit = find(strcmpi(obj.Catalog.Label, s));
                if isempty(hit), hit = find(strcmpi(names, s)); end
                if isempty(hit), hit = find(strcmpi(stems, s)); end
                if isempty(hit), hit = find(strcmpi(obj.Catalog.Path, s)); end
                if isempty(hit)
                    error('stimgen:SoundFile:UnknownFile', ...
                        'No catalog entry matches "%s" by label, file name, or path.', s);
                end
                idx = [idx, reshape(hit, 1, [])]; %#ok<AGROW>
            end
            idx = unique(idx, 'stable');
        end


        function s = file_info(obj, sel)
            % s = file_info(obj, sel) - Struct describing catalog entries.
            if nargin < 2, sel = 1:obj.NFiles; end
            idx = obj.find_file(sel);
            names = obj.FileNames;

            s = struct('Index', {}, 'Label', {}, 'FileName', {}, 'Path', {}, ...
                       'Duration', {}, 'SourceFs', {}, 'NChannels', {}, 'Embedded', {});
            for k = reshape(idx, 1, [])
                s(end+1) = struct( ...
                    'Index',     k, ...
                    'Label',     obj.Catalog.Label(k), ...
                    'FileName',  names(k), ...
                    'Path',      obj.Catalog.Path(k), ...
                    'Duration',  obj.Catalog.NativeSamples(k) ./ obj.Catalog.SourceFs(k), ...
                    'SourceFs',  obj.Catalog.SourceFs(k), ...
                    'NChannels', obj.Catalog.NChannels(k), ...
                    'Embedded',  obj.Catalog.Embedded(k)); %#ok<AGROW>
            end
        end


        function T = catalog_table(obj)
            % T = catalog_table(obj) - Catalog as a table for console review.
            n = obj.NFiles;
            if n == 0
                T = table('Size', [0 7], ...
                    'VariableTypes', {'double','string','string','double','double','double','string'}, ...
                    'VariableNames', {'Index','Label','FileName','Duration_ms','SourceFs','NChannels','Stored'});
                return
            end

            stored = repmat("disk", 1, n);
            stored(obj.Catalog.Embedded) = "embedded";

            T = table( ...
                (1:n)', ...
                obj.Catalog.Label(:), ...
                obj.FileNames(:), ...
                1e3 .* obj.Catalog.NativeSamples(:) ./ obj.Catalog.SourceFs(:), ...
                obj.Catalog.SourceFs(:), ...
                obj.Catalog.NChannels(:), ...
                stored(:), ...
                'VariableNames', {'Index','Label','FileName','Duration_ms','SourceFs','NChannels','Stored'});
        end


        function text = current_parameter_summary(obj)
            % text = current_parameter_summary(obj)
            % Lead with the identity of the sound that is currently selected,
            % then the usual non-default parameter list. This is what
            % StimPlayer prints above the signal plot, so it is the primary
            % answer to "which sound just played".
            %
            % Catalog is removed from UserProperties for the base call, because
            % format_summary_value_ cannot render a struct. It is safe to
            % remove because it is scalar and therefore never a variant source,
            % so the variant signature is unchanged.
            %
            % FileIndex is NOT removed the same way: it *is* a variant source,
            % so dropping it would change the signature, rebuild the
            % combination table, and reset the selection state on every call.
            % Its redundant term is filtered out of the finished string below.
            up = obj.UserProperties;
            obj.UserProperties = up(up ~= "Catalog");
            try
                tail = current_parameter_summary@stimgen.StimType(obj);
            catch ME
                obj.UserProperties = up;
                rethrow(ME)
            end
            obj.UserProperties = up;

            % The identity prefix already states the index, and the base would
            % report it only for non-default values, so it would appear on some
            % variants and not others.
            meta = obj.get_prop_meta();
            parts = split(tail, ", ");
            parts = parts(~startsWith(parts, string(meta.FileIndex.label) + "="));
            tail  = strjoin(parts, ", ");

            n = obj.NFiles;
            if n == 0
                head = "No sound files";
            else
                i = obj.active_file_index_();
                if i < 1 || i > n
                    head = sprintf('File %d/%d: <out of range>', i, n);
                else
                    [~, fn, ext] = fileparts(obj.Catalog.Path(i));
                    head = string(sprintf('File %d/%d: %s (%s)', ...
                        i, n, obj.Catalog.Label(i), fn + ext));
                end
            end

            if strlength(tail) > 0
                text = head + ", " + tail;
            else
                text = head;
            end
        end

    end % methods (public)


    methods (Access = protected)

        function apply_normalization(obj)
            % apply_normalization(obj)
            % Override: Normalization is a Constant, but complex natural
            % sounds need the level reference to be selectable. RMS is the
            % default because SoundLevel should mean dB SPL re: RMS for
            % material with a high crest factor.
            if obj.temporarilyDisableSignalMods || isempty(obj.Signal), return; end
            obj.Signal = obj.normalize_(obj.Signal);
        end


        function apply_calibration(obj)
            % apply_calibration(obj)
            % Override: implement the three calibration modes. CalibrationType
            % is a Constant, so mode selection cannot be expressed through it.
            % Nothing in stimgen.calibration is changed -- both modes reach the
            % tone LUT through the existing compute_adjusted_voltage("filter",
            % value, level) entry point, which substitutes ReferenceFrequency
            % when value is not finite.
            if ~obj.ApplyCalibration || obj.temporarilyDisableSignalMods, return; end
            if obj.CalibrationMode == "None" || isempty(obj.Signal), return; end

            C = obj.Calibration;

            if ~isa(C, 'stimgen.StimCalibration') || isempty(C.CalibrationData)
                if obj.calibrationWarningIssued
                    stimgen.util.vprintf(2, 1, 'No calibration data available for stim');
                else
                    stimgen.util.vprintf(0, 1, 'No calibration data available for stim');
                    obj.calibrationWarningIssued = true;
                end
                return
            end

            y     = obj.Signal;
            level = double(obj.get_selected_property_value_("SoundLevel"));

            switch obj.CalibrationMode
                case "Filtered"
                    if ~isfield(C.CalibrationData, 'filter') || isempty(C.CalibrationData.filter)
                        error('stimgen:SoundFile:NoEqualizer', ...
                            ['Calibration Mode is "Filtered" but the loaded calibration ' ...
                             'contains no equalization filter. Run design_filter during ' ...
                             'calibration, or switch to "Direct".']);
                    end

                    Hd = C.CalibrationData.filter;

                    % The taps realize their designed response only at the rate
                    % they were fitted for, and a mismatch is invisible in the
                    % output. Drop the waveform as well as raising, for the
                    % reason given in StimType.apply_calibration.
                    try
                        stimgen.util.assert_filter_rate(C.CalibrationData, ...
                            double(obj.selected_value("Fs")));
                    catch ME
                        obj.Signal = [];
                        rethrow(ME);
                    end

                    % Equalize in place so the recording keeps its length and
                    % its onset sample.
                    y = stimgen.util.filter_aligned(Hd, y, ...
                        round(C.CalibrationData.filterGrpDelay));

                    % NaN -> Engine anchors the scalar level to ReferenceFrequency,
                    % which is the right anchor once the spectrum is flat.
                    value = NaN;

                case "Direct"
                    value = obj.AnchorFrequency;
                    if ~isfinite(value) || value <= 0
                        value = obj.spectral_centroid_(y, double(obj.selected_value("Fs")));
                    end

                otherwise
                    value = NaN;
            end

            % Equalization changes the overall gain; renormalize before the
            % level scaling, exactly as the base class does.
            y = obj.normalize_(y);

            v = C.compute_adjusted_voltage("filter", value, level);

            % The base class only checks v itself. For RMS-referenced natural
            % sounds the peak is what clips, and the crest factor can be 10x.
            peakV = max(abs(v .* y));
            if peakV > 10
                error('stimgen:SoundFile:VoltageOutOfRange', ...
                    ['Peak output would be %.2f V (limit 10 V): %.2f V level scaling ' ...
                     'times a crest factor of %.1f. Reduce SoundLevel.'], ...
                    peakV, v, max(abs(y)));
            end

            obj.Signal = v .* y;
        end


        function onPropertyChanged(obj, src, event)
            % onPropertyChanged(obj, src, event)
            % Override: Duration is derived from the selected file and written
            % from inside update_signal. Suppress the listener for that write
            % so it does not re-enter update_signal.
            if obj.syncingDuration_ && ~isempty(src) && string(src.Name) == "Duration"
                return
            end
            onPropertyChanged@stimgen.StimType(obj, src, event);
        end


        function m = propMeta(obj)
            % propMeta() - Display metadata for SoundFile GUI properties.
            m = struct();
            m.BrowseFiles     = struct('label', 'Sound Files', 'widget', 'button', ...
                                       'text', 'Browse...', 'callback', 'browse_files', ...
                                       'group', 'Waveform', 'order', 1, ...
                'tooltip', stimgen.util.tooltip(obj, 'BrowseFiles'));
            m.UseAllFiles     = struct('label', 'File Selection', 'widget', 'button', ...
                                       'text', 'Use All Files', 'callback', 'select_all', ...
                                       'group', 'Waveform', 'order', 2, ...
                'tooltip', stimgen.util.tooltip(obj, 'UseAllFiles'));
            m.FileIndex       = struct('label', 'File Index', ...
                                       'group', 'Waveform', 'order', 10, ...
                'tooltip', stimgen.util.tooltip(obj, 'FileIndex'));
            m.Channel         = struct('label', 'Channel (0 = mix)', ...
                                       'group', 'Waveform', 'order', 20, ...
                'tooltip', stimgen.util.tooltip(obj, 'Channel'));
            m.CalibrationMode = struct('label', 'Calibration Mode', 'widget', 'dropdown', ...
                                       'items', ["Filtered" "Direct" "None"], ...
                                       'group', 'Level', 'order', 5, ...
                'tooltip', stimgen.util.tooltip(obj, 'CalibrationMode'));
            m.AnchorFrequency = struct('label', 'Anchor Freq (Hz, 0 = auto)', ...
                                       'group', 'Level', 'order', 6, ...
                'tooltip', stimgen.util.tooltip(obj, 'AnchorFrequency'));
            m.LevelReference  = struct('label', 'Level Reference', 'widget', 'dropdown', ...
                                       'items', ["rms" "peak"], ...
                                       'group', 'Level', 'order', 7, ...
                'tooltip', stimgen.util.tooltip(obj, 'LevelReference'));

            base = propMeta@stimgen.StimType(obj);
            % Duration is derived from the selected file, so it must not be
            % offered as an editable field.
            base = rmfield(base, 'Duration');

            m = stimgen.StimType.merge_prop_meta(m, base);
        end

    end % methods (Access = protected)


    methods (Access = private)

        function y = normalize_(obj, y)
            % y = normalize_(obj, y) - Scale by the selected level reference.
            switch obj.LevelReference
                case "rms"
                    d = sqrt(mean(y.^2));
                case "peak"
                    d = max(abs(y));
            end
            if d > 0
                y = y ./ d;
            end
        end


        function sync_duration_(obj, newDur)
            % sync_duration_(obj, newDur) - Set Duration from the loaded file.
            if isscalar(obj.Duration) && abs(obj.Duration - newDur) <= eps(newDur)
                return
            end
            obj.syncingDuration_ = true;
            try
                obj.Duration = newDur;
            catch ME
                obj.syncingDuration_ = false;
                rethrow(ME)
            end
            obj.syncingDuration_ = false;
        end


        function i = active_file_index_(obj)
            % i = active_file_index_(obj) - Currently selected FileIndex,
            % without advancing the variant selection. selected_value()
            % reselects when called outside a locked update cycle, which would
            % desynchronize a reported index from the signal that was played.
            if obj.NFiles == 0
                i = 0;
                return
            end
            cycleWasActive = obj.variantCycleActive_;
            obj.variantCycleActive_ = true;
            try
                i = round(double(obj.selected_value("FileIndex")));
            catch
                i = round(double(obj.FileIndex(1)));
            end
            obj.variantCycleActive_ = cycleWasActive;
        end


        function y = load_waveform_(obj, i, ch, targetFs)
            % y = load_waveform_(obj, i, ch, targetFs)
            % Channel-reduced, resampled waveform for catalog entry i.
            %
            % Cached: update_signal runs on every property change and on every
            % variant step during timed playback, and re-reading plus
            % resampling a file each time is far too slow. set.Catalog clears
            % the cache, so entries never outlive the data they describe.
            c = obj.Catalog;

            if c.Embedded(i)
                key = sprintf('embedded|%d|%d|%.6f', i, ch, targetFs);
            else
                d = dir(c.Path(i));
                if isempty(d)
                    error('stimgen:SoundFile:FileNotFound', ...
                        'Sound file for "%s" not found: %s', c.Label(i), c.Path(i));
                end
                key = sprintf('%s|%.10f|%d|%.6f', c.Path(i), d.datenum, ch, targetFs);
            end

            hit = find(obj.waveformCache_.key == string(key), 1);
            if ~isempty(hit)
                y = obj.waveformCache_.data{hit};
                return
            end

            try
                if c.Embedded(i)
                    y = stimgen.util.read_audio(c.Data{i}, ch, targetFs, c.SourceFs(i));
                else
                    y = stimgen.util.read_audio(c.Path(i), ch, targetFs);
                end
            catch ME
                switch ME.identifier
                    case 'stimgen:util:read_audio:InvalidChannel'
                        error('stimgen:SoundFile:InvalidChannel', ...
                            'Channel %d is not available in "%s" (%d channel(s)).', ...
                            ch, c.Label(i), c.NChannels(i));
                    case {'stimgen:util:read_audio:FileNotFound', ...
                          'stimgen:util:read_audio:ReadFailed'}
                        error('stimgen:SoundFile:FileNotFound', ...
                            'Could not read "%s": %s', c.Label(i), ME.message);
                    otherwise
                        rethrow(ME)
                end
            end

            obj.waveformCache_.key(end+1)  = string(key);
            obj.waveformCache_.data{end+1} = y;
            if numel(obj.waveformCache_.key) > obj.MaxCachedWaveforms
                obj.waveformCache_.key(1)  = [];
                obj.waveformCache_.data(1) = [];
            end
        end


        function fc = spectral_centroid_(~, y, fs)
            % fc = spectral_centroid_(~, y, fs)
            % Power-weighted mean frequency, used as the Direct-mode LUT anchor
            % when AnchorFrequency is 0. Returns NaN when undefined, which
            % makes Engine fall back to ReferenceFrequency.
            n = numel(y);
            if n < 2
                fc = NaN;
                return
            end
            nfft = 2^nextpow2(n);
            Y    = abs(fft(y, nfft));
            half = floor(nfft/2) + 1;
            p    = reshape(Y(1:half), [], 1).^2;
            f    = (0:half-1)' .* (fs / nfft);

            total = sum(p);
            if ~isfinite(total) || total <= 0
                fc = NaN;
                return
            end
            fc = sum(f .* p) ./ total;
            if ~isfinite(fc) || fc <= 0
                fc = NaN;
            end
        end

    end % methods (Access = private)


    methods (Static)

        function c = empty_catalog()
            % c = stimgen.SoundFile.empty_catalog()
            % An empty catalog struct. Values are wrapped in cells so that
            % struct() builds a 1-by-1 struct of empty arrays rather than a
            % 0-by-0 struct array.
            c = struct( ...
                'Label',         {string.empty(1,0)}, ...
                'Path',          {string.empty(1,0)}, ...
                'SourceFs',      {zeros(1,0)}, ...
                'NativeSamples', {zeros(1,0)}, ...
                'NChannels',     {zeros(1,0)}, ...
                'Embedded',      {false(1,0)}, ...
                'Data',          {cell(1,0)});
        end

    end % methods (Static)


    methods (Static, Access = private)

        function c = normalize_catalog_(c)
            % c = normalize_catalog_(c)
            % Fill in missing fields and conform shapes/types, so that a
            % catalog restored from an older bank or hand-built by a user is
            % safe to index.
            e = stimgen.SoundFile.empty_catalog();
            f = fieldnames(e);
            for k = 1:numel(f)
                if ~isfield(c, f{k})
                    c.(f{k}) = e.(f{k});
                end
            end

            c.Label         = reshape(string(c.Label), 1, []);
            c.Path          = reshape(string(c.Path), 1, []);
            c.SourceFs      = reshape(double(c.SourceFs), 1, []);
            c.NativeSamples = reshape(double(c.NativeSamples), 1, []);
            c.NChannels     = reshape(double(c.NChannels), 1, []);
            c.Embedded      = reshape(logical(c.Embedded), 1, []);
            c.Data          = reshape(c.Data, 1, []);

            n = numel(c.Path);
            if numel(c.Label) ~= n || numel(c.SourceFs) ~= n || ...
               numel(c.NativeSamples) ~= n || numel(c.NChannels) ~= n || ...
               numel(c.Embedded) ~= n || numel(c.Data) ~= n
                error('stimgen:SoundFile:InvalidCatalog', ...
                    'Catalog fields must all have the same number of entries (%d expected).', n);
            end
        end


        function s = unique_label_(base, existing)
            % s = unique_label_(base, existing) - Disambiguate a label.
            base = strtrim(string(base));
            if strlength(base) == 0
                base = "sound";
            end
            s = base;
            k = 1;
            while any(strcmpi(existing, s))
                k = k + 1;
                s = base + "_" + k;
            end
        end


        function p = absolute_path_(ffn)
            % p = absolute_path_(ffn) - Resolve to a full path.
            d = dir(char(ffn));
            if isempty(d)
                p = string(ffn);
            else
                p = string(fullfile(d(1).folder, d(1).name));
            end
        end

    end % methods (Static, Access = private)

end
