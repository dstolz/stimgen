function tf = is_non_vectorizable_property_(~, propName)
% tf = is_non_vectorizable_property_(obj, propName)
% Return true when propName is one of the properties that must remain scalar.
% Non-vectorizable properties: Fs, ApplyCalibration, ApplyWindow, and the
% three background settings that describe the background's kind and its
% noise token rather than a parameter to vary (Background,
% BackgroundLoopDuration, BackgroundSeed).

tf = any(strcmp(string(propName), ["Fs","ApplyCalibration","ApplyWindow", ...
    "Background","BackgroundLoopDuration","BackgroundSeed"]));
