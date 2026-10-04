function [txt, uneven, detail] = reps_per_combination_(~, reps, stimObj)
% [txt, uneven, detail] = reps_per_combination_(reps, stimObj)
% How a bank item's Reps divides over its variant combinations.
%
% Reps counts presentations of the bank item (of each stimulus
% object it holds), not of each combination, and a Run makes
% exactly that many; it is never rounded to a multiple of the
% combination count. How the presentations fall on combinations
% depends on the stimulus's VariantSelectionMode:
%   Serial, ShuffleLeastUsed - balanced: every combination gets
%       floor(Reps/n) or ceil(Reps/n); uneven when n does not
%       divide Reps (Serial gives the extra one to 1..mod(Reps,n))
%   ShuffleUniform - drawn with replacement; counts are random
%   CustomSelector - whatever the selector decides
%
% Returns:
%   txt    - short label text ("" for a single combination)
%   uneven - true when a balanced mode cannot balance Reps
%   detail - one sentence for the Run warning ("" unless uneven)
txt = "";
uneven = false;
detail = "";
info  = stimObj.get_variant_info();
nComb = info.NumCombinations;
if nComb <= 1
    return
end
mode = string(stimObj.VariantSelectionMode);
switch mode
    case {"Serial", "ShuffleLeastUsed"}
        lo = floor(reps / nComb);
        hi = ceil(reps / nComb);
        if lo == hi
            txt = sprintf("%d reps each", lo);
        else
            txt = sprintf("%d-%d reps each", lo, hi);
            uneven = true;
            nHi = mod(reps, nComb);
            detail = sprintf("%d reps over %d combinations (%s): %d combination(s) get %d, %d get %d.", ...
                reps, nComb, mode, nHi, hi, nComb - nHi, lo);
            if mode == "Serial"
                detail = detail + sprintf(" Serial order gives the extra presentation to combinations 1-%d.", nHi);
            end
        end
    case "ShuffleUniform"
        txt = sprintf("~%.3g reps each (random)", reps / nComb);
    otherwise
        txt = "reps set by selector";
end
end
