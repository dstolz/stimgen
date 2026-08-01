function wt = resolve_widget_type(propName, pm, pl)
% resolve_widget_type(propName, pm, pl)
% Determine widget type from metadata or property class.
%
% An explicit pm.widget always wins. Note that 'button' entries need not
% correspond to a real property at all -- they are action rows keyed by a
% pseudo-name, so the property-class lookup below is never reached for them.
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
