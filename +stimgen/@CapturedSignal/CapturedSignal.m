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
    % THE SCALE TRAVELS WITH THE SAMPLES. A record is volts at the converter;
    % what makes it pascals is the microphone sensitivity of the chain it came
    % through, and that is a fact about the capture, not about whichever
    % calibration happens to be loaded later. So the sensitivity is copied in
    % at capture time (MicSensitivity) rather than looked up through a
    % calibration handle -- a StimCalibration can be reloaded underneath a
    % recording, and a record must not silently change level when it is.
    % stimgen.StimInspector reads it to show the record in Pa and dB SPL; NaN
    % leaves the record in volts, which is always true.
    %
    % Properties:
    %   Waveform       - the captured samples, in volts
    %   SourceLabel    - what was played to produce them
    %   Provenance     - free-form struct describing the acquisition
    %   MicSensitivity - V/Pa the record was captured through; NaN = unknown
    %   NoiseRecord    - silence recorded just before the stimulus, in volts
    %   NoiseRms       - rms of all the silence acquired, in volts
    %   Request        - what the stimulus asked for (stimgen.util.level_request)
    %   Warnings       - everything that qualifies the record
    %   Played         - a copy of the stimulus as it was played
    %
    % Example:
    %   c = stimgen.CapturedSignal(micRecord, 48000, SourceLabel="4 kHz tone", ...
    %       MicSensitivity=0.05);
    %   stimgen.StimInspector(c, c.SourceLabel);    % Pa and dB SPL
    %
    %   % From an acquisition, with everything the inspector can use:
    %   cap = eng.play_and_capture(toneObj.Signal);
    %   c   = stimgen.CapturedSignal.from_capture(cap, Stimulus=toneObj, ...
    %       MicSensitivity=eng.MicSensitivity, Spectral=eng.spectral_options());
    %
    % See also: stimgen.SpotCheck, stimgen.StimInspector, stimgen.StimType,
    %           stimgen.StimPlayer.capture_stim

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

        % Microphone sensitivity, in V/Pa, of the chain the record came
        % through: the one number that turns it into sound pressure. Copied
        % in at capture time -- see the class help. NaN means unknown, and
        % the record is read in volts.
        MicSensitivity (1,1) double = NaN

        % Silence recorded immediately before the stimulus, on the same
        % input and the same scale as Waveform: the noise floor the record
        % sat on. Empty when the capture took none. Not in UserProperties,
        % for the same reason Waveform is not.
        NoiseRecord (1,:) double {mustBeReal} = []

        % RMS of all the silence acquired, in volts -- pooled over every
        % repeat, so it can be longer than NoiseRecord. NaN when none was.
        NoiseRms (1,1) double = NaN

        % What the stimulus that produced this record asked for and how its
        % level is measured: stimgen.util.level_request's struct, plus the
        % spectral_window/spectral_fft_length the calibration measures
        % with. An empty struct when nothing is known about the stimulus.
        Request (1,1) struct = struct()

        % Everything that qualifies the record -- a clipped input, a delay
        % search that hit its bound, a level too close to the floor to
        % trust. Written by from_capture; read by the inspector.
        Warnings (1,:) string = string.empty(1, 0)

        % A copy of the stimulus as it was played, taken at capture time --
        % its parameters, its rate, its waveform -- so the record can say
        % what produced it after the original has been edited or deleted.
        % [] when that is not known. A snapshot, never the live object: a
        % bank item edited after the capture must not rewrite the record's
        % description of itself.
        Played = []
    end

    properties (Constant)
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


        function set.MicSensitivity(obj, v)
            % NaN (unknown) or a positive, finite V/Pa. Zero or a negative
            % sensitivity is not a microphone, and Inf would read every level
            % as -Inf dB SPL without saying why.
            if ~(isnan(v) || (isfinite(v) && v > 0))
                error('stimgen:CapturedSignal:badSensitivity', ...
                    ['MicSensitivity must be a positive, finite V/Pa, or NaN ' ...
                     'when it is not known; got %g.'], v);
            end
            obj.MicSensitivity = v;
        end


        function tf = has_spl_scale(obj)
            % tf = has_spl_scale(obj)
            % True when the record can be read in pascals and dB SPL: a
            % microphone sensitivity came with it.
            tf = isfinite(obj.MicSensitivity) && obj.MicSensitivity > 0;
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


    methods (Static)

        function obj = from_capture(capture, options)
            % obj = stimgen.CapturedSignal.from_capture(capture)
            % obj = stimgen.CapturedSignal.from_capture(capture, Name=Value)
            % Wrap an Engine.play_and_capture result with everything the
            % inspector and a saved result need to read it on their own.
            %
            % The one place an acquisition becomes a CapturedSignal, so
            % stimgen.SpotCheck and stimgen.StimPlayer.capture_stim hand the
            % inspector the same thing: the stimulus-span response as the
            % record, the pre-stimulus silence as its noise floor, the scale,
            % what was asked for, and the warnings that qualify it.
            %
            % Parameters:
            %   capture        - struct from stimgen.calibration.Engine.play_and_capture
            %   Stimulus       - stimgen.StimType that was played ([] if unknown).
            %                    Read for the Request and copied into
            %                    Played; the object itself is never modified.
            %   MicSensitivity - V/Pa of the recording chain; NaN (default)
            %                    leaves the record in volts
            %   Spectral       - stimgen.calibration.SpectralOptions the
            %                    calibration measures with, recorded in
            %                    Request so a tone is measured as its table was
            %   SourceLabel    - what was played, in words
            %   Provenance     - struct merged over the acquisition's own
            %                    provenance fields (its fields win)
            %
            % Returns:
            %   obj - stimgen.CapturedSignal
            arguments
                capture (1,1) struct
                options.Stimulus = []
                options.MicSensitivity (1,1) double = NaN
                options.Spectral = []
                options.SourceLabel (1,1) string = ""
                options.Provenance (1,1) struct = struct()
            end

            req = struct();
            played = [];
            if ~isempty(options.Stimulus)
                mustBeA(options.Stimulus, 'stimgen.StimType');
                played = copy(options.Stimulus);
                req = stimgen.util.level_request(options.Stimulus);
                spec = options.Spectral;
                if isempty(spec)
                    spec = stimgen.calibration.SpectralOptions();
                end
                req.spectral_window     = string(spec.Window);
                req.spectral_fft_length = double(spec.FftLength);
            end

            prov = struct( ...
                'fs',             capture.fs, ...
                'pre_delay_s',    capture.pre_delay_s, ...
                'post_delay_s',   capture.post_delay_s, ...
                'repeats',        capture.repeats, ...
                'delay_s',        capture.delay_s, ...
                'delay_sd_s',     capture.delay_sd_s, ...
                'delay_at_bound', capture.delay_at_bound, ...
                'align_quality',  capture.align_quality, ...
                'noise_rms_v',    capture.noise.rms_v, ...
                'headroom',       capture.headroom, ...
                'dc_removed_v',   capture.dc_removed_v, ...
                'ac_coupled_hz',  capture.ac_coupled_hz, ...
                'measuredOn',     capture.measuredOn);
            extra = fieldnames(options.Provenance);
            for k = 1:numel(extra)
                prov.(extra{k}) = options.Provenance.(extra{k});
            end

            warnings = [stimgen.CapturedSignal.request_warnings(req), ...
                        stimgen.CapturedSignal.capture_warnings(capture)];
            if ~(isfinite(options.MicSensitivity) && options.MicSensitivity > 0)
                warnings(end+1) = "No microphone sensitivity came with this " + ...
                    "record (no calibration was loaded), so it is shown in " + ...
                    "volts. Load a calibration and capture again for dB SPL.";
            end

            obj = stimgen.CapturedSignal(capture.response, capture.fs, ...
                'SourceLabel',    options.SourceLabel, ...
                'Provenance',     prov, ...
                'MicSensitivity', options.MicSensitivity, ...
                'NoiseRecord',    reshape(double(capture.noise.record), 1, []), ...
                'NoiseRms',       double(capture.noise.rms_v), ...
                'Request',        req, ...
                'Warnings',       warnings, ...
                'Played',         played);
        end


        function w = capture_warnings(capture)
            % w = stimgen.CapturedSignal.capture_warnings(capture)
            % What qualifies an Engine.play_and_capture record: a delay
            % search that hit its bound, clipping on either side of the
            % speaker, a response too close to its noise floor, and the
            % pessimism averaging puts into an SNR.
            %
            % Shared with stimgen.SpotCheck, whose results carry the same
            % sentences, so a capture and a spot check of one acquisition
            % say the same things about it.
            %
            % Parameters:
            %   capture - struct from stimgen.calibration.Engine.play_and_capture
            %
            % Returns:
            %   w - (1,:) string, empty when there is nothing to say
            w = string.empty(1, 0);

            snrDb = stimgen.CapturedSignal.capture_snr_db(capture);

            if capture.delay_at_bound
                w(end+1) = sprintf( ...
                    "The response delay reached the %.0f ms search bound, so the record " + ...
                    "was probably cut in the wrong place. Raise Post Delay above the " + ...
                    "rig's round-trip latency and run again.", capture.post_delay_s * 1e3);
            end

            h = capture.headroom;
            if h.responseClippingLikely
                w(end+1) = sprintf( ...
                    "The recording looks clipped (peak %.4g V, %.1f%% of samples flat at " + ...
                    "the peak). Reduce the input gain; every level here is understated.", ...
                    h.responsePeakV, 100 * h.responseFlatTopFraction);
            end

            if h.excitationClippingLikely
                w(end+1) = sprintf( ...
                    "The excitation peaks at %.4g V, above the %.4g V output " + ...
                    "ceiling, so the converter clipped it before the speaker saw it.", ...
                    h.excitationPeakV, h.assumedFullScaleV);
            end

            if isfinite(snrDb) && snrDb < 10
                w(end+1) = sprintf( ...
                    "Only %.1f dB above the noise floor in this record. The level and " + ...
                    "every distortion figure below are dominated by noise.", snrDb);
            end

            if capture.repeats > 1
                w(end+1) = sprintf( ...
                    "%d acquisitions were averaged, which lowers noise on the response " + ...
                    "but not on the noise floor it is compared with, so the %.1f dB SNR " + ...
                    "is pessimistic by up to %.1f dB.", capture.repeats, snrDb, ...
                    10 * log10(capture.repeats));
            end
        end


        function w = request_warnings(req)
            % w = stimgen.CapturedSignal.request_warnings(req)
            % Why the requested level of a stimulus may not be a real one:
            % calibration switched off, or asked for with nothing to apply.
            %
            % Parameters:
            %   req - struct from stimgen.util.level_request, or an empty
            %         struct when the stimulus is unknown (nothing to say)
            %
            % Returns:
            %   w - (1,:) string
            w = string.empty(1, 0);
            if ~isfield(req, 'applies_calibration')
                return
            end
            if ~req.applies_calibration
                w(end+1) = "Apply Calibration is off for this stimulus, so its " + ...
                    "waveform is normalized rather than scaled to volts. The measured " + ...
                    "level is real, but Sound Level is nominal and the error is meaningless.";
            elseif ~req.has_calibration_data
                w(end+1) = "The stimulus asks for calibration but carries no " + ...
                    "calibration data, so it was played un-scaled. The measured level is " + ...
                    "real; the requested one is not.";
            end
        end


        function snrDb = capture_snr_db(capture)
            % snrDb = stimgen.CapturedSignal.capture_snr_db(capture)
            % Broadband rms of the response over the rms of the silence
            % before it, in dB; NaN when no silence was recorded. A ratio of
            % two voltages on one input, so it needs no calibration.
            noiseV = capture.noise.rms_v;
            if ~(isfinite(noiseV) && noiseV > 0)
                snrDb = nan;
                return
            end
            y = capture.response(isfinite(capture.response));
            if isempty(y)
                snrDb = nan;
                return
            end
            snrDb = 20 * log10(sqrt(mean(y .^ 2)) / noiseV);
        end

    end % methods (Static)


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
