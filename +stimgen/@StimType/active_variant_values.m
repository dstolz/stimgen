function s = active_variant_values(obj)
% s = active_variant_values(obj)
% Property values of the ACTIVE variant combination, without selecting a new one.
%
% selected_value() is the usual way to read a vectorized property, but outside
% a variant cycle it reselects: it advances the selection order and bumps the
% use count, because that is what generating the next stimulus is supposed to
% do. A caller that only wants to REPORT what the last generated waveform was
% made from cannot use it -- asking would change the answer, and the value
% returned would belong to a waveform that has not been generated yet.
%
% This is the read-only half. It reports the combination that produced the
% signal currently in Signal, and touches no selection state.
%
% The cache is refreshed first, exactly as get_variant_info() does, so a table
% built from stale property values is not reported. That refresh is a no-op
% whenever the vectorized properties have not changed since the last
% generation, which is the case this is called in.
%
% Returns:
%   s - struct with one field per vectorized property, holding that
%       property's value for the active combination. Empty struct when the
%       stimulus has no vectorized properties, in which case every property is
%       already scalar and can be read directly.
%
% Example:
%   v = stimObj.active_variant_values();
%   if isfield(v, 'Frequency'), f = v.Frequency; else, f = stimObj.Frequency; end
%
% See also: selected_value, get_variant_info, set_variant_index

obj.refresh_variant_cache_if_needed_();

s = struct();
if isempty(obj.variantCombinationTable_)
    return
end

idx = min(max(obj.variantActiveIdx_, 1), numel(obj.variantCombinationTable_));
s   = obj.variantCombinationTable_(idx);
end
