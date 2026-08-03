function d = effective_window_duration_(obj)
% d = effective_window_duration_(obj)
% Total onset+offset gate length in seconds, for the active variant.
%
% Seam for subclasses whose WindowDuration is expressed in something other
% than seconds -- see stimgen.Tone.WindowMethod, where it can mean percent
% of Duration or carrier periods. Overriding this keeps the conversion out
% of the stored property, so the value the user typed survives repeated
% calls to update_signal.
%
% Returns:
%   d - (1,1) double gate duration in seconds.

d = double(obj.get_selected_property_value_("WindowDuration"));
