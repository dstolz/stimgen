function context = build_expression_context_(obj, targetPropName)
% context = build_expression_context_(obj, targetPropName)
% Build a struct of current numeric UserProperty values for use as eval context.
% The target property is excluded to prevent self-reference.
%
% Values are converted into GUI display units (see propMeta 'scale'), so an
% expression typed into a millisecond field can reference another time
% property and stay in milliseconds throughout. The caller converts the
% evaluated result back to property units.
%
% Parameters:
%   targetPropName - Name of the property being evaluated (excluded from context).
%
% Returns:
%   context - Struct mapping valid MATLAB names to double values in display units.

context = struct();
if isempty(obj.UserProperties)
    return
end
meta = obj.propMeta();
for k_ = 1:numel(obj.UserProperties)
    pname = char(obj.UserProperties(k_));
    if strcmp(pname, targetPropName)
        continue
    end
    if ~isprop(obj, pname)
        continue
    end
    raw = obj.(pname);
    if isnumeric(raw) || islogical(raw)
        safeName = matlab.lang.makeValidName(pname);
        context.(safeName) = double(raw) * stimgen.StimType.display_scale(meta, pname);
    end
end
