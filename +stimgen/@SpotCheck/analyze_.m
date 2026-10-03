function results = analyze_(obj, capture, stimObj)
% results = analyze_(obj, capture, stimObj)
% Reduce one capture and the stimulus that produced it to the comparison.
%
% Two waveforms go in and one verdict comes out: the level that was asked for,
% the level that came back, and everything that qualifies the difference.
%
% The level is measured the way the table that calibrated this stimulus was
% measured, selected by its CalibrationType. That is the point of the whole
% function. A tone's LUT is built from a spectral rms at the tone frequency, so
% measuring a tone with a broadband rms instead would fold every bit of room
% noise in the record into the number and read as a calibration error of a
% decibel or two that is not there. A click's LUT is built from a peak, so a
% click measured as an rms would read tens of dB low -- the record is mostly
% silence between clicks. Only for stimuli with no frequency to anchor to
% (noise, TORC, sound files) is a broadband rms the right instrument.
%
% Peak measurements are converted to their rms equivalent before conversion to
% dB SPL, which is what Engine/compute_spl_voltage_ does when it builds the
% click table, so the two land on one scale.
%
% The rule itself is stimgen.util.level_request (what the stimulus asks for)
% and stimgen.util.level_as_calibrated (how the record is measured), shared
% with stimgen.StimPlayer.capture_stim so the two tools cannot measure one
% stimulus two ways; the warnings are stimgen.CapturedSignal's for the same
% reason.
%
% Parameters:
%   capture - struct from stimgen.calibration.Engine.play_and_capture
%   stimObj - the stimgen.StimType that was played
%
% Returns:
%   results - see stimgen.SpotCheck.run

eng = obj.Engine;
fs  = capture.fs;
x   = capture.excitation;
y   = capture.response;

% ---- What was asked for -------------------------------------------------
% stimgen.util.level_request reads it through active_variant_values, so a
% vectorized stimulus reports the combination that actually produced this
% waveform without advancing the selection just by asking. The rule for how
% to measure it lives there too, shared with StimPlayer's capture.
req         = stimgen.util.level_request(stimObj);
variant     = req.variant;
requestedDb = req.level_db;
calType     = req.calibration_type;
hasCalData  = req.has_calibration_data;
calibrated  = req.calibrated;

% ---- What came back -----------------------------------------------------
% The sensitivity is NaN unless one was actually measured (or entered, or
% loaded); level_as_calibrated then reports volts and no level error, which is
% the truth, instead of a dB SPL on the engine's 1 V/Pa placeholder.
[sens, sensSource] = obj.mic_sensitivity_(stimObj);
lvl = stimgen.util.level_as_calibrated(y, fs, req, sens, ...
    eng.spectral_options());
mode        = lvl.mode;
anchorHz    = lvl.frequency_hz;
measurement = lvl.measurement_v;
levelRef    = lvl.level_reference;
measuredDb  = lvl.level_db;

snrDb = stimgen.CapturedSignal.capture_snr_db(capture);
if isfinite(snrDb) && isfinite(sens)
    noiseDb = stimgen.calibration.Engine.volts_to_spl(capture.noise.rms_v, sens);
else
    noiseDb = nan;
end

% ---- The two waveforms, characterized the same way ----------------------
% The inspector's own analysis, so the numbers stored in a saved result and
% the numbers on screen in the inspector window cannot drift apart.
nH = stimgen.StimInspector.NHarmonics;
stimMetrics = stimgen.StimInspector.signal_metrics(x, fs, nH);
capMetrics  = stimgen.StimInspector.signal_metrics(y, fs, nH);

% ---- Everything that qualifies the comparison ---------------------------
% The sentences are CapturedSignal's, so a spot check and a StimPlayer
% capture of one acquisition say the same things about it.
warnings = [stimgen.CapturedSignal.request_warnings(req), ...
            stimgen.CapturedSignal.capture_warnings(capture)];

switch sensSource
    case "none"
        warnings(end+1) = "No microphone sensitivity has been measured -- " + ...
            "neither this engine nor the stimulus's calibration has a " + ...
            "reference (Measure Reference, or load a calibration that has " + ...
            "one) -- so the recording is reported in volts and no level " + ...
            "error is computed.";
    case "stimulus calibration"
        warnings(end+1) = sprintf("This engine has no measured microphone " + ...
            "sensitivity, so the stimulus's own calibration supplied it " + ...
            "(%.4g V/Pa). The levels are right only if that microphone " + ...
            "chain is the one attached now.", sens);
end

% ---- Assemble -----------------------------------------------------------
errorDb = lvl.error_db;

results = struct();

results.stimulus = struct( ...
    'class',              string(class(stimObj)), ...
    'label',              obj.StimulusLabel, ...
    'file',               obj.StimulusFile, ...
    'fs',                 double(stimObj.Fs), ...
    'duration_s',         numel(x) / fs, ...
    'calibration_type',   calType, ...
    'requested_level_db', requestedDb, ...
    'level_reference',    string(levelRef), ...
    'measurement_mode',   mode, ...
    'frequency_hz',       anchorHz, ...
    'calibrated',         calibrated, ...
    'applies_calibration', logical(stimObj.ApplyCalibration), ...
    'has_calibration_data', hasCalData, ...
    'variant',            variant, ...
    'variant_info',       stimObj.get_variant_info(), ...
    'parameters',         string(stimObj.current_parameter_summary()));

results.measured = struct( ...
    'level_db_spl',    measuredDb, ...
    'level_error_db',  errorDb, ...
    'measurement_v',   measurement, ...
    'rms_v',           rms_(y), ...
    'peak_v',          max(abs(y)), ...
    'crest_factor_db', capMetrics.CrestFactorDb, ...
    'noise_db_spl',    noiseDb, ...
    'snr_db',          snrDb, ...
    'thd_percent',     capMetrics.ThdPercent, ...
    'thd_db',          capMetrics.ThdDb, ...
    'fundamental_hz',  capMetrics.FundamentalHz, ...
    'clipping',        capture.headroom.responseClippingLikely, ...
    'delay_s',         capture.delay_s);

results.capture          = capture;
results.stimulus_metrics = stimMetrics;
results.capture_metrics  = capMetrics;
results.engine           = struct( ...
    'mic_sensitivity_v_per_pa', sens, ...
    'mic_sensitivity_source',   sensSource, ...
    'reference_level_db',       eng.ReferenceLevel, ...
    'max_output_v',             eng.MaxOutputVoltage, ...
    'ac_coupled',               logical(eng.AcCoupleResponse), ...
    'spectral_window',          eng.SpectralWindow, ...
    'notes',                    eng.Notes);
results.warnings   = warnings;
results.measuredOn = capture.measuredOn;
end % analyze_


% =========================================================================

function r = rms_(y)
% r = rms_(y) - Root mean square over the finite samples; 0 for none.
y = y(isfinite(y));
if isempty(y)
    r = 0;
else
    r = sqrt(mean(y .^ 2));
end
end
