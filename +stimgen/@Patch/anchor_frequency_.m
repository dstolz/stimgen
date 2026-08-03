function value = anchor_frequency_(obj, y, fs)
% value = anchor_frequency_(obj, y, fs)
% Resolve the LUT lookup frequency for calibration mode "Tone".
%
% A non-zero AnchorFrequency wins. Otherwise the anchor is taken from the
% output chain: the highest-frequency Oscillator or Sweep that actually feeds
% the output node, which is almost always the carrier the experimenter thinks
% of the stimulus as being at. If the chain has no frequency-bearing node
% (a pure noise or file patch), fall back to the measured spectral centroid.
%
% Returns NaN when nothing can be determined, which the calibration Engine
% treats as "use ReferenceFrequency".

value = double(obj.AnchorFrequency);
if value > 0
    return
end

% Walk the graph backwards from the output node to collect its ancestors.
labels  = obj.node_labels();
conns   = obj.Graph.Connections;
inChain = false(1, numel(labels));
outIdx  = find(labels == obj.OutputNode, 1);
if isempty(outIdx)
    value = NaN;
    return
end

inChain(outIdx) = true;
changed = true;
while changed
    changed = false;
    for k = 1:numel(conns)
        s = find(labels == conns(k).From, 1);
        t = find(labels == conns(k).To,   1);
        if ~isempty(s) && ~isempty(t) && inChain(t) && ~inChain(s)
            inChain(s) = true;
            changed    = true;
        end
    end
end

% Among contributing nodes, prefer the highest carrier frequency: for a
% modulated tone that is the carrier, not the modulator.
best = NaN;
for i = find(inChain)
    kind  = obj.Graph.Nodes(i).Kind;
    label = obj.Graph.Nodes(i).Label;
    switch kind
        case "Oscillator"
            f = double(obj.selected_value(stimgen.Patch.flat_name_(label, "Frequency")));
        case "Sweep"
            % Geometric mean of the endpoints, matching how StimType handles
            % CalibrationType "swept_sine".
            f1 = double(obj.selected_value(stimgen.Patch.flat_name_(label, "StartFrequency")));
            f2 = double(obj.selected_value(stimgen.Patch.flat_name_(label, "StopFrequency")));
            f  = sqrt(f1 * f2);
        otherwise
            continue
    end
    if isfinite(f) && f > 0 && (isnan(best) || f > best)
        best = f;
    end
end

if ~isnan(best)
    value = best;
    return
end

value = stimgen.util.spectral_centroid(y, fs);
end
