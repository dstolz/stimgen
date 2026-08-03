function build_inspector_(obj)
% build_inspector_(obj)
% Build the parameter editor for the current selection.
%
% Node parameters are read straight out of the Patch's propMeta, keyed by the
% flattened name, so the widget type, label, display scale, format and limits
% are exactly the ones StimPlayer's panel would use. There is no second copy
% of the widget rules to keep in step.

panel = obj.h.InspectorPanel;
delete(panel.Children);

if obj.selKind == "node" && obj.selIdx >= 1 && obj.selIdx <= numel(obj.geom)
    local_node_inspector(obj, panel);
elseif obj.selKind == "conn" && obj.selIdx >= 1 && obj.selIdx <= numel(obj.Patch.Graph.Connections)
    local_conn_inspector(obj, panel);
else
    g = uigridlayout(panel, [1 1]);
    uilabel(g, 'Text', 'Select a node or a wire.', ...
        'HorizontalAlignment', 'center', 'FontColor', [0.45 0.45 0.5]);
end
end


% =========================================================================

function local_node_inspector(obj, panel)
label = obj.geom(obj.selIdx).Label;
comp  = obj.Patch.component(label);
defs  = comp.param_defs();
names = string(fieldnames(defs))';
meta  = obj.Patch.get_prop_meta();

isFile = comp.Kind == "FileSource";
nRows  = 2 + numel(names) + double(isFile);

g = uigridlayout(panel, [nRows 2]);
g.ColumnWidth = {'1.1x', '1x'};
g.RowHeight   = [{28, 28}, repmat({26}, 1, nRows-2)];
g.Scrollable  = 'on';
g.Padding     = [6 6 6 6];
g.RowSpacing  = 3;

% Node label (rename)
uilabel(g, 'Text', 'Label:', 'HorizontalAlignment', 'right');
uieditfield(g, 'Value', char(label), ...
    'ValueChangedFcn', @(s,~) local_rename(obj, label, s));

% Output-node toggle
uilabel(g, 'Text', 'Is Output:', 'HorizontalAlignment', 'right');
cb = uicheckbox(g, 'Text', '', 'Value', obj.Patch.OutputNode == label);
cb.ValueChangedFcn = @(s,~) local_set_output(obj, label, s);

for nm = names
    d  = defs.(nm);
    fn = char(stimgen.Patch.flat_name_(label, nm));

    if strcmp(d.widget, 'none')
        continue
    end

    lbl = uilabel(g, 'Text', [d.label ':'], 'HorizontalAlignment', 'right');
    if ~isempty(d.doc)
        lbl.Tooltip = d.doc;
    end

    pm = meta.(fn);
    sc = stimgen.StimType.display_scale(pm);

    switch d.widget
        case 'checkbox'
            w = uicheckbox(g, 'Text', '', 'Value', obj.Patch.(fn));
        case 'dropdown'
            w = uidropdown(g, 'Items', pm.items);
            if isfield(pm, 'itemsData'), w.ItemsData = pm.itemsData; end
            w.Value = obj.Patch.(fn);
        case 'numeric'
            % A plain text field, not a numeric one: these accept expressions
            % and vectors, which is how a graph parameter becomes a variant
            % axis. The text is eval'd, so a vector literal needs its brackets
            % ("[1000 2000 4000]", "1000:1000:4000", "Osc1_Frequency/400").
            w = uieditfield(g, 'Value', local_fmt(obj.Patch.(fn) * sc));
            w.Tooltip = 'Accepts an expression or a vector literal, e.g. [1000 2000 4000]; a vector creates variants.';
        otherwise
            w = uieditfield(g, 'Value', char(string(obj.Patch.(fn))));
    end
    w.ValueChangedFcn = @(s,e) local_set_param(obj, fn, d.widget, sc, s, e);
end

if isFile
    uilabel(g, 'Text', 'Files:', 'HorizontalAlignment', 'right');
    uibutton(g, 'Text', 'Browse...', ...
        'ButtonPushedFcn', @(~,~) local_browse(obj, label));
end
end


function local_conn_inspector(obj, panel)
c = obj.Patch.Graph.Connections(obj.selIdx);
[modes, descs] = stimgen.Patch.mode_names();

g = uigridlayout(panel, [5 2]);
g.ColumnWidth = {'1.1x', '1x'};
g.RowHeight   = repmat({26}, 1, 5);
g.Padding     = [6 6 6 6];
g.RowSpacing  = 3;

uilabel(g, 'Text', 'Connection:', 'HorizontalAlignment', 'right');
uilabel(g, 'Text', char(c.From + " -> " + c.To), 'Interpreter', 'none');

uilabel(g, 'Text', 'Parameter:', 'HorizontalAlignment', 'right');
uilabel(g, 'Text', char(c.Param), 'Interpreter', 'none');

uilabel(g, 'Text', 'Mode:', 'HorizontalAlignment', 'right');
dd = uidropdown(g, 'Items', cellstr(modes), 'Value', char(c.Mode));
dd.Tooltip = cellstr(descs);
dd.ValueChangedFcn = @(s,~) local_set_conn(obj, 'Mode', string(s.Value));

uilabel(g, 'Text', 'Depth:', 'HorizontalAlignment', 'right');
uieditfield(g, 'numeric', 'Value', c.Depth, ...
    'ValueChangedFcn', @(s,~) local_set_conn(obj, 'Depth', s.Value));

uilabel(g, 'Text', 'Power Comp:', 'HorizontalAlignment', 'right');
pc = uicheckbox(g, 'Text', '', 'Value', c.PowerCompensate);
pc.Tooltip = 'Equalize power across AM depths (Viemeister correction).';
pc.ValueChangedFcn = @(s,~) local_set_conn(obj, 'PowerCompensate', s.Value);
end


% ------------------------- callbacks -------------------------

function local_set_param(obj, fn, widget, sc, src, event)
try
    switch widget
        case 'numeric'
            % Same path as StimPlayer's panel: parse as an expression in
            % display units, then divide by the scale exactly once.
            obj.Patch.(fn) = obj.Patch.evalPropertyExpression(fn, char(string(event.Value))) / sc;
            src.Value = local_fmt(obj.Patch.(fn) * sc);
        case 'checkbox'
            obj.Patch.(fn) = event.Value;
        otherwise
            % A dropdown/text widget's Value is always char, even when the
            % property it backs is a string scalar (e.g. Oscillator.Shape).
            % Assigning char directly would flip numel() from 1 to the
            % string's length, which get_selected_property_value_ would then
            % misinterpret as a vectorized/variant property.
            obj.Patch.(fn) = string(event.Value);
    end
    obj.set_status_(string(fn) + " updated.", "info");
catch ME
    src.Value = local_revert_value(obj, fn, widget, sc, event);
    obj.set_status_(ME.message, "error");
end
obj.refresh_all_();
end

function v = local_revert_value(obj, fn, widget, sc, event)
try
    switch widget
        case 'numeric',  v = local_fmt(obj.Patch.(fn) * sc);
        case 'checkbox', v = logical(obj.Patch.(fn));
        case 'dropdown', v = obj.Patch.(fn);
        otherwise,       v = char(string(obj.Patch.(fn)));
    end
catch
    v = event.PreviousValue;
end
end

function local_set_conn(obj, field, value)
try
    g = obj.Patch.Graph;
    g.Connections(obj.selIdx).(field) = value;
    obj.Patch.Graph = g;
catch ME
    obj.set_status_(ME.message, "error");
end
obj.refresh_all_();
end

function local_rename(obj, oldLabel, src)
try
    obj.Patch.rename_node(oldLabel, string(src.Value));
    obj.set_status_("Renamed to " + string(src.Value) + ".", "info");
catch ME
    src.Value = char(oldLabel);
    obj.set_status_(ME.message, "error");
end
obj.refresh_all_();
end

function local_set_output(obj, label, src)
try
    if src.Value
        obj.Patch.OutputNode = label;
    end
    src.Value = obj.Patch.OutputNode == label;  % cannot have no output
catch ME
    obj.set_status_(ME.message, "error");
end
obj.refresh_all_();
end

function local_browse(obj, label)
[fn, pn] = uigetfile({'*.wav;*.flac;*.ogg;*.mp3;*.m4a', 'Audio Files'}, ...
    'Select audio files', 'MultiSelect', 'on');
if isequal(fn, 0), return, end
if ischar(fn), fn = {fn}; end

cat = obj.Patch.(char(stimgen.Patch.flat_name_(label, "Catalog")));
if ~isfield(cat, 'Path') || isempty(cat.Path)
    cat = stimgen.components.FileSource.empty_catalog();
end

for k = 1:numel(fn)
    ffn = fullfile(pn, fn{k});
    try
        info = audioinfo(ffn);
    catch ME
        obj.set_status_("Could not read " + string(fn{k}) + ": " + string(ME.message), "error");
        continue
    end
    cat.Label{end+1}         = fn{k};
    cat.Path{end+1}          = ffn;
    cat.SourceFs(end+1)      = info.SampleRate;
    cat.NativeSamples(end+1) = info.TotalSamples;
    cat.NChannels(end+1)     = info.NumChannels;
    cat.Embedded(end+1)      = false;
    cat.Data{end+1}          = [];
end

obj.Patch.(char(stimgen.Patch.flat_name_(label, "Catalog"))) = cat;
obj.set_status_(string(numel(cat.Path)) + " file(s) in the catalog.", "info");
obj.refresh_all_();
end

function s = local_fmt(v)
% Shared with the Output panel's Duration field, so both format the same way.
s = stimgen.PatchEditor.format_field_value_(v);
end
