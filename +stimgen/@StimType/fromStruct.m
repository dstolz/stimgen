function obj = fromStruct(S)
% obj = stimgen.StimType.fromStruct(S)
% Reconstruct a stimgen.StimType subclass instance from a serialized struct.
%
% Calibration is held OFF while the object is rebuilt and switched to the
% saved setting last. Every observable property assigned below regenerates
% the signal (create_listeners), and until the serialized calibration has
% been restored that is against the default, empty StimCalibration:
% apply_calibration then logs a critical "No calibration data available for
% stim" about a stimulus that is in fact calibrated -- word for word the line
% a stimulus with no calibration earns, so a log could not tell the two
% apart. With ApplyCalibration false, apply_calibration returns before it
% looks. The closing assignment is the one regeneration made with every
% property and the calibration in place.
obj = feval(char(S.Class));
obj.DisplayName = S.DisplayName;
obj.ApplyCalibration = false;   % restored last; see above
obj.Fs               = S.Fs;
obj.ApplyWindow      = S.ApplyWindow;
if isfield(S, 'VariantSelectionMode')
    obj.VariantSelectionMode = string(S.VariantSelectionMode);
end
if isfield(S, 'VariantCombinationMode')
    obj.VariantCombinationMode = string(S.VariantCombinationMode);
end
if isfield(S, 'VariantSelectorClass')
    obj.VariantSelectorClass = string(S.VariantSelectorClass);
end
if isfield(S, 'VariantSelectorConfig')
    obj.VariantSelectorConfig = S.VariantSelectorConfig;
end
if isfield(S, 'VariantReselectOnUpdate')
    obj.VariantReselectOnUpdate = logical(S.VariantReselectOnUpdate);
end
if isfield(S, 'Calibration')
    calData = S.Calibration;
    if isa(calData, 'stimgen.StimCalibration')
        obj.Calibration = calData;
    elseif isstruct(calData)
        obj.Calibration = stimgen.StimCalibration.loadobj(calData);
    end
end
for k = 1:numel(S.UserProperties)
    pname = char(S.UserProperties(k));
    if strcmp(pname, 'ApplyCalibration'), continue; end   % restored last
    if isprop(obj, pname) && isfield(S, pname)
        obj.(pname) = S.(pname);
    end
end
obj.ApplyCalibration = S.ApplyCalibration;
end
