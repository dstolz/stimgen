function names = remembered_setting_names_(~, stimObj)
% remembered_setting_names_() - Properties worth carrying to the next stimulus of a type.
% The settings a user tunes: level, timing, window, variant
% policy, and the type's own parameters. Not Fs (the bank owns
% the rate) and not Catalog / FileIndex (a file list and indices
% into it mean nothing to a new item that has no files yet).
base = ["SoundLevel","Duration","WindowDuration","WindowFcn", ...
        "ApplyCalibration","ApplyWindow", ...
        "VariantSelectionMode","VariantCombinationMode", ...
        "VariantSelectorClass","VariantSelectorConfig", ...
        "VariantReselectOnUpdate"];
names = unique([base, stimObj.UserProperties], 'stable');
names = names(~ismember(names, ["Catalog","FileIndex"]));
has = false(size(names));
for k = 1:numel(names)
    has(k) = isprop(stimObj, char(names(k)));
end
names = names(has);
end
