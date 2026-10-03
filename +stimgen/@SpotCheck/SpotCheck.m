classdef SpotCheck < handle

    % obj = stimgen.SpotCheck
    % obj = stimgen.SpotCheck(engine)
    % obj = stimgen.SpotCheck(adapter)
    % obj = stimgen.SpotCheck(host)
    % obj = stimgen.SpotCheck(..., Name, Value, ...)
    % Play one stimulus through the rig, record it, and characterize what came
    % back.
    %
    % Developer guide: documentation/stimgen_SpotCheck.md
    %
    % A calibration answers "what voltage produces 70 dB SPL at 4 kHz". It does
    % not answer "does this stimulus, the one about to run in the experiment,
    % actually come out of the speaker the way it was asked for". That is a
    % different question -- it is about a whole waveform rather than a table
    % point, and it is asked minutes before a session rather than during a
    % calibration -- and this is the tool for it.
    %
    % Three pieces already existed and this joins them:
    %
    %   stimgen.calibration.Engine    plays and records, through whatever
    %                                 HwAdapter the rig has, on the same
    %                                 acquisition path every calibration uses
    %   stimgen.CapturedSignal        carries the microphone record as a
    %                                 stimgen.StimType so the recording can go
    %                                 where a stimulus goes
    %   stimgen.StimInspector         characterizes it -- waveform, envelope,
    %                                 spectrum, spectrogram, harmonics, and a
    %                                 table of time/spectral/distortion metrics
    %
    % Nothing about the analysis is reimplemented here. This window sets the
    % capture up, runs it, reports the handful of numbers that compare the two
    % waveforms, and opens an inspector on each so they can be read side by
    % side. Two plots are drawn here rather than there, and only because they
    % are about the PAIR: the stimulus and the recording overlaid on one time
    % base, and their two spectra overlaid on one frequency axis. Neither is a
    % view of a single signal, which is all an inspector holds.
    %
    % The headline number is the level error. The stimulus asks for a level in
    % dB SPL; the recording is converted to dB SPL through the engine's own
    % scale (Engine.volts_to_spl) and the two are subtracted -- on a measured
    % microphone sensitivity only (Engine.known_mic_sensitivity, else the
    % stimulus calibration's; with neither the record stays in volts and no
    % error is reported, never a level on the 1 V/Pa placeholder). The measurement
    % follows the stimulus's CalibrationType, so it is made the same way the
    % table that calibrated it was made -- spectral rms at the tone frequency
    % for a tone, peak for a click train, broadband rms otherwise. A spot check
    % that measured a tone with a broadband rms would disagree with the tone LUT
    % by the noise in the record and look like a calibration fault.
    %
    % OFFLINE. With no adapter attached the window still opens and a stimulus
    % can still be loaded and inspected; only Run is unavailable. That matches
    % stimgen.StimPlayer and stimgen.calibration.CalibrationGui.
    %
    % Properties (read-only):
    %   Engine         - stimgen.calibration.Engine doing the acquisition
    %   Stimulus       - stimgen.StimType currently loaded, or []
    %   StimulusLabel  - display label for it
    %   StimulusFile   - file it was loaded from, or ""
    %   Capture        - raw struct from Engine.play_and_capture ([] before a run)
    %   Recording      - stimgen.CapturedSignal wrapping the last record
    %   Results        - reduced comparison (see run)
    %   VariantIndex   - variant combination the next run plays (set_variant)
    %
    % Properties (settable):
    %   PreDelay, PostDelay - silence around the stimulus, in seconds.
    %                         PostDelay must exceed the rig round-trip latency.
    %   Repeats             - acquisitions to average
    %   StepVariant         - advance one combination per run (default false)
    %
    % Usage:
    %   % Interactive, on a sound card:
    %   a  = stimgen.calibration.WindowsSoundCardAdapter(SampleRate=48000);
    %   sc = stimgen.SpotCheck(a);
    %   sc.load_stimulus('C:\banks\session.spl');   % or set_stimulus(toneObj)
    %   % ... press Run, or:
    %   r  = sc.run;
    %   fprintf('%.1f dB requested, %.1f dB measured\n', ...
    %       r.stimulus.requested_level_db, r.measured.level_db_spl);
    %
    %   % Against an already-calibrated engine, headless:
    %   eng = stimgen.calibration.Engine.load('rigB.esgc');
    %   eng.set_adapter(a);
    %   sc  = stimgen.SpotCheck(eng, Stimulus=myTone, Show=false);
    %   sc.run; sc.save_results('spotcheck_rigB.mat');
    %
    % VARIANTS. A stimulus with vectorized properties has several combinations,
    % and the one checked is the one the window names -- VariantIndex, chosen
    % with the Variant spinner or set_variant -- never whatever the stimulus's
    % own selector would pick next. Repeated runs measure that same combination
    % until another is chosen. StepVariant (the "Step each run" box) walks the
    % combinations instead: each run after the first on a combination moves one
    % along before playing, so the result on screen and the variant on screen
    % always describe the same run. The waveform is regenerated only when it
    % does not already match the chosen combination, so what is measured is
    % the waveform the object is actually holding.
    %
    % See also: stimgen.calibration.Engine.play_and_capture,
    %           stimgen.StimInspector, stimgen.CapturedSignal,
    %           stimgen.calibration.CalibrationGui

    % --- External method declarations ---
    % Trailing-underscore methods are helpers, public only so GUI callbacks can
    % reach them (the convention stimgen.StimPlayer and stimgen.StimInspector
    % already use).
    methods
        results = run(obj)
        load_stimulus(obj, ffn)
        ffn = save_results(obj, ffn)
        ffn = save_screenshot(obj, ffn)
        s = describe(obj)
        build_ui_(obj)
        refresh_ui_(obj)
        results = analyze_(obj, capture, stimObj)
        update_compare_plots_(obj)
    end

    % --- Public read-only state ---
    properties (SetAccess = private)
        Engine stimgen.calibration.Engine
        Stimulus                            % stimgen.StimType | []
        StimulusLabel (1,1) string = ""
        StimulusFile  (1,1) string = ""
        Capture       = []                  % struct from Engine.play_and_capture
        Recording                           % stimgen.CapturedSignal | []
        Results       (1,1) struct = struct()

        % Variant combination the next run plays, 1-based. Pinned here rather
        % than read off the stimulus, because the stimulus's own active index
        % moves by itself: any regeneration outside a locked cycle (a property
        % change such as Match Rate's Fs, for one) selects the next
        % combination. run() puts the stimulus back on this index first.
        VariantIndex  (1,1) double = 1
    end

    % --- Capture settings ---
    properties
        % Leading silence, in seconds. Doubles as the noise-floor measurement:
        % the level the recording is compared against is measured over exactly
        % this stretch, under the conditions the stimulus was captured in.
        PreDelay  (1,1) double {mustBeNonnegative, mustBeFinite} = 0.05

        % Trailing silence, in seconds. This is the bound on the delay search,
        % so it has to be longer than the rig's round-trip latency -- acoustic
        % flight time plus converter latency -- or the response cannot be
        % located and the record is cut in the wrong place.
        PostDelay (1,1) double {mustBeNonnegative, mustBeFinite} = 0.05

        % Acquisitions to average. Each is aligned on its own measured delay
        % first, so a latency that shifts between records does not smear them.
        Repeats   (1,1) double {mustBeInteger, mustBePositive, mustBeFinite} = 1

        % Advance one variant combination per run, wrapping at the end, so a
        % series of runs walks a whole bank item. Off by default: a spot check
        % is usually repeated on one combination until it is right, and a
        % stimulus that changes between two presses of Run makes the second
        % press answer a different question.
        StepVariant (1,1) logical = false
    end

    properties (Constant)
        % Help > Guide opens this page.
        GuideURL = 'https://github.com/dstolz/stimgen/wiki/Calibrating-Your-Rig'

        % Waveform points drawn before min/max decimation, matching
        % stimgen.StimInspector so the two windows thin a trace alike.
        MaxPlotPoints = 2e4
    end

    properties (Access = private)
        Figure
        handles struct = struct()
        StimInspector_                  % stimgen.StimInspector on the stimulus
        CaptureInspector_               % stimgen.StimInspector on the recording
        Running_ (1,1) logical = false
        DataPath_ (1,1) string = ""

        % True once a run has completed on VariantIndex. StepVariant steps
        % only from a combination that has been measured, so the first run
        % after choosing one plays that one rather than its successor.
        VariantMeasured_ (1,1) logical = false
    end

    % =====================================================================
    methods

        function obj = SpotCheck(varargin)
            % obj = stimgen.SpotCheck(...)
            % Build the tool. Positional arguments are identified by type, so
            % an Engine, an HwAdapter, a HardwareHost and a StimType may be
            % given in any order or by name -- the same convention
            % stimgen.calibration.CalibrationGui uses.
            %
            % Parameters (positional, any order, all optional):
            %   stimgen.calibration.Engine    - engine to acquire through
            %   stimgen.calibration.HwAdapter - adapter to build one around
            %   stimgen.HardwareHost          - host to take an adapter from
            %   stimgen.StimType              - stimulus to load
            %
            % Parameters (Name=Value):
            %   Engine, Adapter, Host, Stimulus - as above, named
            %   Label   - (1,1) string display label for the stimulus
            %   Show    - (1,1) logical, false to run headless (default true)

            [eng, adapter, host, stimObj, label, show] = obj.parse_args_(varargin);

            % An adapter or a host is a request for an engine to hang it on;
            % an engine given as well keeps its own adapter unless one was
            % named explicitly.
            if isempty(eng)
                eng = stimgen.calibration.Engine();
            end
            obj.Engine = eng;

            if isempty(adapter) && ~isempty(host)
                adapter = obj.adapter_from_host_(host);
            end
            if ~isempty(adapter)
                obj.Engine.set_adapter(adapter);
            end

            if show
                obj.build_ui_();
            end

            if ~isempty(stimObj)
                obj.set_stimulus(stimObj, label);
            elseif show
                obj.refresh_ui_();
            end

            if nargout == 0 && show, clear obj; end
        end


        % -----------------------------------------------------------------
        function delete(obj)
            % Destructor: close the window and any inspector it opened.
            for h = [obj.StimInspector_, obj.CaptureInspector_]
                if ~isempty(h) && isvalid(h)
                    delete(h);
                end
            end
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                obj.Figure.DeleteFcn = '';
                delete(obj.Figure);
            end
        end


        % -----------------------------------------------------------------
        function set_stimulus(obj, stimObj, label)
            % set_stimulus(obj, stimObj)
            % set_stimulus(obj, stimObj, label)
            % Load a stimulus object to spot check.
            %
            % The object is used directly, not copied: a spot check should
            % measure the very waveform the caller is about to run, edits and
            % variant state included.
            %
            % Parameters:
            %   stimObj - stimgen.StimType to check, or [] to clear
            %   label   - display label (optional; defaults to DisplayName)
            arguments
                obj (1,1) stimgen.SpotCheck
                stimObj
                label (1,1) string = ""
            end

            if ~isempty(stimObj)
                mustBeA(stimObj, 'stimgen.StimType');
                if ~isscalar(stimObj)
                    error('stimgen:SpotCheck:nonScalarStimulus', ...
                        ['A spot check measures one stimulus at a time, but %d ' ...
                         'were given. Index the array first.'], numel(stimObj));
                end
            end

            obj.Stimulus = stimObj;

            % A stimulus handed over as an object came from no file. Cleared
            % here rather than left to whoever calls next, so a saved result
            % never names the file a previous stimulus was loaded from;
            % load_stimulus sets it again after this returns.
            obj.StimulusFile = "";

            % Start on the combination the stimulus arrives on, so a caller
            % that stepped it before handing it over gets that one checked.
            obj.VariantIndex     = 1;
            obj.VariantMeasured_ = false;
            if ~isempty(stimObj)
                info = stimObj.get_variant_info();
                obj.VariantIndex = info.ActiveIndex;
            end

            if strlength(label) > 0
                obj.StimulusLabel = label;
            elseif ~isempty(stimObj)
                obj.StimulusLabel = obj.default_label_(stimObj);
            else
                obj.StimulusLabel = "";
            end

            % The previous run described a different stimulus.
            obj.Capture   = [];
            obj.Recording = [];
            obj.Results   = struct();

            obj.refresh_inspectors_();
            obj.refresh_ui_();
        end


        % -----------------------------------------------------------------
        function set_adapter(obj, adapter)
            % set_adapter(obj, adapter)
            % Attach, replace ([] to detach) the acquisition adapter.
            obj.Engine.set_adapter(adapter);
            obj.refresh_ui_();
        end


        % -----------------------------------------------------------------
        function match_hardware_rate(obj)
            % match_hardware_rate(obj)
            % Set the stimulus sample rate to the hardware's.
            %
            % Never done implicitly by run(): changing Fs regenerates the
            % waveform, and silently altering the object a caller is about to
            % run in an experiment is not this tool's decision to make. run()
            % raises instead, and this is the explicit fix.
            if isempty(obj.Stimulus) || ~isvalid(obj.Stimulus)
                return
            end
            fs = obj.Engine.Fs;
            if ~isfinite(fs) || fs <= 0
                obj.set_status_("No hardware sample rate to match; attach an adapter first.", ...
                    isError=true);
                return
            end
            obj.Stimulus.Fs = fs;
            % Assigning Fs regenerates through the stimulus's own selector,
            % which moves it on to the next combination; put it back.
            obj.pin_variant_(obj.VariantIndex);
            stimgen.util.vprintf(1, 'SpotCheck: stimulus sample rate set to %.10g Hz.', fs);
            obj.set_status_(sprintf('Stimulus sample rate set to %.10g Hz.', fs));
            obj.refresh_inspectors_();
            obj.refresh_ui_();
        end


        % -----------------------------------------------------------------
        function set_variant(obj, idx)
            % set_variant(obj, idx)
            % Choose the variant combination to spot check.
            %
            % Regenerates the stimulus at that combination and discards the
            % previous result, which described a different one. Every later
            % run plays this combination until another is chosen, unless
            % StepVariant is on (see the class help).
            %
            % Parameters:
            %   idx - 1-based combination index, 1..NumCombinations
            arguments
                obj (1,1) stimgen.SpotCheck
                idx (1,1) double {mustBeInteger, mustBePositive}
            end

            if obj.Running_
                error('stimgen:SpotCheck:alreadyRunning', ...
                    'The variant cannot be changed while a spot check is running.');
            end
            if isempty(obj.Stimulus) || ~isvalid(obj.Stimulus)
                error('stimgen:SpotCheck:noStimulus', ...
                    'Load a stimulus before choosing a variant.');
            end

            n = obj.variant_count_();
            if idx > n
                error('stimgen:SpotCheck:variantOutOfRange', ...
                    'Variant %d was asked for, but "%s" has %d combination(s).', ...
                    idx, obj.StimulusLabel, n);
            end
            if idx == obj.VariantIndex && ~isempty(obj.Stimulus.Signal)
                info = obj.Stimulus.get_variant_info();
                if info.ActiveIndex == idx
                    return      % already there; keep the result it produced
                end
            end

            obj.pin_variant_(idx);

            obj.Capture   = [];
            obj.Recording = [];
            obj.Results   = struct();

            obj.refresh_inspectors_();
            if obj.is_open()
                obj.update_compare_plots_();
                obj.refresh_ui_();
            end
            obj.set_status_(sprintf('Variant %d of %d selected.', idx, n));
        end


        % -----------------------------------------------------------------
        function show_inspector(obj, which)
            % show_inspector(obj)
            % show_inspector(obj, "recording" | "stimulus")
            % Open (or raise) an inspector on the recording or the stimulus.
            arguments
                obj (1,1) stimgen.SpotCheck
                which (1,1) string {mustBeMember(which, ["recording", "stimulus"])} = "recording"
            end

            if which == "stimulus"
                if isempty(obj.Stimulus) || ~isvalid(obj.Stimulus)
                    obj.set_status_("No stimulus loaded.");
                    return
                end
                obj.StimInspector_ = obj.ensure_inspector_(obj.StimInspector_);
                obj.StimInspector_.set_source_provider(@() obj.stimulus_source_());
                obj.StimInspector_.show();
            else
                if isempty(obj.Recording) || ~isvalid(obj.Recording)
                    obj.set_status_("Nothing recorded yet — run a spot check first.");
                    return
                end
                obj.CaptureInspector_ = obj.ensure_inspector_(obj.CaptureInspector_);
                obj.CaptureInspector_.set_source_provider(@() obj.recording_source_());
                obj.CaptureInspector_.show();
            end
        end


        % -----------------------------------------------------------------
        function show(obj)
            % show(obj) - Bring the spot check window to the foreground.
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                figure(obj.Figure);
            end
        end


        % -----------------------------------------------------------------
        function tf = is_open(obj)
            % tf = is_open(obj) - True while the window exists.
            tf = isvalid(obj) && ~isempty(obj.Figure) && isvalid(obj.Figure);
        end


        % -----------------------------------------------------------------
        function f = Figure_(obj)
            % f = Figure_(obj)
            % The window handle, for the few callers that need the figure
            % itself rather than a control on it -- save_screenshot, and a
            % host application parenting a dialog to this window. Kept as an
            % accessor rather than a public property so nothing outside can
            % reassign it.
            f = obj.Figure;
        end


        % -----------------------------------------------------------------
        function tf = is_running(obj)
            % tf = is_running(obj) - True while a capture is in progress.
            tf = obj.Running_;
        end


        % -----------------------------------------------------------------
        function tf = can_run(obj)
            % tf = can_run(obj)
            % True when a stimulus is loaded and hardware is attached to play
            % it through.
            tf = ~isempty(obj.Stimulus) && isvalid(obj.Stimulus) ...
                && ~isempty(obj.Engine.Adapter);
        end


        % -----------------------------------------------------------------
        function set_status_(obj, messageText, options)
            % set_status_(obj, messageText)
            % set_status_(obj, messageText, isError=true)
            % Update the status line, when there is one.
            arguments
                obj (1,1) stimgen.SpotCheck
                messageText (1,1) string
                options.isError (1,1) logical = false
            end

            h = obj.handles;
            if ~isfield(h, 'StatusLabel') || isempty(h.StatusLabel) || ~isvalid(h.StatusLabel)
                return
            end
            h.StatusLabel.Text = char(messageText);
            if options.isError
                h.StatusLabel.FontColor = [0.75 0.15 0.15];
            else
                h.StatusLabel.FontColor = [0.35 0.35 0.35];
            end
            drawnow limitrate
        end


        % -----------------------------------------------------------------
        function cancel(obj)
            % cancel(obj) - Ask an in-progress capture to stop.
            obj.Engine.cancel();
            obj.set_status_("Cancelling...");
        end


        % -----------------------------------------------------------------
        function refresh_inspectors_(obj)
            % refresh_inspectors_(obj)
            % Re-read both inspectors, if they are open. They follow through
            % source providers, so this is all that is needed after either
            % signal changes.
            for h = [obj.StimInspector_, obj.CaptureInspector_]
                if ~isempty(h) && isvalid(h) && h.is_open()
                    h.refresh();
                end
            end
        end

    end % methods (public)


    % =====================================================================
    methods (Access = private)

        function finish_run_(obj)
            % Clear the in-progress flag. Called from run()'s onCleanup, so it
            % also runs when a capture errors or is cancelled -- otherwise a
            % single failure would leave the tool permanently refusing to run.
            obj.Running_ = false;
            if obj.is_open()
                obj.refresh_ui_();
            end
        end


        function [sens, source] = mic_sensitivity_(obj, stimObj)
            % [sens, source] = mic_sensitivity_(obj, stimObj)
            % The microphone sensitivity a capture is read on, and where it
            % came from.
            %
            % Engine.MicSensitivity is never missing -- it starts at a 1 V/Pa
            % placeholder -- so it is read through known_mic_sensitivity,
            % which answers NaN until a reference has been measured, entered,
            % or loaded with a calibration that had one. Read through the
            % placeholder, a fresh engine reported every level 20*log10(1/S)
            % dB off and called the difference a calibration error.
            %
            % When this engine has none, the stimulus's own calibration is the
            % next best: it is the calibration whose level the stimulus asks
            % for, and it was measured through a microphone. That is only
            % right when the same microphone chain is on the rig now, which is
            % why the source is returned for a warning to say so.
            %
            % Returns:
            %   sens   - V/Pa, or NaN when nothing has a measured sensitivity
            %   source - "engine" | "stimulus calibration" | "none"
            sens   = obj.Engine.known_mic_sensitivity();
            source = "engine";
            if isfinite(sens)
                return
            end
            if ~isempty(stimObj) && isvalid(stimObj) ...
                    && isa(stimObj.Calibration, 'stimgen.StimCalibration') ...
                    && ~isempty(stimObj.Calibration.Engine)
                sens = stimObj.Calibration.Engine.known_mic_sensitivity();
                if isfinite(sens)
                    source = "stimulus calibration";
                    return
                end
            end
            sens   = NaN;
            source = "none";
        end


        function n = variant_count_(obj)
            % Number of variant combinations the loaded stimulus has.
            info = obj.Stimulus.get_variant_info();
            n = info.NumCombinations;
        end


        function pin_variant_(obj, idx)
            % Regenerate the stimulus at combination idx (wrapping at the end)
            % and make it the one runs play. Through set_variant_index, which
            % locks the index for the regeneration -- update_signal alone
            % would select the next combination instead.
            n   = obj.variant_count_();
            idx = mod(round(idx) - 1, n) + 1;
            obj.Stimulus.set_variant_index(idx);
            if idx ~= obj.VariantIndex
                obj.VariantMeasured_ = false;
            end
            obj.VariantIndex = idx;
        end


        function sync_variant_(obj)
            % Put the stimulus back on VariantIndex if anything has moved it
            % off, or give it a waveform if it has none. Left alone otherwise:
            % regenerating a noise stimulus draws a different waveform, and
            % the one it is holding is the one being reported on.
            info = obj.Stimulus.get_variant_info();
            if isempty(obj.Stimulus.Signal) || info.ActiveIndex ~= obj.VariantIndex
                if ~isempty(obj.Stimulus.Signal)
                    stimgen.util.vprintf(2, ...
                        'SpotCheck: stimulus had moved to variant %d; restoring %d.', ...
                        info.ActiveIndex, obj.VariantIndex);
                end
                obj.pin_variant_(obj.VariantIndex);
            end
        end


        function [stimObj, label] = stimulus_source_(obj)
            % Provider for the stimulus inspector.
            stimObj = [];
            label   = obj.StimulusLabel;
            if ~isempty(obj.Stimulus) && isvalid(obj.Stimulus)
                stimObj = obj.Stimulus;
            end
        end


        function [stimObj, label] = recording_source_(obj)
            % Provider for the recording inspector.
            stimObj = [];
            label   = "Recording — " + obj.StimulusLabel;
            if ~isempty(obj.Recording) && isvalid(obj.Recording)
                stimObj = obj.Recording;
            end
        end


        function insp = ensure_inspector_(~, insp)
            % An open inspector, reusing the one given when it still exists.
            if isempty(insp) || ~isvalid(insp) || ~insp.is_open()
                insp = stimgen.StimInspector();
            end
        end


        function adapter = adapter_from_host_(obj, host)
            % Adapter from a HardwareHost, or [] with a logged reason.
            adapter = [];
            try
                adapter = host.calibrationAdapter();
            catch ME
                stimgen.util.vprintf(0, 1, ...
                    'SpotCheck: the host could not supply a calibration adapter.');
                stimgen.util.vprintf(0, 1, ME);
                obj.set_status_("Host could not supply an adapter: " + ...
                    string(ME.message), isError=true);
            end
        end

    end % methods (Access = private)


    % =====================================================================
    methods (Static)

        function label = default_label_(stimObj)
            % label = stimgen.SpotCheck.default_label_(stimObj)
            % Display label for a stimulus that was given none: its
            % DisplayName, or the bare class name when that is unset.
            %
            % Public because the local functions in load_stimulus.m need it,
            % and a local function in a class-folder file has no class access.
            label = string(stimObj.DisplayName);
            if strlength(strtrim(label)) == 0 || label == "undefined"
                parts = split(string(class(stimObj)), ".");
                label = parts(end);
            end
        end

        function u = level_unit_(r)
            % u = stimgen.SpotCheck.level_unit_(r)
            % Unit of a result's requested and measured levels: dB peSPL
            % when the stimulus was measured at its peak (a click, or a
            % peak-referenced sound file), dB SPL otherwise. Read from
            % r.stimulus.measurement_mode through stimgen.util.level_unit, so
            % a saved result is labelled the way it was measured.
            %
            % Public for the same reason as default_label_: the local
            % functions in refresh_ui_.m and run.m need it.
            mode = "rms";
            if isfield(r, 'stimulus') && isfield(r.stimulus, 'measurement_mode')
                mode = string(r.stimulus.measurement_mode);
            end
            u = stimgen.util.level_unit(mode);
        end

    end % methods (Static)


    % =====================================================================
    methods (Static, Access = private)

        function [eng, adapter, host, stimObj, label, show] = parse_args_(args)
            % Sort constructor arguments by type, then by name.
            eng = []; adapter = []; host = []; stimObj = [];
            label = ""; show = true;

            k = 1;
            while k <= numel(args)
                a = args{k};

                % A Name,Value pair starts where the positional arguments stop
                % being recognizable objects.
                if (ischar(a) && isrow(a)) || (isstring(a) && isscalar(a))
                    name = string(a);
                    if k == numel(args)
                        error('stimgen:SpotCheck:badArgs', ...
                            'The "%s" argument has no value after it.', name);
                    end
                    value = args{k+1};
                    switch lower(name)
                        case "engine",   eng     = value;
                        case "adapter",  adapter = value;
                        case "host",     host    = value;
                        case "stimulus", stimObj = value;
                        case "label",    label   = string(value);
                        case "show",     show    = logical(value);
                        otherwise
                            error('stimgen:SpotCheck:badArgs', ...
                                ['"%s" is not a stimgen.SpotCheck argument. ' ...
                                 'Expected Engine, Adapter, Host, Stimulus, ' ...
                                 'Label or Show.'], name);
                    end
                    k = k + 2;
                    continue
                end

                if isa(a, 'stimgen.calibration.Engine')
                    eng = a;
                elseif isa(a, 'stimgen.calibration.HwAdapter')
                    adapter = a;
                elseif isa(a, 'stimgen.HardwareHost')
                    host = a;
                elseif isa(a, 'stimgen.StimType')
                    stimObj = a;
                elseif isempty(a)
                    % Tolerated so a caller can pass through an unset handle.
                else
                    error('stimgen:SpotCheck:badArgs', ...
                        ['A %s was given to stimgen.SpotCheck. Expected a ' ...
                         'stimgen.calibration.Engine, a HwAdapter, a ' ...
                         'stimgen.HardwareHost or a stimgen.StimType.'], class(a));
                end
                k = k + 1;
            end
        end

    end % methods (Static, Access = private)

end
