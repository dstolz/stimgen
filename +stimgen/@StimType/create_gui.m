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
%
% Each row comes from build_prop_widget, the builder shared with the
% StimPlayer bank editor. A 'button' action that succeeds rebuilds the panel
% into src (see run_action_ below).

meta     = obj.propMeta();
sections = stimgen.StimType.group_prop_meta(meta); % Nx1 cell of {groupName, propNames}
secRows  = vertcat(sections{:});                   % Nx2 cell: col 1 = name, col 2 = propNames
fields   = vertcat(secRows{:, 2});                 % flatten propNames, section order preserved
nRows    = numel(fields);

g = uigridlayout(src);
g.ColumnWidth = {'1x', '1x'};
g.RowHeight   = repmat({25}, 1, nRows);

h = struct();
for i = 1:nRows
    propName = fields{i};

    % Label, widget, tooltip and display units come from the builder shared
    % with the StimPlayer bank editor; only the layout is decided here.
    [x, lbl] = obj.build_prop_widget(g, propName, meta.(propName), '%s', ...
        @(callbackName) run_action_(obj, src, g, callbackName));

    lbl.Layout.Column = 1;
    lbl.Layout.Row    = i;
    x.Layout.Column   = 2;
    x.Layout.Row      = i;
    h.(propName)      = x;
end

% Buttons carry ButtonPushedFcn, not ValueChangedFcn, and would error here.
hNames = fieldnames(h);
for i = 1:numel(hNames)
    if ~isa(h.(hNames{i}), 'matlab.ui.control.Button')
        h.(hNames{i}).ValueChangedFcn = @obj.interpret_gui;
    end
end
obj.GUIHandles = h;
end


% =========================================================================

function run_action_(obj, src, g, callbackName)
% run_action_(obj, src, g, callbackName) - Invoke a propMeta 'button' action.
% A failure is logged and shown rather than escaping the callback, as the
% StimPlayer bank editor does. An action (e.g. SoundFile.browse_files) can
% change the parameter set and the number of variant combinations, so on
% success the panel is rebuilt into the same container; the rebuilt widgets
% are registered in GUIHandles, so the struct create_gui first returned is
% stale from then on.
if ~isvalid(obj)
    return
end
try
    obj.(callbackName)();
catch ME
    titleText = 'Parameter Action Failed';
    stimgen.util.vprintf(0, 1, '%s: %s', titleText, ME.message);
    stimgen.util.vprintf(0, 1, ME);
    fig = [];
    if isvalid(src)
        fig = ancestor(src, 'matlab.ui.Figure');
    end
    if ~isempty(fig) && isvalid(fig)
        try
            uialert(fig, sprintf('Could not complete that action.\n\n%s', ME.message), ...
                titleText, 'Icon', 'error');
        catch
            % Avoid cascading GUI failures while reporting an error.
        end
    end
    return
end

if isvalid(src)
    if isvalid(g)
        delete(g);
    end
    obj.create_gui(src);
end
end
