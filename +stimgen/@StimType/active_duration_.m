function d = active_duration_(obj)
% d = active_duration_(obj)
% Duration, in seconds, of the waveform being generated or last generated,
% read WITHOUT advancing the variant selection.
%
% The Time and N getters read Duration through here. Inside a variant cycle
% (i.e. inside update_signal) the combination is already locked, so
% get_selected_property_value_ returns the one being generated. Outside a
% cycle get_selected_property_value_ would RESELECT -- advance the order and
% bump the use count -- whenever Duration is vectorized, so a plot refresh
% reading Time would change which combination plays next. There the active
% combination is read with active_variant_values instead, which touches no
% selection state and describes the waveform currently in Signal.
%
% Returns:
%   d - scalar duration in seconds (as double).
%
% See also: active_variant_values, selected_value

raw = obj.Duration;
if numel(raw) <= 1
    d = double(raw);
    return
end

if obj.variantCycleActive_
    d = double(obj.get_selected_property_value_("Duration"));
    return
end

v = obj.active_variant_values();
if isfield(v, 'Duration')
    d = double(v.Duration);
else
    d = double(raw(1));   % no combination table: what get_selected_property_value_ returns
end
end
