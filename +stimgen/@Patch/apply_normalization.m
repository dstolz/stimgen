function apply_normalization(obj)
% apply_normalization(obj)
% Normalize Signal according to LevelReference.
%
% StimType.Normalization is an Abstract Constant, so it cannot vary per
% instance. A patch can hold anything from a pure tone (where peak
% normalization is right) to broadband noise (where RMS is), so the choice is
% a per-instance property and this override honors it. Same reasoning, and the
% same solution, as stimgen.SoundFile.

if obj.temporarilyDisableSignalMods || isempty(obj.Signal)
    return
end

obj.Signal = local_normalize(obj.Signal, obj.LevelReference);
end


function y = local_normalize(y, reference)
switch reference
    case "rms"
        d = sqrt(mean(y.^2));
    case "peak"
        d = max(y);
    otherwise % "absmax"
        d = max(abs(y));
end
if isfinite(d) && d > 0
    y = y ./ d;
end
end
