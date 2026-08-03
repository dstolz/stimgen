function apply_gate(obj)
% apply_gate(obj)
% Apply onset/offset cosine-squared window to obj.Signal.
% Has no effect when ApplyWindow is false or temporarilyDisableSignalMods is true.

applyWindowValue = logical(obj.get_selected_property_value_("ApplyWindow"));
if ~applyWindowValue || obj.temporarilyDisableSignalMods, return; end

g = obj.Window;

n = length(g);

% A gate longer than the signal cannot be applied. This is reachable
% transiently whenever a property that reinterprets WindowDuration is
% assigned before WindowDuration itself catches up -- switching
% Tone.WindowMethod, or fromStruct restoring the two in either order --
% so shrink the window to fit rather than failing on the index.
nSignal = numel(obj.Signal);
if n > nSignal
    if n < 2 || nSignal < 2
        return
    end
    nFit = nSignal - rem(nSignal, 2);
    g = interp1(linspace(0, 1, n), g, linspace(0, 1, nFit));
    n = nFit;
end

ga = g(1:n/2);
gb = g(n/2+1:end);

obj.Signal(1:n/2) = obj.Signal(1:n/2) .* ga;
obj.Signal(end-n/2+1:end) = obj.Signal(end-n/2+1:end) .* gb;
