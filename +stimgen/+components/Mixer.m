classdef Mixer < stimgen.components.Component
% stimgen.components.Mixer
% Weighted sum of up to four inputs.
%
% Audio routing needs no special machinery in a patch: the inputs are ordinary
% modulatable parameters that default to 0, so connecting a node to In1 with
% connection mode "Direct" simply replaces that parameter with the source
% waveform. This is what makes two-tone complexes, noise-plus-tone stimuli and
% harmonic stacks expressible.
%
% Parameters:
%   In1..In4     - input signals (modulatable; default 0 = unconnected)
%   Gain1..Gain4 - per-input linear weight

    properties (Constant)
        Kind        = "Mixer";
        Description = "Weighted sum of up to four inputs";
        NumInputs   = 4;
    end

    methods

        function d = param_defs(obj)
            pd = @stimgen.components.Component.pdef;
            d = struct();
            for k = 1:obj.NumInputs
                d.(sprintf('In%d', k)) = pd(sprintf('In %d', k), 0, ...
                    'format','%.4f', 'modulatable',true, 'order',10*k, ...
                    'doc','Connect a node here with mode "Direct" to route its output in.');
                d.(sprintf('Gain%d', k)) = pd(sprintf('Gain %d', k), 1, ...
                    'format','%.4f', 'order',10*k + 5);
            end
        end

        function y = render(obj, ctx, p)
            N = ctx.N;
            y = zeros(1, N);
            for k = 1:obj.NumInputs
                g = double(p.(sprintf('Gain%d', k)));
                if all(g == 0)
                    continue
                end
                y = y + obj.expand(g, N) .* obj.expand(p.(sprintf('In%d', k)), N);
            end
            y = obj.fit(y, N);
        end

    end % methods

end
