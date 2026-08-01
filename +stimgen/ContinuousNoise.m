classdef ContinuousNoise < stimgen.Noise & stimgen.continuous.Playable

    % obj = stimgen.ContinuousNoise(Name,Value,...)
    % Continuously playing band-limited noise.
    %
    % Package guide: documentation/stimgen_overview.md
    % Class guide: documentation/stimgen_continuous.md
    %
    % Unlike stimgen.Noise, which produces a finite gated burst, this class
    % produces a seamlessly loopable block and owns its own playback: call
    % start() and the noise sounds until stop(). Duration is therefore the
    % LOOP-BLOCK length, not the stimulus length.
    %
    %   n = stimgen.ContinuousNoise;
    %   n.Fs = 48000; n.HighPass = 2000; n.LowPass = 8000;
    %   n.start; pause(5); n.stop
    %
    % The waveform is synthesized in the FREQUENCY domain rather than by the
    % randn + filter path in stimgen.Noise. That matters: a time-domain FIR
    % has a startup transient and leaves the block edges mismatched, so the
    % loop would tick once per lap. An inverse FFT of a band-limited
    % random-phase spectrum is periodic by construction, so it does not.
    %
    % Loop length sets the frequency resolution: bins are spaced Fs/N apart,
    % so a narrow band needs a longer Duration to contain any bins at all.
    %
    % See also stimgen.Noise, stimgen.ContinuousTone, stimgen.continuous.Stream

    methods

        function obj = ContinuousNoise(varargin)
            obj = obj@stimgen.Noise(varargin{:});

            obj.DisplayName = 'Continuous Noise';

            % A gate inside a looping block would fire once per lap. The
            % stream fades instead, via RampDuration.
            obj.ApplyWindow = false;

            % Sound cards do not run at the TDT default of 97656.25 Hz.
            obj.Fs = 48000;
            obj.Duration = 1;

            % The calibration equalization FIR is folded into the spectrum
            % below, as a magnitude response. Let apply_calibration do the
            % LUT level scaling but not re-filter in the time domain, which
            % would reintroduce the very transient this class avoids.
            obj.suppressCalFilter_ = true;

            obj.UserProperties = ["SoundLevel","Duration","HighPass","LowPass", ...
                obj.continuous_user_properties_()];
        end

        % -----------------------------------------------------------------
        function update_signal(obj)
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            fsValue  = double(obj.selected_value("Fs"));
            durValue = double(obj.selected_value("Duration"));
            highPass = double(obj.selected_value("HighPass"));
            lowPass  = double(obj.selected_value("LowPass"));

            if lowPass <= highPass
                error('stimgen:ContinuousNoise:InvalidBand', ...
                    'LowPass must be greater than HighPass.');
            end

            nBlock = max(2, round(fsValue * durValue));

            % Positive-frequency bins, excluding DC and Nyquist so the
            % 'symmetric' inverse transform stays exactly real.
            nHalf = floor((nBlock - 1) / 2);
            binHz = (1:nHalf) .* (fsValue / nBlock);
            keep  = binHz >= highPass & binHz <= min(lowPass, fsValue/2);

            if ~any(keep)
                error('stimgen:ContinuousNoise:EmptyBand', ...
                    ['No FFT bins fall between %.1f and %.1f Hz for a %.4f s block at %.1f Hz ' ...
                     '(bin spacing %.2f Hz). Increase Duration to narrow the bin spacing.'], ...
                    highPass, lowPass, durValue, fsValue, fsValue/nBlock);
            end

            mag = keep .* obj.calibration_magnitude_(binHz, fsValue);

            X = zeros(1, nBlock);
            X(2:nHalf+1) = mag .* exp(1i .* 2 .* pi .* rand(1, nHalf));
            obj.Signal = ifft(X, nBlock, 'symmetric');

            obj.apply_normalization;
            obj.apply_calibration;
            % No apply_gate: see the ApplyWindow note in the constructor.

            obj.refresh_stream_();
        end

    end

    % =====================================================================
    methods (Access = protected)

        function mag = calibration_magnitude_(obj, binHz, fsValue)
            % calibration_magnitude_(binHz, fsValue) - Equalization gain per bin.
            %
            % Shaping the spectrum directly is exactly a circular convolution
            % with the calibration filter, so unlike the time-domain filter in
            % stimgen.StimType/apply_calibration it preserves the loop seam.
            % Only the magnitude is used: the phase would just delay the block,
            % which is meaningless for a loop of random-phase noise, and
            % dropping it removes any group-delay compensation to get wrong.
            mag = ones(1, numel(binHz));

            if ~obj.ApplyCalibration
                return
            end
            C = obj.Calibration;
            if ~isa(C, 'stimgen.StimCalibration') || isempty(C.CalibrationData) ...
                    || ~isfield(C.CalibrationData, 'filter') || isempty(C.CalibrationData.filter)
                return
            end

            try
                mag = abs(freqz(C.CalibrationData.filter, binHz, fsValue)).';
            catch ME
                stimgen.util.vprintf(1, 1, ...
                    'ContinuousNoise: calibration filter response failed, using flat spectrum.');
                stimgen.util.vprintf(2, 1, ME);
                mag = ones(1, numel(binHz));
            end
        end

        % -----------------------------------------------------------------
        function m = propMeta(obj)
            % propMeta() - Display metadata for ContinuousNoise GUI properties.
            base = propMeta@stimgen.Noise(obj);
            m = obj.continuous_prop_meta_(base);
        end

        % -----------------------------------------------------------------
        function cpObj = copyElement(obj)
            % copyElement() - Copies must not share the live audio device.
            cpObj = copyElement@stimgen.Noise(obj);
            cpObj.detach_stream_();
        end

    end

end
