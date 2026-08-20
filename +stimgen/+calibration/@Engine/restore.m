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

% A struct written before the level scale was corrected carries tables that
% double-counted the calibrator. Version 2 marks the fix; anything older, or
% unversioned, is only ambiguous when the calibrator was not the default 94 dB,
% because that is the one setting at which the two scales agree.
if isfield(s, 'ReferenceLevel') && ~isempty(s.ReferenceLevel)
    stale = ~isfield(s, 'version') || isempty(s.version) || s.version < 2;
    offsetDb = double(s.ReferenceLevel) - 94;
    if stale && abs(offsetDb) >= 0.05
        stimgen.util.vprintf(0, 1, ...
            ['This calibration was serialized on the old level scale, which ' ...
             'added the %.1f dB calibrator level on top of the 20 uPa ' ...
             'reference. Its levels are %+.1f dB off and the rig would play ' ...
             'about %.1f dB too %s. Re-measure it.'], ...
            s.ReferenceLevel, offsetDb, abs(offsetDb), ...
            stale_direction_(offsetDb));
    end
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
                "NormativeValue", "MaxOutputVoltage", "ShowLivePlots", ...
                "ToneLutSource", "AcCoupleResponse", "AcCoupleFrequency", ...
                "AdcGain", "DacAttenuation", ...
                "SpectralWindow", "SpectralFftLength"];
for k = 1:numel(scalarFields)
    f = scalarFields(k);
    if isfield(s, f) && ~isempty(s.(f))
        cfg = [cfg, {char(f), s.(f)}]; %#ok<AGROW>
    end
end

% DemeanResponse is the option AC coupling replaced. It named the same intent
% by the weaker means, so a struct written before the change turns it on at
% the current default corner rather than being dropped as unknown.
if ~isfield(s, 'AcCoupleResponse') && isfield(s, 'DemeanResponse') && ~isempty(s.DemeanResponse)
    cfg = [cfg, {'AcCoupleResponse', logical(s.DemeanResponse)}];
end

% One string here, but one entry per line in a struct a text area filled in,
% so it is joined rather than assigned straight through.
if isfield(s, 'Notes') && ~isempty(s.Notes)
    cfg = [cfg, {'Notes', join(string(s.Notes(:)), newline)}];
end

if isfield(s, 'ExcitationVoltage') && ~isempty(s.ExcitationVoltage)
    cfg = [cfg, {'ExcitationVoltage', s.ExcitationVoltage}];
elseif isfield(s, 'ExcitationSignalVoltage') && ~isempty(s.ExcitationSignalVoltage)
    cfg = [cfg, {'ExcitationVoltage', s.ExcitationSignalVoltage}];
end

if ~isempty(cfg)
    obj.set_configuration(cfg{:});
end
end


% ------------------------------------------------------------------------ %
function d = stale_direction_(offsetDb)
% Which way a stale calibration errs: an overstated level produces an
% understated drive voltage, so the rig plays quieter than asked.
if offsetDb > 0
    d = 'quietly';
else
    d = 'loudly';
end
end
