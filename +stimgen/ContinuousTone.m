classdef ContinuousTone < stimgen.Tone & stimgen.continuous.Playable

    % obj = stimgen.ContinuousTone(Name,Value,...)
    % Continuously playing pure tone.
    %
    % Package guide: documentation/stimgen_overview.md
    % Class guide: documentation/stimgen_continuous.md
    %
    % Unlike stimgen.Tone, which produces a finite gated burst, this class
    % produces a seamlessly loopable block and owns its own playback: call
    % start() and the tone sounds until stop(). Duration is therefore the
    % LOOP-BLOCK length, not the stimulus length.
    %
    %   t = stimgen.ContinuousTone;
    %   t.Fs = 48000; t.Frequency = 1000;
    %   t.start;                 % sounds indefinitely
    %   t.Frequency = 2000;      % crossfades, no click
    %   t.stop
    %
    % Seamlessness comes from snapping Frequency to the nearest whole number
    % of cycles per block, so the block joins to itself with no phase step.
    % The snapped value is reported by RealizedFrequency; the error is
    % bounded by Fs/(2*N), i.e. +/-0.5 Hz for a 1 s block at 48 kHz. Use a
    % longer Duration for finer frequency resolution.
    %
    % See also stimgen.Tone, stimgen.ContinuousNoise, stimgen.continuous.Stream

    properties (Dependent)
        % Frequency actually synthesized after cycle-snapping, Hz.
        RealizedFrequency
    end

    properties (Access = protected)
        realizedFrequency_ (1,1) double = NaN;
    end

    methods

        function obj = ContinuousTone(varargin)
            obj = obj@stimgen.Tone(varargin{:});

            obj.DisplayName = 'Continuous Tone';

            % A gate inside a looping block would fire once per lap. The
            % stream fades instead, via RampDuration.
            obj.ApplyWindow = false;

            % Sound cards do not run at the TDT default of 97656.25 Hz.
            obj.Fs = 48000;

            % One second gives 1 Hz FFT resolution, so cycle-snapping error
            % stays under half a hertz.
            obj.Duration = 1;

            obj.UserProperties = ["Frequency","SoundLevel","Duration","OnsetPhase", ...
                obj.continuous_user_properties_()];
        end

        % -----------------------------------------------------------------
        function f = get.RealizedFrequency(obj)
            f = obj.realizedFrequency_;
        end

        % -----------------------------------------------------------------
        function update_signal(obj)
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            fsValue  = double(obj.selected_value("Fs"));
            durValue = double(obj.selected_value("Duration"));
            freq     = double(obj.selected_value("Frequency"));
            onsetPhase = double(obj.selected_value("OnsetPhase"));

            nBlock = max(2, round(fsValue * durValue));

            % Snap to a whole number of cycles per block so sample nBlock+1
            % equals sample 1 in phase, making the loop seam exact.
            cycles  = max(1, round(nBlock * freq / fsValue));
            fActual = cycles * fsValue / nBlock;
            obj.realizedFrequency_ = fActual;

            if abs(fActual - freq) > 1e-9
                stimgen.util.vprintf(2, ...
                    'ContinuousTone: Frequency snapped %.4f -> %.4f Hz for a seamless %d-sample loop.', ...
                    freq, fActual, nBlock);
            end

            k = 0:nBlock-1;
            obj.Signal = sin(2.*pi.*fActual.*k./fsValue + onsetPhase);

            obj.apply_normalization;
            obj.apply_calibration;
            % No apply_gate: see the ApplyWindow note in the constructor.

            obj.refresh_stream_();
        end

    end

    % =====================================================================
    methods (Access = protected)

        function m = propMeta(obj)
            % propMeta() - Display metadata for ContinuousTone GUI properties.
            base = propMeta@stimgen.Tone(obj);
            m = obj.continuous_prop_meta_(base);
        end

        % -----------------------------------------------------------------
        function cpObj = copyElement(obj)
            % copyElement() - Copies must not share the live audio device.
            cpObj = copyElement@stimgen.Tone(obj);
            cpObj.detach_stream_();
        end

    end

end
