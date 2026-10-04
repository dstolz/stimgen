function v = pref_number_(text, default, limits, lowerOpen)
% A stored preference as a number a field will accept, or the default. A
% numeric edit field throws on a Value outside its Limits, so a hand-edited
% or stale preference must not reach one unchecked.
v = str2double(text);
if ~isfinite(v) && ~(isinf(v) && v > 0 && isinf(limits(2)))
    v = default;
elseif v < limits(1) || v > limits(2) || (lowerOpen && v <= limits(1))
    v = default;
end
end
