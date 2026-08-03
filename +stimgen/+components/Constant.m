classdef Constant < stimgen.components.Component
% stimgen.components.Constant
% DC source.
%
% Useful as a routable scalar: connect it to another node's parameter to add a
% fixed offset, or use it as a Mixer input to introduce a DC term. Because
% Value is itself modulatable, a Constant also serves as a relay point where
% several modulators can be summed before driving a single target parameter.
%
% Parameters:
%   Value - the constant level (modulatable)

    properties (Constant)
        Kind        = "Constant";
        Description = "DC source; a routable scalar or modulator summing point";
    end

    methods

        function d = param_defs(~)
            pd = @stimgen.components.Component.pdef;
            d = struct();
            d.Value = pd('Value', 1, 'format','%.4f', 'modulatable',true, 'order',10);
        end

        function y = render(obj, ctx, p)
            y = obj.fit(obj.expand(p.Value, ctx.N), ctx.N);
        end

    end % methods

end
