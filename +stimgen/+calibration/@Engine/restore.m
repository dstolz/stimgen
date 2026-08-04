function restore(obj, s)
% restore(obj, s)
% Restore engine state from a serialized struct.
%
% The measurement properties are SetAccess = protected, so callers outside
% the class -- notably stimgen.StimCalibration.loadobj, which rebuilds a
% calibration from a .spl bank or a serialized StimType -- cannot assign
% them directly. This is the supported entry point for that.
%
% Accepts either field naming in use:
%   ExcitationVoltage        (.esgc files, Engine.save)
%   ExcitationSignalVoltage  (stimgen.StimCalibration.toStruct/saveobj)
%
% Missing fields keep their current values, so a partial struct from an
% older file is safe.
%
% Parameters:
%   s - struct of engine properties

arguments
    obj (1,1) stimgen.calibration.Engine
    s   (1,1) struct
end

if isfield(s, 'CalibrationData') && isstruct(s.CalibrationData)
    obj.CalibrationData = s.CalibrationData;
end

if isfield(s, 'CalibrationTimestamp')
    obj.CalibrationTimestamp = s.CalibrationTimestamp;
end

% Scalars go through set_configuration so that their validators run.
cfg = {};
scalarFields = ["MicSensitivity", "ReferenceLevel", "ReferenceFrequency", ...
                "NormativeValue", "ShowLivePlots"];
for k = 1:numel(scalarFields)
    f = scalarFields(k);
    if isfield(s, f) && ~isempty(s.(f))
        cfg = [cfg, {char(f), s.(f)}]; %#ok<AGROW>
    end
end

if isfield(s, 'ExcitationVoltage') && ~isempty(s.ExcitationVoltage)
    cfg = [cfg, {'ExcitationVoltage', s.ExcitationVoltage}];
elseif isfield(s, 'ExcitationSignalVoltage') && ~isempty(s.ExcitationSignalVoltage)
    cfg = [cfg, {'ExcitationVoltage', s.ExcitationSignalVoltage}];
end

if ~isempty(cfg)
    obj.set_configuration(cfg{:});
end
