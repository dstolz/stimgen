function [x, lbl] = build_prop_widget(obj, parent, propName, pm, labelFormat, actionFcn)
% [x, lbl] = build_prop_widget(obj, parent, propName, pm, labelFormat, actionFcn)
% Create the label and the widget for one propMeta entry: the one widget
% builder behind both GUI generators, create_gui and the StimPlayer bank
% editor (StimPlayer.on_bank_selection_changed). A new widget type is added
% here and nowhere else.
%
% Builds, from pm and the property's class:
%   numeric  - numeric edit field in display units (pm.format, pm.limits)
%              for a non-vectorizable property, otherwise an expression
%              text field (UserData.isNumericExpression = true)
%   checkbox - uicheckbox
%   dropdown - uidropdown from pm.items (and pm.itemsData)
%   button   - uibutton captioned pm.text, an action rather than a property
%   text     - text edit field (anything else)
% applies pm.tooltip to both halves of the row, and stores the label in the
% widget's UserData.labelHandle / UserData.labelFormat so refresh_gui_widget
% can retitle it later.
%
% Deliberately left to the caller: where the two handles go in the grid
% (Layout.Row / Layout.Column), ValueChangedFcn (a uibutton has none), and
% registering the widgets (GUIHandles / set_gui_handles). Each generator
% lays out and applies edits its own way.
%
% Parameters:
%   parent      - container both handles are created in (a uigridlayout)
%   propName    - property name; also the widget Tag
%   pm          - the propMeta entry for propName
%   labelFormat - (optional) sprintf template for the label caption, e.g.
%                 '%s:'. Default '%s'.
%   actionFcn   - (optional) function handle invoked as actionFcn(callbackName)
%                 when a 'button' widget is pressed, so the caller can wrap
%                 the action in its own error handling and rebuild. Default
%                 calls obj.(callbackName)() directly.
%
% Returns:
%   x   - the widget handle
%   lbl - the label handle
%
% Public but Hidden: StimPlayer is not a StimType subclass, and is the
% other caller.

if nargin < 5 || isempty(labelFormat)
    labelFormat = '%s';
end
if nargin < 6
    actionFcn = [];
end
propName = char(propName);

lbl = uilabel(parent, 'Text', sprintf(labelFormat, pm.label), ...
    'HorizontalAlignment', 'right');

mc = metaclass(obj);
wt = stimgen.StimType.resolve_widget_type(propName, pm, mc.PropertyList);
sc = stimgen.StimType.display_scale(pm);

switch wt
    case 'numeric'
        % Widgets carry display units (e.g. ms for time properties);
        % pm.format and pm.limits are already expressed in those units.
        if obj.is_non_vectorizable_property_(propName)
            x = uieditfield(parent, 'numeric', 'Tag', propName);
            x.Value = obj.(propName) * sc;
            if isfield(pm, 'format')
                x.ValueDisplayFormat = pm.format;
            end
            if isfield(pm, 'limits')
                x.Limits = pm.limits;
            end
        else
            x = uieditfield(parent, 'Tag', propName);
            x.Value = stimgen.StimType.localFormatPropertyValue_(obj.(propName) * sc);
            x.UserData = struct('isNumericExpression', true, 'propMeta', pm);
        end
    case 'checkbox'
        x = uicheckbox(parent, 'Tag', propName, 'Text', '');
        x.Value = obj.(propName);
    case 'dropdown'
        x = uidropdown(parent, 'Tag', propName);
        x.Items = pm.items;
        if isfield(pm, 'itemsData')
            x.ItemsData = pm.itemsData;
        end
        x.Value = obj.(propName);
    case 'button'
        % Action widget: pm.callback names a public no-argument method on
        % obj. Backed by no property, so nothing is read from obj here.
        x = uibutton(parent, 'Tag', propName, 'Text', pm.text);
        callbackName = char(pm.callback);
        if isempty(actionFcn)
            x.ButtonPushedFcn = @(~,~) obj.(callbackName)();
        else
            x.ButtonPushedFcn = @(~,~) actionFcn(callbackName);
        end
    otherwise % 'text'
        x = uieditfield(parent, 'Tag', propName);
        x.Value = char(obj.(propName));
end

% Hover help, applied to both halves of the row so it appears wherever the
% pointer lands.
if isfield(pm, 'tooltip')
    lbl.Tooltip = pm.tooltip;
    x.Tooltip   = pm.tooltip;
end

% Keep the label reachable so refresh_gui_widget can retitle a property
% whose units depend on another property (e.g. Tone.WindowDuration).
ud = x.UserData;
if ~isstruct(ud)
    ud = struct();
end
ud.labelHandle = lbl;
ud.labelFormat = labelFormat;
x.UserData     = ud;
end
