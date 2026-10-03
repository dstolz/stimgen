function S = toStruct(obj)
% S = toStruct(obj)
% Serialize StimType object to a struct.
% Signal, GUIHandles, and listeners are not included.
%
% Returns:
%   S - Struct with class metadata, core properties, calibration, and
%       user-defined property values.

% Basic class metadata
S = struct;
S.Class        = string(class(obj));
S.DisplayName  = obj.DisplayName;

% Core StimType properties: the list fromStruct restores from
core = stimgen.StimType.CoreProperties;
for k = 1:numel(core)
    pname = char(core(k));
    S.(pname) = obj.(pname);
end
S.ApplyCalibration = obj.ApplyCalibration;

% Abstract/constant properties (same across instances of subclass)
S.CalibrationType  = obj.CalibrationType;
S.Normalization    = obj.Normalization;
S.IsMultiObj       = obj.IsMultiObj;

% Calibration
S.Calibration = obj.Calibration.toStruct;

% User-defined property list and values
S.UserProperties = obj.UserProperties;
for k = 1:numel(obj.UserProperties)
    pname = obj.UserProperties(k);
    if isprop(obj,pname)
        S.(pname) = obj.(pname);
    end
end
