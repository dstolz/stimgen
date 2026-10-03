function restore(obj, s, options)
% restore(obj, s)
% Restore engine state from a serialized struct.
%
% The measurement properties are SetAccess = protected, so callers outside
% the class -- notably stimgen.StimCalibration.loadobj, which rebuilds a
% calibration from a .spl bank or a serialized StimType -- cannot assign
% them directly. This is the supported entry point for that.
%
% Accepts either field naming in use:
%   ExcitationVoltage        (Engine.to_struct: .esgc files, and
%                             StimCalibration.toStruct/saveobj since)
%   ExcitationSignalVoltage  (StimCalibration structs written before that)
%
% Missing fields keep their current values, so a partial struct from an
% older file is safe.
%
% This is the one restore path: Engine.load reads a .esgc through it, and
% StimCalibration.loadobj a calibration embedded in a bank or a StimType.
% Both are written by to_struct.
%
% Parameters:
%   s      - struct of engine properties
%   Source - (optional) where s came from, e.g. the .esgc path; named in the
%            stale-scale warning

arguments
    obj (1,1) stimgen.calibration.Engine
    s   (1,1) struct
    options.Source (1,1) string = ""
end

% A struct written before the level scale was corrected carries tables that
% double-counted the calibrator. Version 2 marks the fix; anything older, or
% unversioned, is only ambiguous when the calibrator was not the default 94 dB,
% because that is the one setting at which the two scales agree.
%
% Reported rather than corrected. The correction is arithmetic --
% tone/click/swept_sine voltages scale by 10^((ReferenceLevel-94)/20) and
% their spl_db shift by -(ReferenceLevel-94) -- but a rig whose levels were
% visibly wrong may already have been compensated somewhere else, and
% silently moving measurement data underneath a user who cannot see it happen
% is worse than telling them plainly.
if isfield(s, 'ReferenceLevel') && ~isempty(s.ReferenceLevel)
    stale = ~isfield(s, 'version') || isempty(s.version) || s.version < 2;
    offsetDb = double(s.ReferenceLevel) - 94;
    if stale && abs(offsetDb) >= 0.05
        if options.Source == ""
            what = 'This calibration';
        else
            what = sprintf('Calibration "%s"', options.Source);
        end
        stimgen.util.vprintf(0, 1, ...
            ['%s was saved on the old level scale, which added the %.1f dB ' ...
             'calibrator level on top of the 20 uPa reference. Every level in ' ...
             'it is %+.1f dB off and its drive voltages are %+.1f dB the other ' ...
             'way, so this rig would play about %.1f dB too %s. Re-run the ' ...
             'reference and the sweeps to rebuild it.'], ...
            what, s.ReferenceLevel, offsetDb, -offsetDb, abs(offsetDb), ...
            stale_direction_(offsetDb));
    end
end

if isfield(s, 'CalibrationData') && isstruct(s.CalibrationData)
    % A table written before schema version 3 does not say which level its
    % voltages were solved for. The NormativeValue saved beside it is the one
    % that solved them -- a sweep commits at the engine's current setting, and
    % that setting is what to_struct wrote -- so it is stamped on now, once,
    % rather than leaving compute_adjusted_voltage to fall back on whatever
    % the setting happens to be later. Without one in the struct the engine's
    % own value stands in, which is what the lookup used before the field
    % existed. A table that already records its level is left alone.
    if isfield(s, 'NormativeValue') && isscalar(s.NormativeValue) ...
            && isfinite(s.NormativeValue)
        savedNormative = double(s.NormativeValue);
    else
        savedNormative = obj.NormativeValue;
    end
    obj.CalibrationData = stamp_normative_(s.CalibrationData, savedNormative);
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
                "ToneRampDuration", "AmbientTemperature", ...
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

% Whether the sensitivity is a real one. set_configuration above marks it
% known whenever it changed the value, so the struct's own record is applied
% after it and wins. A struct written before the flag existed is judged by its
% value: only the 1 V/Pa placeholder an engine starts with counts as unknown,
% since no measurement chain lands on exactly that and a calibrator reading
% always replaces it. Without either field the engine's own state stands.
if isfield(s, 'MicSensitivityKnown') && ~isempty(s.MicSensitivityKnown)
    obj.MicSensitivityKnown = logical(s.MicSensitivityKnown);
elseif isfield(s, 'MicSensitivity') && ~isempty(s.MicSensitivity)
    obj.MicSensitivityKnown = double(s.MicSensitivity) ~= 1;
end
end


% ------------------------------------------------------------------------ %
function cd = stamp_normative_(cd, normativeDb)
% Record normative_db on every lookup table that does not carry one.
names = {'tone', 'click', 'swept_sine'};
for k = 1:numel(names)
    f = names{k};
    if isfield(cd, f) && isstruct(cd.(f)) && isscalar(cd.(f)) ...
            && ~isfield(cd.(f), 'normative_db')
        cd.(f).normative_db = normativeDb;
    end
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
