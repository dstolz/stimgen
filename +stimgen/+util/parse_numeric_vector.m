function values = parse_numeric_vector(textValue, label)
% values = parse_numeric_vector(textValue, label)
% Parse a GUI text entry into a positive numeric row vector.
%
% Accepts comma/space separated numbers or any MATLAB expression evaluating
% to a real vector (e.g. "500:250:32000", "0.01.*2.^(0:9)"). Empty text, or
% a "(empty ...)" placeholder, returns [] so the caller can fall back to its
% own default rather than treating it as a parse failure.
%
% Parameters:
%   textValue - char | string | cellstr entry to parse
%   label     - description used in the error text, e.g. 'click durations'
%
% Returns:
%   values - (1,:) double of positive values; 1x0 when nothing was entered
%
% See also: stimgen.calibration.CalibrationGui
arguments
    textValue
    label (1,:) char
end

values = double.empty(1,0);

if ischar(textValue)
    raw = string(textValue);
elseif isstring(textValue)
    raw = strjoin(textValue, ' ');
elseif iscell(textValue)
    raw = strjoin(string(textValue), ' ');
else
    raw = "";
end

raw = strtrim(raw);
if raw == "" || startsWith(raw, "(empty", IgnoreCase=true)
    return
end

% str2num, not str2double: evaluating an expression is the point.
vals = str2num(char(raw));
if ~isnumeric(vals) || isempty(vals) || ~isreal(vals) || ~isvector(vals) || any(isnan(vals(:)))
    error('stimgen:util:parse_numeric_vector:badVector', ...
        'Could not parse %s. Use comma/space separated numbers or a MATLAB expression (e.g. 500:250:32000).', label);
end

values = vals(:)';
if any(values <= 0)
    error('stimgen:util:parse_numeric_vector:badVector', ...
        '%s must contain only positive values.', label);
end
end
