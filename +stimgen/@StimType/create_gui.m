function h = create_gui(obj, src, ~)
% create_gui(obj, src) - Auto-build parameter GUI from propMeta().
% Creates a two-column label+widget grid for each property returned
% by propMeta(). Widget type is inferred from the property class
% (double->numeric editfield, logical->checkbox, string->text
% editfield) unless overridden via the 'widget' metadata field.
%
% Parameters:
%   src - parent UI container (e.g. uipanel)
%
% Returns:
%   h - struct of widget handles keyed by property name

meta     = obj.propMeta();
sections = stimgen.StimType.group_prop_meta(meta); % Nx1 cell of {groupName, propNames}
secRows  = vertcat(sections{:});                   % Nx2 cell: col 1 = name, col 2 = propNames
fields   = vertcat(secRows{:, 2});                 % flatten propNames, section order preserved
nRows    = numel(fields);

mc = metaclass(obj);
pl = mc.PropertyList;

g = uigridlayout(src);
g.ColumnWidth = {'1x', '1x'};
g.RowHeight   = repmat({25}, 1, nRows);

h = struct();
for i = 1:nRows
    propName = fields{i};
    pm = meta.(propName);

    lbl = uilabel(g, 'Text', pm.label);
    lbl.Layout.Column = 1;
    lbl.Layout.Row    = i;
    lbl.HorizontalAlignment = 'right';

    wt = stimgen.StimType.resolve_widget_type(propName, pm, pl);
    sc = stimgen.StimType.display_scale(pm);

    switch wt
        case 'numeric'
            % Widgets show display units (e.g. ms); pm.format and pm.limits
            % are already expressed in those units.
            if obj.is_non_vectorizable_property_(propName)
                x = uieditfield(g, 'numeric', 'Tag', propName);
                x.Value = obj.(propName) * sc;
                if isfield(pm, 'format')
                    x.ValueDisplayFormat = pm.format;
                end
                if isfield(pm, 'limits')
                    x.Limits = pm.limits;
                end
            else
                x = uieditfield(g, 'Tag', propName);
                x.Value = stimgen.StimType.localFormatPropertyValue_(obj.(propName) * sc);
                x.UserData = struct('isNumericExpression', true, 'propMeta', pm);
            end
        case 'checkbox'
            x = uicheckbox(g, 'Tag', propName, 'Text', '');
            x.Value = obj.(propName);
        case 'dropdown'
            x = uidropdown(g, 'Tag', propName);
            x.Items = pm.items;
            if isfield(pm, 'itemsData')
                x.ItemsData = pm.itemsData;
            end
            x.Value = obj.(propName);
        case 'button'
            % Action widget: pm.callback names a public method on obj.
            % Backed by no property, so nothing is read from obj here.
            x = uibutton(g, 'Tag', propName, 'Text', pm.text);
            x.ButtonPushedFcn = @(~,~) obj.(pm.callback)();
        otherwise % 'text'
            x = uieditfield(g, 'Tag', propName);
            x.Value = char(obj.(propName));
    end

    % Keep the label reachable so refresh_gui_widget can retitle a property
    % whose units depend on another property (e.g. Tone.WindowDuration).
    ud = x.UserData;
    if ~isstruct(ud)
        ud = struct();
    end
    ud.labelHandle = lbl;
    ud.labelFormat = '%s';
    x.UserData     = ud;

    x.Layout.Column = 2;
    x.Layout.Row    = i;
    h.(propName)    = x;
end

% Buttons carry ButtonPushedFcn, not ValueChangedFcn, and would error here.
hNames = fieldnames(h);
for i = 1:numel(hNames)
    if ~isa(h.(hNames{i}), 'matlab.ui.control.Button')
        h.(hNames{i}).ValueChangedFcn = @obj.interpret_gui;
    end
end
obj.GUIHandles = h;
