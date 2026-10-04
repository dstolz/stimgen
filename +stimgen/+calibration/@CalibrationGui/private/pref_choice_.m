function v = pref_choice_(text, allowed, default)
% A stored preference as one of a dropdown's items, or the default.
v = lower(strtrim(string(text)));
if ~ismember(v, allowed)
    v = default;
end
end
