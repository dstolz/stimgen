classdef CapturedSignal < stimgen.StimType

    % obj = stimgen.CapturedSignal(waveform, fs)
    % obj = stimgen.CapturedSignal(waveform, fs, Name, Value, ...)
    % A recorded waveform wearing the StimType interface.
    %
    % Class guide: documentation/stimgen_SpotCheck.md
    %
    % Everything else in +stimgen synthesizes a signal from parameters. This
    % carries one that was already measured -- a microphone record -- so that
    % the tools built around StimType can read it. stimgen.StimInspector is the
    % reason it exists: the inspector characterizes a stimgen.StimType, and a
    % recording that arrives as a bare vector cannot be handed to it. Wrapping
    % the vector is a great deal less invasive than teaching the inspector a
    % second kind of input, and it buys plot/play/spectrogram for free.
    %
    % stimgen.SoundFile is the nearest relative -- it reads rather than
    % synthesizes too -- but it still owns a catalog and a level. This owns
    % nothing but samples.
    %
    % NOTHING IS DONE TO THE SAMPLES. update_signal copies Waveform into Signal
    % and stops: no normalization, no gate, no calibration voltage. That is the
    % entire point. A recording is evidence, and the measured amplitude in
    % volts is the evidence; a class that renormalized it would destroy the one
    % number the capture was made to obtain. ApplyCalibration and ApplyWindow
    % default to false to match, and are not offered in the generated panel.
    %
    % Duration is derived from the waveform and its sample rate, exactly as
    % stimgen.SoundFile derives it from the selected file, so Time, N and
    % Signal always agree.
    %
    % This class lives in a class folder rather than as a loose +stimgen/*.m
    % file so that stimgen.StimType.list() does not glob it: a recording is not
    % a stimulus and must never be offered in a stimulus dropdown. See
    % @StimType/list.m, which reaches only the loose files.
    %
    % Not a persistence format. Waveform is deliberately absent from
    % UserProperties -- a vector there would be read as a variant axis and
    % expanded into one combination per sample -- so it does not survive
    % toStruct/fromStruct or a .spl bank. Save a capture with
    % stimgen.SpotCheck.save_results, which writes the record with the
    % provenance that makes it worth keeping.
    %
    % Properties:
    %   Waveform    - the captured samples, in volts
    %   SourceLabel - what was played to produce them
    %   Provenance  - free-form struct describing the acquisition
    %
    % Example:
    %   c = stimgen.CapturedSignal(micRecord, 48000, SourceLabel="4 kHz tone");
    %   stimgen.StimInspector(c, c.SourceLabel);
    %
    % See also: stimgen.SpotCheck, stimgen.StimInspector, stimgen.StimType

    properties (SetObservable, AbortSet)
        % The captured record, in volts. SetObservable so that assigning a new
        % record refreshes Signal and any attached plot through the base
        % class's listener, the same way a stimulus parameter does.
        Waveform (1,:) double {mustBeReal} = []
    end

    properties
        % What was played to produce this record. Free text; the inspector
        % header and the SpotCheck result file both read it.
        SourceLabel (1,1) string = ""

        % Whatever the capturing code wants recorded about the acquisition --
        % conduction delay, noise floor, the stimulus that drove it. Never
        % parsed here; carried so that a record and the circumstances it was
        % taken under do not become separated.
        Provenance (1,1) struct = struct()
    end

    properties (Constant)
        IsMultiObj      = false;
        % Nothing here is ever calibrated: the samples are already the
        % measurement. The name is outside the LUT families on purpose, so a
        % stray apply_calibration call could not silently pick one.
        CalibrationType = "none";
        % Declared because the base class requires it, and unreachable:
        % update_signal never calls apply_normalization.
        Normalization   = "absmax";
    end

    properties (Access = private)
        % Guards the Duration write inside update_signal, so the SetObservable
        % listener does not re-enter. Same device as stimgen.SoundFile.
        syncingDuration_ (1,1) logical = false
    end

    methods

        function obj = CapturedSignal(waveform, fs, varargin)
            % obj = stimgen.CapturedSignal()
            % obj = stimgen.CapturedSignal(waveform, fs)
            % obj = stimgen.CapturedSignal(waveform, fs, Name, Value, ...)
            %
            % Parameters:
            %   waveform - (1,:) double captured samples, in volts
            %   fs       - (1,1) double sample rate of that record, in Hz
            %
            % Defaults are prepended to varargin so a caller's Name,Value pair
            % still wins, per the package-wide constructor rule.
            args = {};
            if nargin >= 2 && ~isempty(fs)
                args = [args, {'Fs', fs}];
            end
            if nargin >= 1 && ~isempty(waveform)
                args = [args, {'Waveform', reshape(double(waveform), 1, [])}];
            end

            obj = obj@stimgen.StimType( ...
                'DisplayName', 'Captured Signal', ...
                ... % A recording is reported as recorded. Both would alter the
                ... % samples, and there is nothing here they could correctly act on.
                'ApplyCalibration', false, ...
                'ApplyWindow', false, ...
                ... % Waveform is NOT listed: UserProperties is what
                ... % get_variant_source_values_ scans for variant axes, and a
                ... % record of a million samples would become a million
                ... % combinations. See the class help.
                'UserProperties', "SoundLevel", ...
                args{:}, varargin{:});

            % Generated here rather than left for the first reader. The base
            % constructor assigns properties before it attaches listeners, so
            % nothing would otherwise have published the record into Signal,
            % and a carrier handed a waveform that then reports an empty
            % Signal is a trap. A synthesized stimulus has a reason to defer
            % -- its parameters are still being set -- and this has none: the
            % samples are already final.
            if ~isempty(obj.Waveform)
                obj.update_signal();
            end
        end


        function update_signal(obj)
            % update_signal(obj)
            % Publish the captured record as Signal, untouched.
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            y = reshape(obj.Waveform, 1, []);

            if isempty(y)
                % Must be a no-op rather than an error: a bare
                % stimgen.CapturedSignal is constructed before it has a record,
                % and the GUIs build a panel and a signal plot immediately.
                obj.Signal = [];
                return
            end

            obj.sync_duration_(numel(y) ./ double(obj.selected_value("Fs")));

            obj.Signal = y;
        end


        function s = duration_s(obj)
            % s = duration_s(obj) - Length of the captured record in seconds.
            s = numel(obj.Waveform) ./ double(obj.Fs);
        end


        function text = current_parameter_summary(obj)
            % text = current_parameter_summary(obj)
            % Lead with what was captured; there are no parameters to report,
            % because nothing here was generated from any.
            if strlength(obj.SourceLabel) > 0
                head = "Recording of " + obj.SourceLabel;
            else
                head = "Recording";
            end
            text = head + sprintf(', %d samples (%.1f ms) at %.7g Hz', ...
                numel(obj.Waveform), obj.duration_s * 1e3, obj.Fs);
        end

    end % methods (public)


    methods (Access = protected)

        function onPropertyChanged(obj, src, event)
            % onPropertyChanged(obj, src, event)
            % Override: Duration is derived from the record and written from
            % inside update_signal. Suppress the listener for that one write so
            % it does not re-enter.
            if obj.syncingDuration_ && ~isempty(src) && string(src.Name) == "Duration"
                return
            end
            onPropertyChanged@stimgen.StimType(obj, src, event);
        end


        function m = propMeta(obj)
            % propMeta(obj)
            % Only the base entries that mean anything for a record. There are
            % no parameters of its own to edit: every one would be a request to
            % alter evidence.
            m = struct();

            base = propMeta@stimgen.StimType(obj);
            % Duration follows the record, and there is no read-only widget, so
            % it is removed rather than shown -- the same reasoning as
            % stimgen.SoundFile.
            for f = ["Duration", "WindowDuration", "ApplyWindow", ...
                     "ApplyCalibration", "SoundLevel"]
                if isfield(base, f)
                    base = rmfield(base, f);
                end
            end

            m = stimgen.StimType.merge_prop_meta(m, base);
        end

    end % methods (Access = protected)


    methods (Access = private)

        function sync_duration_(obj, newDur)
            % sync_duration_(obj, newDur) - Set Duration from the record length.
            if ~isfinite(newDur) || newDur <= 0
                return
            end
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

    end % methods (Access = private)

end
