function s = display_scale(pm, propName)
% s = stimgen.StimType.display_scale(pmEntry)
% s = stimgen.StimType.display_scale(pmStruct, propName)
% Return the display scale factor for a property, i.e. the factor that
% converts a stored property value into the units shown in the GUI:
%
%   displayValue  = propertyValue * s
%   propertyValue = displayValue  / s
%
% Time properties are stored in seconds and displayed in milliseconds, so
% they declare 'scale', 1000 in propMeta(). Properties without a 'scale'
% field return 1.
%
% Parameters:
%   pm       - A single propMeta entry struct, or the full propMeta struct
%              when propName is supplied.
%   propName - (optional) Property name to look up inside pm.
%
% Returns:
%   s - (1,1) double scale factor, always finite and nonzero.

if nargin == 2
    propName = char(propName);
    if ~isstruct(pm) || ~isfield(pm, propName)
        s = 1;
        return
    end
    pm = pm.(propName);
end

if ~isstruct(pm) || ~isfield(pm, 'scale')
    s = 1;
    return
end

s = double(pm.scale);
if ~isscalar(s) || ~isfinite(s) || s == 0
    s = 1;
end
end
