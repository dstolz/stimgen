function value = active_value_(obj, propName)
% value = active_value_(obj, propName)
% One property's value for the ACTIVE variant combination, read without
% advancing the variant selection.
%
% The general form of active_duration_. Inside a variant cycle (inside
% update_signal) the combination is already locked, so
% get_selected_property_value_ returns the one being generated. Outside a
% cycle that call would RESELECT whenever the property is vectorized --
% advance the order and bump the use count -- so the active combination is
% read with active_variant_values instead, which touches no selection state
% and describes the waveform currently in Signal.
%
% Parameters:
%   propName - property name (char or string)
%
% Returns:
%   value - the property's value: as stored when it is scalar, otherwise the
%           active combination's element
%
% See also: active_duration_, active_variant_values, selected_value

name = char(propName);
raw  = obj.(name);
if numel(raw) <= 1
    value = raw;
    return
end

if obj.variantCycleActive_
    value = obj.get_selected_property_value_(name);
    return
end

v = obj.active_variant_values();
if isfield(v, name)
    value = v.(name);
else
    value = raw(1);   % no combination table: what get_selected_property_value_ returns
end
end
