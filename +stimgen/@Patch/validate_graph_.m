function g = validate_graph_(g)
% g = stimgen.Patch.validate_graph_(g)
% Normalize and check a topology struct before it is accepted.
%
% Checks every invariant the renderer and the flattening layer rely on, so that
% failures surface at assignment with an actionable message rather than deep
% inside a render. Node labels are checked here; collisions between a FLATTENED
% parameter name and a real property are checked in rebuild_params_, which is
% where the property namespace is actually known.

if ~isstruct(g) || ~isscalar(g)
    error('stimgen:Patch:InvalidGraph', 'Graph must be a scalar struct.');
end

base = stimgen.Patch.empty_graph();
for f = string(fieldnames(base))'
    if ~isfield(g, f)
        g.(f) = base.(f);
    end
end

% --- Nodes ---
kinds = stimgen.components.list();
seen  = string.empty(1,0);
for i = 1:numel(g.Nodes)
    label = string(g.Nodes(i).Label);
    kind  = string(g.Nodes(i).Kind);

    if ~isvarname(char(label))
        error('stimgen:Patch:InvalidNodeLabel', ...
            ['Node label "%s" is not a valid MATLAB identifier. Labels become ' ...
             'part of a parameter name, so they must start with a letter and ' ...
             'contain only letters, digits and underscores.'], label);
    end
    if any(seen == label)
        error('stimgen:Patch:DuplicateNodeLabel', ...
            'Two nodes are labelled "%s". Node labels must be unique.', label);
    end
    if ~any(kinds == kind)
        error('stimgen:Patch:UnknownKind', ...
            'Unknown component kind "%s". Available: %s.', kind, strjoin(kinds, ', '));
    end
    seen(end+1) = label; %#ok<AGROW>

    pos = g.Nodes(i).Position;
    if isempty(pos) || numel(pos) ~= 2 || ~all(isfinite(pos))
        % Lay unplaced nodes out on a coarse grid so a graph built from a
        % script still opens sensibly in the editor.
        pos = [0.15 + 0.22*mod(i-1,4), 0.80 - 0.25*floor((i-1)/4)];
    end
    g.Nodes(i).Label    = label;
    g.Nodes(i).Kind     = kind;
    g.Nodes(i).Position = reshape(double(pos), 1, 2);
end

% --- Connections ---
modes = stimgen.Patch.mode_names();
for k = 1:numel(g.Connections)
    c     = g.Connections(k);
    from  = string(c.From);
    to    = string(c.To);
    param = string(c.Param);

    if ~any(seen == from)
        error('stimgen:Patch:UnknownNode', ...
            'Connection %d starts at "%s", which is not a node in this patch.', k, from);
    end
    if ~any(seen == to)
        error('stimgen:Patch:UnknownNode', ...
            'Connection %d ends at "%s", which is not a node in this patch.', k, to);
    end

    comp = feval("stimgen.components." + g.Nodes(seen == to).Kind);
    if ~comp.is_modulatable(param)
        mp = comp.modulatable_params();
        if isempty(mp)
            detail = "it has no modulatable parameters";
        else
            detail = "modulatable parameters are: " + strjoin(mp, ", ");
        end
        error('stimgen:Patch:NotModulatable', ...
            'Node "%s" (%s) cannot be modulated on "%s"; %s.', to, comp.Kind, param, detail);
    end

    mode = string(c.Mode);
    if ~any(modes == mode)
        error('stimgen:Patch:UnknownMode', ...
            'Unknown connection mode "%s". Available: %s.', mode, strjoin(modes, ", "));
    end

    if ~isscalar(c.Depth) || ~isfinite(c.Depth)
        error('stimgen:Patch:InvalidDepth', ...
            'Connection %d ("%s" -> "%s.%s") needs a finite scalar Depth.', ...
            k, from, to, param);
    end

    g.Connections(k).From            = from;
    g.Connections(k).To              = to;
    g.Connections(k).Param           = param;
    g.Connections(k).Mode            = mode;
    g.Connections(k).Depth           = double(c.Depth);
    g.Connections(k).PowerCompensate = logical(c.PowerCompensate);
end

% Reject cycles here rather than at render time. Render is reached through the
% Graph PostSet listener, and MATLAB turns an error thrown inside a listener
% callback into a warning -- so a cycle detected there would not reach the
% caller and the patch would be left holding a graph it cannot render.
stimgen.Patch.topo_order_for_(g);
end
