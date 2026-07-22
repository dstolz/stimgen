function on_bank_selection_changed(obj, src, ~)
% on_bank_selection_changed(obj, src) - Rebuild the parameter panel when listbox selection changes.
% Clears existing contents and builds labeled sections (Waveform, Level,
% Timing, Variant) inside a single scrollable grid layout. Section
% membership and in-section order come from each property's propMeta
% 'group'/'order' metadata (see stimgen.StimType.group_prop_meta), so a
% subclass that tags a new property (e.g. Tone.WindowMethod as 'Timing')
% appears in the right section automatically.

if isempty(src.ItemsData) || isempty(src.Value)
    obj.clear_tabs_;
    return
end

idx = src.Value;
if idx < 1 || idx > numel(obj.StimPlayObjs)
    obj.clear_tabs_;
    return
end

sp      = obj.StimPlayObjs(idx);
stimObj = sp.CurrentStimObj;

% Sync Reps field
obj.handles.RepsField.Value = sp.Reps;

% Clear param panel
pnl = obj.handles.ParamPanel;
delete(pnl.Children);

% --- Gather parameter metadata, grouped into logical sections ---
% Section definitions: {title, metaStruct, propNames}
meta         = stimObj.get_prop_meta();
metaSections = stimgen.StimType.group_prop_meta(meta);

sections = cell(1, numel(metaSections));
for s = 1:numel(metaSections)
    sTitle    = metaSections{s}{1};
    sPropList = metaSections{s}{2};
    sMeta     = struct();
    for k = 1:numel(sPropList)
        sMeta.(sPropList{k}) = meta.(sPropList{k});
    end
    sections{s} = {sTitle, sMeta, sPropList};
end

% --- Compute row heights ---
ROW_TOP  = 28;   % top bank label row
ROW_GAP  = 8;    % gap after top row
ROW_HDR  = 28;   % section header
ROW_PROP = 28;   % per-property row
ROW_SEP  = 10;   % gap after each section
rowHeights = {ROW_TOP, ROW_GAP};
for s = 1:numel(sections)
    rowHeights{end+1} = ROW_HDR;
    for p = 1:numel(sections{s}{3})
        rowHeights{end+1} = ROW_PROP;
    end
    rowHeights{end+1} = ROW_SEP;
end

% --- Build scrollable grid ---
g = uigridlayout(pnl, 'Scrollable', 'on');
g.ColumnWidth = {'1x', '2x'};
g.RowHeight   = rowHeights;
g.Padding     = [6 6 6 6];
g.RowSpacing  = 2;

mc = metaclass(stimObj);
pl = mc.PropertyList;

row = 1;

% Top row: editable bank label
lbl = uilabel(g, 'Text', 'Bank Label:', 'HorizontalAlignment', 'right');
lbl.Layout.Row    = row;
lbl.Layout.Column = 1;

x = uieditfield(g, 'Tag', 'BankLabelField', 'Value', char(sp.Name));
x.Layout.Row       = row;
x.Layout.Column    = 2;
x.ValueChangedFcn  = @(s,~) update_name_(obj, idx, s);
row = row + 2;

for s = 1:numel(sections)
    sTitle    = sections{s}{1};
    sMeta     = sections{s}{2};
    sPropList = sections{s}{3};

    % Section header
    hdr = uilabel(g, 'Text', ['  ' sTitle], ...
        'FontWeight', 'bold', 'FontSize', 11, ...
        'BackgroundColor', [0.88 0.88 0.92]);
    hdr.Layout.Row    = row;
    hdr.Layout.Column = [1 2];
    row = row + 1;

    % Property rows
    for p = 1:numel(sPropList)
        propName = sPropList{p};
        pm       = sMeta.(propName);

        lbl = uilabel(g, 'Text', [pm.label ':'], ...
            'HorizontalAlignment', 'right');
        lbl.Layout.Row    = row;
        lbl.Layout.Column = 1;

        wt = resolve_wt_(propName, pm, pl);
        sc = stimgen.StimType.display_scale(pm);
        switch wt
            case 'numeric'
                % Widgets carry display units (ms for time properties);
                % pm.format and pm.limits are already in those units.
                if is_non_vectorizable_prop_(propName)
                    x = uieditfield(g, 'numeric', 'Tag', propName);
                    x.Value = stimObj.(propName) * sc;
                    if isfield(pm, 'format'), x.ValueDisplayFormat = pm.format; end
                    if isfield(pm, 'limits'), x.Limits = pm.limits; end
                else
                    x = uieditfield(g, 'Tag', propName);
                    x.Value = localFormatPropValue_(stimObj.(propName) * sc);
                    x.UserData = struct('isNumericExpression', true);
                end
            case 'checkbox'
                x = uicheckbox(g, 'Tag', propName, 'Text', '');
                x.Value = stimObj.(propName);
            case 'dropdown'
                x = uidropdown(g, 'Tag', propName);
                x.Items = pm.items;
                if isfield(pm, 'itemsData'), x.ItemsData = pm.itemsData; end
                x.Value = stimObj.(propName);
            otherwise
                x = uieditfield(g, 'Tag', propName);
                x.Value = char(stimObj.(propName));
        end
        x.ValueChangedFcn = @(s, e) set_prop_(obj, stimObj, s, e);

        x.Layout.Row    = row;
        x.Layout.Column = 2;
        row = row + 1;
    end

    row = row + 1; % skip separator row
end

obj.update_signal_plot;
obj.refresh_combo_controls_;
end


% =========================================================================

function set_prop_(obj, stimObj, src, event)
% set_prop_(obj, stimObj, src, event) - Set a property on stimObj then refresh the plot.
% For vectorizable numeric fields (UserData.isNumericExpression == true), parses
% value as a MATLAB expression via evalPropertyExpression before assignment.
% Widget values are in display units (ms for time properties) and are divided
% by the propMeta display scale before being written to the property.
isNumExpr = isstruct(src.UserData) && isfield(src.UserData, 'isNumericExpression') && src.UserData.isNumericExpression;
sc = stimgen.StimType.display_scale(stimObj.get_prop_meta(), src.Tag);
try
    value = event.Value;
    if isNumExpr
        value = stimObj.evalPropertyExpression(src.Tag, char(string(value))) / sc;
    elseif isnumeric(value)
        value = value / sc;
    end
    stimObj.(src.Tag) = value;
    stimObj.update_signal();
    obj.update_signal_plot();
catch ME
    if isNumExpr
        src.Value = localFormatPropValue_(stimObj.(src.Tag) * sc);
    elseif isprop(stimObj, src.Tag)
        currentValue = stimObj.(src.Tag);
        if islogical(currentValue)
            src.Value = logical(currentValue);
        elseif isnumeric(currentValue)
            src.Value = currentValue * sc;
        elseif isstring(currentValue)
            src.Value = char(currentValue);
        else
            src.Value = event.PreviousValue;
        end
    else
        src.Value = event.PreviousValue;
    end
    obj.report_gui_error_(ME, "Invalid Parameter Value", ...
        "StimPlayer could not apply that parameter value. The previous value has been restored.");
    return
end
if isNumExpr
    src.Value = localFormatPropValue_(stimObj.(src.Tag) * sc);
end
obj.refresh_combo_controls_();
end


function update_name_(obj, idx, src)
% update_name_(obj, idx, newName) - Update the Name of bank item idx.
if idx < 1 || idx > numel(obj.StimPlayObjs)
    return
end

nameValue = strtrim(string(src.Value));
if strlength(nameValue) == 0
    src.Value = char(obj.StimPlayObjs(idx).Name);
    obj.show_gui_message_("Bank label cannot be empty.", ...
        "Invalid Label", "warning");
    return
end

obj.StimPlayObjs(idx).Name = nameValue;
obj.refresh_listbox_;

if isfield(obj.handles, 'BankList') && isvalid(obj.handles.BankList) && ...
        ~isempty(obj.handles.BankList.ItemsData)
    obj.handles.BankList.Value = idx;
end

obj.update_signal_plot;
obj.set_status_("Renamed stimulus to: " + nameValue);
end


function wt = resolve_wt_(propName, pm, pl)
% resolve_wt_(propName, pm, pl) - Determine widget type for a property.
if isfield(pm, 'widget')
    wt = pm.widget;
    return
end
idx = strcmp({pl.Name}, propName);
if ~any(idx) || isempty(pl(idx).Validation) || isempty(pl(idx).Validation.Class)
    wt = 'text';
    return
end
switch pl(idx).Validation.Class.Name
    case 'double'
        wt = 'numeric';
    case 'logical'
        wt = 'checkbox';
    otherwise
        wt = 'text';
end
end


function tf = is_non_vectorizable_prop_(propName)
% is_non_vectorizable_prop_(propName) - True for properties that must stay scalar.
% Mirrors stimgen.StimType.is_non_vectorizable_property_ (protected).
tf = any(strcmp(string(propName), ["Fs","ApplyCalibration","ApplyWindow"]));
end


function text = localFormatPropValue_(value)
% localFormatPropValue_(value) - Format a numeric property value for a text edit field.
% Scalars render as a bare number; vectors render in mat2str bracket notation.
if isscalar(value)
    text = num2str(double(value), '%g');
else
    text = mat2str(double(value));
end
end
