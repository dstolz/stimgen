function v = apply_mode_(mode, base, m, range, depth, powerComp)
% v = stimgen.Patch.apply_mode_(mode, base, m, range, depth, powerComp)
% Apply one connection's contribution to a target parameter.
%
% Parameters:
%   mode      - one of stimgen.Patch.mode_names()
%   base      - the parameter value so far (scalar or 1-by-N)
%   m         - the source node's output (1-by-N)
%   range     - the source component's declared nominal_range, [lo hi]
%   depth     - connection Depth
%   powerComp - apply the Viemeister power correction (AM only)
%
% The source is normalized through its DECLARED range rather than its measured
% extremes, so Depth means the same thing whatever the source happens to be
% doing on this particular render -- a modulator that is momentarily quiet does
% not silently rescale the modulation.
%
% See stimgen.Patch.mode_names for the formulas.

lo = range(1);
hi = range(2);
if hi > lo
    u = (m - lo) ./ (hi - lo);   % unipolar [0 1]
else
    u = zeros(size(m));          % degenerate range: treat as silent
end
b = 2 .* u - 1;                  % bipolar [-1 1]

switch mode
    case "Add"
        v = base + depth .* b;
    case "AM"
        v = base .* (1 - depth + depth .* u);
        if powerComp
            % Equalizes total power across modulation depths so that changing
            % depth does not change loudness. Ported from stimgen.AMnoise.
            v = v .* sqrt(1 / (depth^2/2 + 1));
        end
    case "Ring"
        v = base .* b;
    case "Exp"
        v = base .* 2.^(depth .* b);
    case "Gate"
        v = base .* double(u >= depth);
    case "Direct"
        v = m;
    otherwise
        error('stimgen:Patch:UnknownMode', 'Unknown connection mode "%s".', mode);
end
end
