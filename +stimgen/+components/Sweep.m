classdef Sweep < stimgen.components.Component
% stimgen.components.Sweep
% Log-sine or linear frequency chirp.
%
% Ports the two generators from stimgen.SweptSine, which were already written
% as stateless functions of (t, f1, f2, T). As a graph node the chirp can be
% gated, amplitude-modulated or mixed with other sources, which the monolithic
% class cannot do.
%
% Note this is a swept carrier, not a modulator: its output is an audio-rate
% waveform. To sweep some other node's frequency parameter instead, connect a
% slow Oscillator or a Constant to that parameter.
%
% Parameters:
%   StartFrequency, StopFrequency - sweep endpoints in Hz
%   ChirpType                     - log-sine | linear
%   Amplitude                     - linear gain (modulatable)

    properties (Constant)
        Kind        = "Sweep";
        Description = "Log-sine or linear frequency chirp";
    end

    methods

        function d = param_defs(~)
            pd = @stimgen.components.Component.pdef;
            d = struct();
            d.StartFrequency = pd('Start Freq (Hz)', 100, 'format','%.1f Hz', ...
                'limits',[1 1e6], 'order',10);
            d.StopFrequency = pd('Stop Freq (Hz)', 20000, 'format','%.1f Hz', ...
                'limits',[1 1e6], 'order',20);
            d.ChirpType = pd('Chirp Type', "log-sine", ...
                'items',["log-sine" "linear"], 'order',30);
            d.Amplitude = pd('Amplitude', 1, 'format','%.3f', ...
                'modulatable',true, 'order',40);
        end

        function y = render(obj, ctx, p)
            N  = ctx.N;
            t  = ctx.t;
            f1 = double(p.StartFrequency);
            f2 = double(p.StopFrequency);

            if f1 >= f2
                error('stimgen:components:Sweep:BadFreqRange', ...
                    'Start frequency (%.1f Hz) must be below stop frequency (%.1f Hz).', f1, f2);
            end

            T = t(end);
            if T <= 0
                y = zeros(1, N);
                return
            end

            switch string(p.ChirpType)
                case "log-sine"
                    K        = 2*pi*f1*T / log(f2/f1);
                    exponent = log(f2/f1) .* t ./ T;
                    exponent = max(exponent, -1e-16);
                    y        = sin(K .* (exp(exponent) - 1));
                case "linear"
                    y = sin(2*pi .* (f1.*t + (f2-f1).*t.^2 ./ (2*T)));
                otherwise
                    error('stimgen:components:Sweep:UnknownChirpType', ...
                        'Unknown chirp type "%s".', string(p.ChirpType));
            end

            y = obj.fit(y .* obj.expand(p.Amplitude, N), N);
        end

    end % methods

end
