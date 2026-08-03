classdef Oscillator < stimgen.components.Component
% stimgen.components.Oscillator
% Periodic waveform generator with modulatable frequency, amplitude and phase.
%
% This one node subsumes both stimgen.Tone and stimgen.FMtone: a constant
% Frequency gives a pure tone, and a modulator connected to Frequency gives
% frequency modulation. Connected to Amplitude instead, the same modulator
% gives amplitude modulation. Used at a low rate it is an LFO; used at an
% audio rate it is a carrier -- there is no distinction in the code.
%
% Parameters:
%   Frequency  - Hz (modulatable)
%   Amplitude  - linear gain (modulatable)
%   Phase      - starting phase in degrees (modulatable)
%   Offset     - DC offset added after scaling by Amplitude (modulatable)
%   Shape      - sine | square | triangle | sawtooth

    properties (Constant)
        Kind        = "Oscillator";
        Description = "Sine/square/triangle/saw with modulatable frequency, amplitude and phase";
    end

    methods

        function d = param_defs(~)
            pd = @stimgen.components.Component.pdef;
            d = struct();
            d.Frequency = pd('Frequency (Hz)', 1000, 'format','%.2f Hz', ...
                'limits',[0 1e6], 'modulatable',true, 'order',10, ...
                'doc','Carrier frequency. Modulate this for FM.');
            d.Amplitude = pd('Amplitude', 1, 'format','%.3f', ...
                'modulatable',true, 'order',20, ...
                'doc','Linear gain. Modulate this for AM, tremolo or gating.');
            d.Phase = pd('Phase (deg)', 0, 'format','%.1f deg', ...
                'modulatable',true, 'order',30, ...
                'doc','Starting phase in degrees.');
            d.Offset = pd('Offset', 0, 'format','%.3f', ...
                'modulatable',true, 'order',35, ...
                'doc','DC offset added to the waveform after scaling by Amplitude.');
            d.Shape = pd('Shape', "sine", ...
                'items',["sine" "square" "triangle" "sawtooth"], 'order',40);
        end

        function y = render(obj, ctx, p)
            N  = ctx.N;
            f  = obj.expand(p.Frequency, N);
            a  = obj.expand(p.Amplitude, N);
            ph = deg2rad(obj.expand(p.Phase, N));

            % Instantaneous phase by trapezoidal integration of f over the
            % ACTUAL sample times in ctx.t, not over assumed 1/Fs steps.
            % StimType.Time is linspace(0, D-1/Fs, round(Fs*D)), whose step
            % equals 1/Fs only when Fs*D happens to be an integer -- which it
            % is not at the default Fs of 97656.25 Hz. Integrating over dt
            % makes a constant Frequency reproduce sin(2*pi*f*t) exactly, so
            % this node agrees with stimgen.Tone and stimgen.FMtone by
            % construction rather than to within a rounding error.
            % Integrating the DEVIATION from the mean, rather than f itself,
            % keeps cumsum's rounding error proportional to the modulation
            % depth instead of to the carrier frequency. An unmodulated
            % oscillator then has df == 0 and reduces to the closed form
            % 2*pi*f*t with no accumulation at all.
            fbar = mean(f);
            df   = f - fbar;
            if N > 1
                dt  = diff(ctx.t);
                idf = [0, cumsum((df(1:end-1) + df(2:end)) ./ 2 .* dt)];
            else
                idf = 0;
            end
            phase = 2*pi .* (fbar .* (ctx.t - ctx.t(1)) + idf) + ph;

            switch string(p.Shape)
                case "sine"
                    y = sin(phase);
                case "square"
                    y = sign(sin(phase));
                    y(y == 0) = 1;
                case "triangle"
                    y = (2/pi) .* asin(max(-1, min(1, sin(phase))));
                case "sawtooth"
                    y = 2 .* (mod(phase./(2*pi) + 0.5, 1) - 0.5);
                otherwise
                    error('stimgen:components:Oscillator:UnknownShape', ...
                        'Unknown oscillator shape "%s".', string(p.Shape));
            end

            o = obj.expand(p.Offset, N);
            y = obj.fit(y .* a, N) + o;
        end

    end % methods

end
