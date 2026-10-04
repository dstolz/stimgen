function v = vector_or_empty_(text, label)
% A list field's value: [] when blank (the engine's default applies), else a
% positive numeric row vector. The parse is the package's shared one.
v = stimgen.util.parse_numeric_vector(text, char(label));
end
