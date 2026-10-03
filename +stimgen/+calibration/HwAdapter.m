classdef (Abstract) HwAdapter < handle
    % stimgen.calibration.HwAdapter
    % Abstract hardware adapter for calibration I/O.
    %
    % Concrete subclasses supply the sample rate and implement play_and_record()
    % to send an excitation waveform to hardware and return the microphone
    % response. Implementations are expected to validate their required
    % capabilities at construction time and error immediately if anything is
    % absent (fail-fast).
    %
    % record() is concrete and defaults to a silent play_and_record, so an
    % existing subclass satisfies the contract unchanged. So are full_scale()
    % and input_range(), which default to NaN ("not known"): the Engine then
    % judges headroom against its own MaxOutputVoltage exactly as it did
    % before they existed. A backend whose converters have a known range
    % should override them.
    %
    % See also: stimgen.calibration.WindowsSoundCardAdapter, stimgen.calibration.Engine,
    %           documentation/stimgen_calibration.md

    methods
        function response = record(obj, nSamples)
            % response = record(obj, nSamples)
            % Acquire nSamples of microphone input without driving the speaker.
            %
            % This is what the reference measurement uses: the reference tone
            % comes from an acoustic calibrator seated on the microphone, so
            % playing anything would only contaminate the recording.
            %
            % The default is a silent play_and_record, which is correct for any
            % duplex device -- zeros go out while the input is captured.
            % Override when a backend can acquire without arming its output.
            %
            % Parameters:
            %   nSamples - (1,1) double number of samples to acquire
            %
            % Returns:
            %   response - (1,:) double recorded microphone signal
            arguments
                obj
                nSamples (1,1) double {mustBeInteger, mustBePositive}
            end
            response = obj.play_and_record(zeros(1, nSamples));
        end

        function v = full_scale(~)
            % v = full_scale(obj)
            % Largest |signal| play_and_record can reproduce, in the units the
            % signal is given in (volts for an analog rig, digital full scale
            % for a sound card).
            %
            % The Engine judges excitation headroom against the smaller of
            % this and its MaxOutputVoltage, refuses test points that need
            % more, and checks play_and_capture waveforms against it. NaN, the
            % default, means "not known" and leaves MaxOutputVoltage alone in
            % charge -- the behaviour every adapter had before this method
            % existed.
            %
            % Returns:
            %   v - (1,1) double positive full scale, or NaN when unknown
            v = NaN;
        end

        function v = input_range(~)
            % v = input_range(obj)
            % Largest |response| the input can record before it saturates, in
            % the units play_and_record returns.
            %
            % The Engine judges a response's headroom and its clipping flag
            % against this. NaN, the default, means "not known": the Engine
            % then falls back to MaxOutputVoltage, which is what it judged
            % the input against before this method existed -- right for a rig
            % whose input and output ranges match (+/-10 V on both sides of a
            % TDT RZ), and the only assumption available otherwise.
            %
            % Returns:
            %   v - (1,1) double positive input range, or NaN when unknown
            v = NaN;
        end
    end

    methods (Abstract)
        % Fs = sample_rate(obj)
        % Return the hardware sample rate in Hz.
        Fs = sample_rate(obj)

        % response = play_and_record(obj, signal)
        % Play signal (1-D double, unit-amplitude, already scaled by
        % ExcitationVoltage) through the hardware output and simultaneously
        % record the microphone response.
        %
        % Parameters:
        %   signal   - (1,:) double output waveform
        %
        % Returns:
        %   response - (1,:) double recorded microphone signal
        response = play_and_record(obj, signal)
    end
end
