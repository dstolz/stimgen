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
    % existing subclass satisfies the contract unchanged.
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
