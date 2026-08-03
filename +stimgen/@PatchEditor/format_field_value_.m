function s = format_field_value_(v)
% s = stimgen.PatchEditor.format_field_value_(v)
% Format a property value for one of the editor's expression text fields.
%
% Scalars print as a bare number and vectors as a MATLAB literal, so the text
% a field shows is always text the same field would accept back. %g rather
% than mat2str's 15 significant digits, because a value that arrived through a
% display scale (0.1 s * 1000) would otherwise render as 100.000000000000014.
%
% Parameters:
%   v - Numeric scalar or vector, already in display units.
%
% Returns:
%   s - char row vector.

if isscalar(v)
    s = num2str(double(v), '%g');
else
    s = mat2str(double(v));
end
end
