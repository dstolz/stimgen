function p = resolve_params_(obj, idx, ctx, outputs, resolved)
% p = resolve_params_(obj, idx, ctx, outputs, resolved)
% Build the resolved parameter struct for node idx.
%
% Each parameter starts at its base value, read through selected_value so the
% active variant combination applies -- this is the seam that lets a graph
% parameter be vectorized like any other stimulus property. Inbound connections
% are then applied in graph order, so two modulators targeting the same
% parameter compose predictably.
%
% Parameters:
%   idx      - node index
%   ctx      - timebase struct (Fs, N, t)
%   outputs  - 1-by-N cell of already-rendered node outputs
%   resolved - 1-by-N cell of already-resolved parameter structs, needed
%              because a source's nominal_range can depend on its own
%              parameters (PulseTrain.Polarity)
%
% Returns:
%   p - struct of parameter name -> scalar or 1-by-N vector

node   = obj.Graph.Nodes(idx);
comp   = obj.components_{idx};
defs   = comp.param_defs();
names  = string(fieldnames(defs))';
labels = obj.node_labels();

p = struct();
for nm = names
    p.(nm) = obj.selected_value(stimgen.Patch.flat_name_(node.Label, nm));
end

conns = obj.Graph.Connections;
for k = 1:numel(conns)
    c = conns(k);
    if c.To ~= node.Label
        continue
    end

    s = find(labels == c.From, 1);
    if isempty(s) || isempty(outputs{s})
        % topo_order_ guarantees sources render first, so this only happens
        % for a connection whose source was removed mid-edit.
        continue
    end

    srcComp  = obj.components_{s};
    srcRange = srcComp.nominal_range(resolved{s});

    p.(c.Param) = stimgen.Patch.apply_mode_(c.Mode, p.(c.Param), outputs{s}, ...
                                            srcRange, c.Depth, c.PowerCompensate);
end
end
