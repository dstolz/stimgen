function update_signal(obj)
% update_signal(obj)
% Render the component graph into Signal.
%
% One global timebase drives every node: Fs and Duration come from the Patch,
% and each component returns exactly N samples. That single rule replaces the
% per-class truncate/pad reconciliation the monolithic stimulus classes each
% do differently.
%
% Pipeline order is the package-wide normalize -> calibrate -> gate, applied
% once to the output node's waveform. Individual nodes are never normalized or
% gated: doing so would defeat modulation, since a modulator's amplitude is
% exactly what carries the information.

if ~obj.variantCycleActive_
    obj.call_update_signal_with_variant_cycle_();
    return
end

% A patch with nothing to render produces silence rather than raising. Every
% Graph edit fires this through the PostSet listener, so an intermediate state
% -- the moment after the last node is deleted, or while a preset is being
% assembled -- must not leave the object unusable. The same reasoning as
% stimgen.SoundFile's empty-catalog no-op, which exists because StimPlayer
% builds the panel and the plot immediately after construction.
nodes  = obj.Graph.Nodes;
outIdx = [];
if ~isempty(nodes) && strlength(obj.OutputNode) > 0
    outIdx = find(obj.node_labels() == obj.OutputNode, 1);
end
if isempty(outIdx)
    obj.lastOutputs_ = {};
    obj.Signal       = zeros(1, obj.N);
    stimgen.util.vprintf(2, 'Patch: no output node; generating silence.');
    return
end

ctx = struct('Fs', double(obj.selected_value("Fs")), ...
             'N',  obj.N, ...
             't',  obj.Time);

outputs  = cell(1, numel(nodes));
resolved = cell(1, numel(nodes));

for i = obj.topo_order_()
    resolved{i} = obj.resolve_params_(i, ctx, outputs, resolved);

    y = obj.components_{i}.render(ctx, resolved{i});

    if ~isnumeric(y) || ~isrow(y) || numel(y) ~= ctx.N
        error('stimgen:Patch:BadNodeOutput', ...
            'Node "%s" (%s) returned %s but the timebase requires a 1-by-%d row vector.', ...
            nodes(i).Label, nodes(i).Kind, mat2str(size(y)), ctx.N);
    end
    if ~all(isfinite(y))
        error('stimgen:Patch:BadNodeOutput', ...
            ['Node "%s" (%s) produced non-finite samples. Check for a zero or ' ...
             'negative value in a parameter that is being modulated.'], ...
            nodes(i).Label, nodes(i).Kind);
    end

    outputs{i} = y;
end

obj.lastOutputs_ = outputs;   % kept so the editor can preview any node
obj.Signal       = outputs{outIdx};

obj.apply_normalization;
obj.apply_calibration;
obj.apply_gate;
end
