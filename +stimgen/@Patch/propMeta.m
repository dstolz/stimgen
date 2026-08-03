function m = propMeta(obj)
% m = propMeta(obj)
% GUI metadata for a patch: one section per node, plus routing and level.
%
% Each node contributes a section named "<Label> (<Kind>)". Those are custom
% group names, which stimgen.StimType.group_prop_meta places between Waveform
% and Level, so a patch renders in StimPlayer as
%
%   Waveform      Output Node, Edit Graph...
%   Osc1 (Oscillator)   Frequency, Amplitude, Phase, Offset, Shape
%   LFO1 (Oscillator)   Frequency, Amplitude, Phase, Offset, Shape
%   Level         Calibration Mode, Anchor Freq, Level Reference, ...
%   Timing        Duration, Window Duration, ...
%   Variant       ...
%
% with no changes to either widget generator: the parameters are dynamic
% properties, and both generators address properties by name.
%
% Every entry sets 'widget' explicitly. StimType.resolve_widget_type falls back
% to metaclass(obj).PropertyList when 'widget' is absent, and dynamic
% properties never appear there, so the fallback would infer 'text' for every
% numeric parameter.

m = struct();

% --- Routing ---
labels = obj.node_labels();
if isempty(labels)
    items = {' '};   % uidropdown rejects an empty Items list
else
    items = cellstr(labels);
end
m.OutputNode = struct('label','Output Node', 'widget','dropdown', ...
    'items',{items}, 'group','Waveform', 'order',10);

% A propMeta 'button' is an action, not a property: the field name is only a
% widget Tag and 'callback' names a public no-argument method.
m.EditGraph = struct('label','Signal Graph', 'widget','button', ...
    'text','Edit Graph...', 'callback','edit_graph', ...
    'group','Waveform', 'order',20);

% --- One section per node ---
for i = 1:numel(obj.Graph.Nodes)
    node    = obj.Graph.Nodes(i);
    defs    = obj.components_{i}.param_defs();
    names   = string(fieldnames(defs))';
    section = char(node.Label + " (" + node.Kind + ")");

    for nm = names
        d = defs.(nm);
        if strcmp(d.widget, 'none')
            continue   % e.g. FileSource.Catalog: a struct, edited in the editor
        end

        e = struct('label', d.label, 'widget', d.widget, ...
                   'group', section, 'order', d.order);
        if isfield(d,'format'),    e.format    = d.format;    end
        if isfield(d,'limits'),    e.limits    = d.limits;    end
        if isfield(d,'items'),     e.items     = d.items;     end
        if isfield(d,'itemsData'), e.itemsData = d.itemsData; end
        if d.scale ~= 1,           e.scale     = d.scale;     end

        m.(char(stimgen.Patch.flat_name_(node.Label, nm))) = e;
    end
end

% --- Level policy ---
m.CalibrationMode = struct('label','Calibration Mode', 'widget','dropdown', ...
    'items',["Filtered" "Tone" "None"], 'group','Level', 'order',5);
m.AnchorFrequency = struct('label','Anchor Freq (Hz, 0 = auto)', 'widget','numeric', ...
    'format','%.1f Hz', 'limits',[0 1e6], 'group','Level', 'order',6);
m.LevelReference = struct('label','Level Reference', 'widget','dropdown', ...
    'items',["absmax" "rms" "peak"], 'group','Level', 'order',7);

m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.StimType(obj));
end
