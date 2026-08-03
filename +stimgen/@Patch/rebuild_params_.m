function rebuild_params_(obj)
% rebuild_params_(obj)
% Synchronize the dynamic parameter properties with the current Graph.
%
% Called from set.Graph. Creates a dynamic property <Label>_<Param> for every
% parameter of every node, removes the ones whose node or parameter no longer
% exists, and PRESERVES the value of every parameter that survives -- editing
% the graph in the patch editor must not silently reset tuned parameters.
%
% Component objects are likewise reused when a node keeps its label and kind,
% so their internal caches (NoiseSource's filter cache, FileSource's waveform
% cache) survive an unrelated edit elsewhere in the graph.
%
% Each dynamic property is created SetObservable/AbortSet and wired to
% StimType.onPropertyChanged. StimType.create_listeners cannot do this for us:
% it walks metaclass(obj).PropertyList, which never contains dynamic
% properties.

if obj.rebuilding_
    return
end
obj.rebuilding_ = true;
cleanup = onCleanup(@() set_rebuilding_false_(obj));

nodes = obj.Graph.Nodes;

% --- Reuse component objects where the node kept its label and kind ---
oldLabels = obj.componentLabels_;
newComponents = cell(1, numel(nodes));
newLabels     = string.empty(1,0);
for i = 1:numel(nodes)
    hit = [];
    if ~isempty(oldLabels)
        hit = find(oldLabels == nodes(i).Label, 1);
        if ~isempty(hit) && obj.components_{hit}.Kind ~= nodes(i).Kind
            hit = [];
        end
    end
    if isempty(hit)
        newComponents{i} = feval("stimgen.components." + nodes(i).Kind);
    else
        newComponents{i} = obj.components_{hit};
    end
    newLabels(i) = string(nodes(i).Label); %#ok<AGROW>
end
obj.components_      = newComponents;
obj.componentLabels_ = newLabels;

% --- Desired parameter set ---
wanted   = string.empty(1,0);
defaults = {};
mcPatch  = ?stimgen.Patch;
reserved = string({mcPatch.PropertyList.Name});
for i = 1:numel(nodes)
    defs  = newComponents{i}.param_defs();
    names = string(fieldnames(defs))';
    for p = names
        fn = stimgen.Patch.flat_name_(nodes(i).Label, p);
        if any(reserved == fn)
            error('stimgen:Patch:InvalidNodeLabel', ...
                ['Node "%s" would produce parameter "%s", which collides with a ' ...
                 'built-in stimulus property. Rename the node.'], nodes(i).Label, fn);
        end
        wanted(end+1)   = fn;                            %#ok<AGROW>
        defaults{end+1} = defs.(p).default;              %#ok<AGROW>
    end
end

% --- Drop properties that are no longer wanted ---
for k = numel(obj.paramProps_):-1:1
    name = obj.paramProps_(k);
    if any(wanted == name)
        continue
    end
    if ~isempty(obj.paramListeners_{k}) && isvalid(obj.paramListeners_{k})
        delete(obj.paramListeners_{k});
    end
    mp = findprop(obj, char(name));
    if ~isempty(mp) && isvalid(mp)
        delete(mp);
    end
    obj.paramProps_(k)     = [];
    obj.paramListeners_(k) = [];
end

% --- Add the missing ones, leaving survivors untouched ---
for k = 1:numel(wanted)
    name = wanted(k);
    if any(obj.paramProps_ == name)
        continue
    end
    mp = obj.addprop(char(name));
    mp.SetObservable = true;
    mp.AbortSet      = true;
    obj.(char(name))  = defaults{k};

    obj.paramProps_(end+1)     = name;
    obj.paramListeners_{end+1} = addlistener(obj, char(name), 'PostSet', ...
                                             @obj.onPropertyChanged);
end

% --- Reorder to graph order, then republish UserProperties ---
[~, order] = ismember(wanted, obj.paramProps_);
obj.paramProps_     = obj.paramProps_(order);
obj.paramListeners_ = obj.paramListeners_(order);

% Graph must come first: fromStruct, load_bank and the constructor all assign
% in UserProperties order, and the nodes have to exist before their parameters
% can be restored. OutputNode follows for the same reason.
obj.UserProperties = ["Graph", "OutputNode", obj.paramProps_, ...
                      "CalibrationMode", "AnchorFrequency", "LevelReference", ...
                      "SoundLevel", "Duration", "WindowDuration", "ApplyWindow"];

obj.lastOutputs_ = {};

% If the output node was removed, fall back to the last node so the patch
% still renders rather than erroring on every subsequent update.
if strlength(obj.OutputNode) == 0 || ~any(obj.node_labels() == obj.OutputNode)
    if isempty(nodes)
        obj.OutputNode = "";
    else
        obj.OutputNode = string(nodes(end).Label);
    end
end
end


function set_rebuilding_false_(obj)
obj.rebuilding_ = false;
end
