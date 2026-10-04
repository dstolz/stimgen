function sgn = claim_polarity_(obj)
% sgn = claim_polarity_() - Sign for the next presentation.
% A stimulus that alternates across presentations (see
% StimType.alternates_polarity) is inverted on every other
% presentation OF THE SAME VARIANT, so each combination's
% repetitions are split between the signs whatever order the
% bank and its variants are visited in. Counting per bank item
% would not do: two variants of one item presented in turn
% would each always get the same sign. Called once per
% presentation, just before it is buffered.
sgn = 1;
bankIdx = obj.nextSPOIdx;
sp = obj.CurrentSPObj;
if isempty(sp) || bankIdx < 1
    return
end
stimObj = sp.CurrentStimObj;
if ~stimObj.alternates_polarity()
    return
end
info = stimObj.get_variant_info();
v = info.ActiveIndex;
if numel(obj.PolarityCount_) < bankIdx
    obj.PolarityCount_{bankIdx} = [];
end
counts = obj.PolarityCount_{bankIdx};
if numel(counts) < v
    counts(v) = 0;
end
if mod(counts(v), 2) == 1
    sgn = -1;
end
counts(v) = counts(v) + 1;
obj.PolarityCount_{bankIdx} = counts;
end
