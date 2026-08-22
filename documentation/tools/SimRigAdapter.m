classdef SimRigAdapter < stimgen.calibration.HwAdapter
    % SimRigAdapter
    % A synthetic speaker + microphone + room, for producing documentation
    % screenshots without a rig. Nothing here is used at run time; it exists
    % so the calibration GUI can be photographed with plausible data on it.
    %
    % The model, in the order the chain applies it:
    %   drive volts -> clip at MaxOutputVoltage
    %               -> loudspeaker magnitude response (Pa per V)
    %               -> weak 2nd/3rd harmonic distortion
    %               -> booth impulse response (delay, early reflections, tail)
    %               -> microphone sensitivity (V per Pa)
    %               -> noise floor (broadband + 1/f + mains hum)
    %
    % record() returns the noise floor alone, or the acoustic calibrator's
    % 1 kHz tone when CalibratorOn is set -- which is what makes
    % calibrate_reference and measure_background behave differently.

    properties
        Fs_             (1,1) double = 48000
        MicVPerPa       (1,1) double = 0.050   % 50 mV/Pa, a typical 1/4" measurement mic
        MidbandPaPerV   (1,1) double = 0.63    % ~90 dB SPL at 1 V drive, midband
        DelaySeconds    (1,1) double = 2.90e-3 % speaker-to-mic flight + converter latency
        EarlyDelays     (1,:) double = [3.5e-3 5.2e-3 8.1e-3]  % re direct arrival
        EarlyGains      (1,:) double = [0.045 -0.028 0.018]
        ReverbT60       (1,1) double = 0.060   % s -- a sound-attenuating booth, not a room
        ReverbGain      (1,1) double = 0.008   % diffuse tail re direct sound
        NoiseVrms       (1,1) double = 32e-6   % ~30 dB SPL broadband at 50 mV/Pa
        HumVrms         (1,1) double = 9e-6    % 60 Hz + harmonics
        Hd2             (1,1) double = 0.006   % 2nd harmonic, fraction of fundamental
        Hd3             (1,1) double = 0.0035  % 3rd harmonic
        MaxOutputVolts  (1,1) double = 10
        CalibratorOn    (1,1) logical = false  % seat the acoustic calibrator on the mic
        CalibratorLevel (1,1) double = 94      % dB SPL
        CalibratorFreq  (1,1) double = 1000    % Hz
        Seed            (1,1) double = 20260821
    end

    properties (Access = private)
        Rng_
        HCache_ = struct('nf', {}, 'H', {})   % minimum-phase response per transform length
        RoomIr_ (1,:) double = []
    end

    methods
        function obj = SimRigAdapter(varargin)
            for k = 1:2:numel(varargin)
                obj.(varargin{k}) = varargin{k+1};
            end
            obj.Rng_ = RandStream('threefry', 'Seed', obj.Seed);
        end

        function Fs = sample_rate(obj)
            Fs = obj.Fs_;
        end

        function response = record(obj, nSamples)
            % Nothing is played. Either the room alone, or the calibrator.
            arguments
                obj
                nSamples (1,1) double {mustBeInteger, mustBePositive}
            end
            response = obj.noise_(nSamples);
            if obj.CalibratorOn
                t = (0:nSamples-1) / obj.Fs_;
                pa = stimgen.calibration.Engine.ReferencePressurePa ...
                    * 10^(obj.CalibratorLevel/20) * sqrt(2);   % amplitude, not rms
                v  = pa * obj.MicVPerPa;
                tone = v * sin(2*pi*obj.CalibratorFreq*t);
                % A calibrator is clean but not perfect.
                tone = tone + 0.002*v*sin(2*pi*2*obj.CalibratorFreq*t);
                response = response + tone;
            end
        end

        function response = play_and_record(obj, signal)
            arguments
                obj
                signal (1,:) double
            end
            n = numel(signal);
            x = max(min(signal, obj.MaxOutputVolts), -obj.MaxOutputVolts);

            pa = obj.speaker_(x);                      % volts -> pascals
            pa = pa + obj.Hd2 * sign(pa) .* pa.^2 / max(max(abs(pa)), eps) ...
                    + obj.Hd3 * pa.^3 / max(max(abs(pa)), eps)^2;

            pa = obj.room_(pa);

            response = pa * obj.MicVPerPa + obj.noise_(n);
        end
    end

    methods (Access = private)
        function y = speaker_(obj, x)
            % Frequency-domain magnitude shaping. The response is made
            % MINIMUM PHASE rather than left zero-phase: a zero-phase filter
            % rings symmetrically about t=0, and that acausal precursor
            % arrives before the propagation delay this class applies
            % separately -- which is exactly what the engine's first-arrival
            % latency estimator would then report. A real speaker is roughly
            % minimum phase anyway, so this is the more faithful model as
            % well as the one that leaves the delay measurable.
            n  = numel(x);
            nf = 2^nextpow2(max(2*n, 1024));
            H  = obj.min_phase_(nf);
            y  = real(ifft(fft(x(:), nf) .* H));
            y  = y(1:n).';
        end

        function H = min_phase_(obj, nf)
            hit = find([obj.HCache_.nf] == nf, 1);
            if ~isempty(hit)
                H = obj.HCache_(hit).H;
                return
            end
            f = (0:nf-1)' * obj.Fs_ / nf;
            f(f > obj.Fs_/2) = obj.Fs_ - f(f > obj.Fs_/2);
            mag = obj.magnitude_(max(f, 1e-3));

            % Minimum phase from the real cepstrum: fold the anticausal half
            % of log|H| onto the causal one and re-exponentiate.
            c = real(ifft(log(max(mag, 1e-12))));
            w = zeros(nf, 1);
            w(1) = 1;
            w(2:nf/2) = 2;
            w(nf/2 + 1) = 1;
            H = exp(fft(c .* w));

            obj.HCache_(end+1) = struct('nf', nf, 'H', H);
        end

        function H = magnitude_(obj, f)
            % dB shape: 2nd-order high-pass at 120 Hz, a broad box resonance
            % near 3.2 kHz, a suckout at 9 kHz, and a top-octave
            % rolloff -- a small closed-field speaker, roughly.
            hp   = 40*log10(f./120 ./ sqrt(1 + (f./120).^2));
            res  = 5.5 * exp(-((log2(f/3200)).^2) / (2*0.55^2));
            dip  = -5.0 * exp(-((log2(f/9000)).^2) / (2*0.28^2));
            top  = -12*log10(1 + (f./19000).^4);
            ripl = 1.2*sin(2*pi*log2(max(f,20))/2.6) + 0.6*sin(2*pi*log2(max(f,20))/1.1 + 1.1);
            dB   = hp + res + dip + top + ripl;
            H    = 10.^(dB/20) * obj.MidbandPaPerV;
        end

        function y = room_(obj, x)
            % Convolve with the booth: the direct arrival at DelaySeconds, a
            % few discrete early reflections behind it, and a short diffuse
            % tail. The tail is what makes the swept sine's RT60/C50/DRR
            % readouts mean something -- a single reflection leaves them
            % reporting a room with no decay at all.
            h = obj.room_ir_();
            n = numel(x);
            nf = 2^nextpow2(n + numel(h));
            y = real(ifft(fft(x, nf) .* fft(h, nf)));
            y = y(1:n);
        end

        function h = room_ir_(obj)
            if ~isempty(obj.RoomIr_)
                h = obj.RoomIr_;
                return
            end
            fs = obj.Fs_;
            tailLen = round(1.5 * obj.ReverbT60 * fs);
            h = zeros(1, round(obj.DelaySeconds*fs) + tailLen + 16);
            d0 = round(obj.DelaySeconds * fs) + 1;
            h(d0) = 1;
            for k = 1:numel(obj.EarlyDelays)
                h(d0 + round(obj.EarlyDelays(k)*fs)) = ...
                    h(d0 + round(obj.EarlyDelays(k)*fs)) + obj.EarlyGains(k);
            end
            t = (0:tailLen-1) / fs;
            env = 10.^(-3 * t / obj.ReverbT60);
            tail = obj.ReverbGain * env .* randn(obj.Rng_, 1, tailLen);
            idx = d0 + (0:tailLen-1);
            h(idx) = h(idx) + tail;
            obj.RoomIr_ = h;
        end

        function v = noise_(obj, n)
            w = randn(obj.Rng_, 1, n);
            % 1/f tilt below ~1 kHz, on top of the flat floor.
            nf = 2^nextpow2(max(n, 64));
            f  = (0:nf-1) * obj.Fs_ / nf;
            f(f > obj.Fs_/2) = obj.Fs_ - f(f > obj.Fs_/2);
            tilt = sqrt(1 + (700 ./ max(f, 1)).^1.9);
            p = randn(obj.Rng_, 1, nf);
            pink = real(ifft(fft(p) .* tilt));
            pink = pink(1:n) / max(std(pink(1:n)), eps);
            v = obj.NoiseVrms * (0.42*w + 0.92*pink);

            t = (0:n-1) / obj.Fs_;
            v = v + obj.HumVrms * ( sin(2*pi*60*t + 0.4) ...
                                  + 0.45*sin(2*pi*120*t + 1.9) ...
                                  + 0.22*sin(2*pi*180*t + 0.7) );
        end
    end
end
