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

paramHandles = struct(); % registered with stimObj so on_gui_changed can reach the widgets

row = 1;

% Top row: editable bank label
BANK_LABEL_TIP = stimgen.util.tooltip('StimPlayer', 'BankLabel');

lbl = uilabel(g, 'Text', 'Bank Label:', 'HorizontalAlignment', 'right');
lbl.Layout.Row    = row;
lbl.Layout.Column = 1;
lbl.Tooltip       = BANK_LABEL_TIP;

x = uieditfield(g, 'Tag', 'BankLabelField', 'Value', char(sp.Name));
x.Layout.Row       = row;
x.Layout.Column    = 2;
x.Tooltip          = BANK_LABEL_TIP;
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

        % Label, widget, tooltip and display units come from the builder
        % shared with StimType.create_gui; the layout and the edit handling
        % are this panel's own.
        [x, lbl] = stimObj.build_prop_widget(g, propName, pm, '%s:', ...
            @(callbackName) run_action_(obj, stimObj, callbackName));
        lbl.Layout.Row    = row;
        lbl.Layout.Column = 1;

        if ~isa(x, 'matlab.ui.control.Button')
            x.ValueChangedFcn = @(s, e) set_prop_(obj, stimObj, s, e);
        end

        x.Layout.Row    = row;
        x.Layout.Column = 2;
        paramHandles.(propName) = x;
        row = row + 1;
    end

    row = row + 1; % skip separator row
end

stimObj.set_gui_handles(paramHandles);

obj.update_signal_plot;
obj.refresh_combo_controls_;
obj.sync_control_enable_;
end


% =========================================================================

function set_prop_(obj, stimObj, src, event)
% set_prop_(obj, stimObj, src, event) - Set a property on stimObj then refresh the plot.
% For vectorizable numeric fields (UserData.isNumericExpression == true), parses
% value as a MATLAB expression via evalPropertyExpression before assignment.
% Widget values are in display units (ms for time properties) and are divided
% by the propMeta display scale before being written to the property.

% An edit still pending when its panel is torn down (a bank rebuilt or
% reloaded, the window closed) commits on the destroyed widget, and the
% stimulus it was editing may be gone with it. There is nothing left to
% write to, and the recovery path below would fault on the same handles.
if ~isvalid(obj) || ~isvalid(src) || ~isvalid(stimObj)
    return
end
isNumExpr =isstruct(src.UserData) && isfield(src.UserData, 'isNumericExpression') && src.UserData.isNumericExpression;
sc = stimgen.StimType.display_scale(stimObj.get_prop_meta(), src.Tag);
try
    value = event.Value;
    if isNumExpr
        value = stimObj.evalPropertyExpression(src.Tag, char(string(value))) / sc;
    elseif isnumeric(value)
        value = value / sc;
    end
    stimObj.(src.Tag) = value;
    % Lets a stimulus react to the edit before the signal is rebuilt, e.g.
    % Tone re-rendering the Window Duration widget when Window Method
    % changes the units it is expressed in.
    stimObj.notify_gui_changed(src.Tag, event.Value);
    obj.set_computing_(true);
    computingCleanup = onCleanup(@() obj.set_computing_(false));
    stimObj.update_signal();
    clear computingCleanup;
    obj.update_signal_plot();
    % The calibration label counts the items that apply a calibration, so
    % toggling Apply Calibration (or anything else) must refresh it.
    obj.update_calibration_status_;
    obj.mark_bank_dirty_;
    % Only an edit that took is worth carrying to the next stimulus of this type.
    obj.remember_stim_settings_(stimObj);
catch ME
    if isNumExpr
        src.Value = stimgen.StimType.localFormatPropertyValue_(stimObj.(src.Tag) * sc);
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
    src.Value = stimgen.StimType.localFormatPropertyValue_(stimObj.(src.Tag) * sc);
end
obj.refresh_combo_controls_();
end


function run_action_(obj, stimObj, callbackName)
% run_action_(obj, stimObj, callbackName) - Invoke a propMeta 'button' action.
% Action callbacks (e.g. SoundFile.browse_files) can change the parameter set
% and the number of variant combinations, so the panel is rebuilt afterwards.
try
    stimObj.(char(callbackName))();
catch ME
    obj.report_gui_error_(ME, "Parameter Action Failed", ...
        "StimPlayer could not complete that action.");
    return
end
obj.mark_bank_dirty_;  % an action edits the stimulus (e.g. adds files)

if isfield(obj.handles, 'BankList') && isvalid(obj.handles.BankList)
    obj.on_bank_selection_changed(obj.handles.BankList, []);
else
    obj.update_signal_plot;
    obj.refresh_combo_controls_;
end
end


function update_name_(obj, idx, src)
% update_name_(obj, idx, newName) - Update the Name of bank item idx.
% Same pending-edit-on-a-destroyed-widget case as set_prop_.
if ~isvalid(obj) || ~isvalid(src)
    return
end
if idx < 1|| idx > numel(obj.StimPlayObjs)
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
obj.mark_bank_dirty_;
obj.refresh_listbox_;

if isfield(obj.handles, 'BankList') && isvalid(obj.handles.BankList) && ...
        ~isempty(obj.handles.BankList.ItemsData)
    obj.handles.BankList.Value = idx;
end

obj.update_signal_plot;
obj.set_status_("Renamed stimulus to: " + nameValue);
end

