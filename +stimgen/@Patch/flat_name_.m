function name = flat_name_(label, param)
% name = stimgen.Patch.flat_name_(label, param)
% Build the flattened property name for one node parameter.
%
% The underscore separator is load-bearing. It keeps the result a legal MATLAB
% identifier (so it can be a dynamic property), a legal struct fieldname (so it
% can be a variant-combination table field and a serialized struct field), and
% free of the dot that StimType.rewrite_qualified_property_refs_ would strip
% from an expression like "Osc1.Frequency".

name = string(label) + "_" + string(param);
end
