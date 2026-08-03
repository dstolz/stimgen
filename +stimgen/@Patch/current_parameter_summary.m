function text = current_parameter_summary(obj)
% text = current_parameter_summary(obj)
% Compact summary of the patch for status lines and bank labels.
%
% Graph is stripped before delegating: it is a topology struct that the base
% implementation would render as "<struct>", and it is the one UserProperties
% entry that carries no numeric value. stimgen.SoundFile does the same for its
% Catalog. Removing it is safe because it is scalar and therefore can never be
% a variant axis, so the variant signature does not change.

props = obj.UserProperties;
keep  = props ~= "Graph";

restore = onCleanup(@() set_user_properties_(obj, props));
obj.UserProperties = props(keep);

text = current_parameter_summary@stimgen.StimType(obj);
end


function set_user_properties_(obj, props)
obj.UserProperties = props;
end
