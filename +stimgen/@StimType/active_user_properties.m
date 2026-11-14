function names = active_user_properties(obj)
% names = active_user_properties(obj)
% UserProperties without the settings that currently mean nothing.
%
% UserProperties is the full list a stimulus serializes, and it always
% includes every Background* property. A Background setting the chosen
% Background type does not use -- all of them under "None" -- is not a
% parameter of the stimulus as it stands, so a display that lists parameters
% (the inspector's table) reads this list rather than showing a Background
% Level for a stimulus that has no background.
%
% Returns:
%   names - (1,:) string, in UserProperties order
names = string(obj.UserProperties);
keep  = true(size(names));
for k = 1:numel(names)
    keep(k) = ~obj.is_inactive_background_property_(names(k));
end
names = names(keep);
end
