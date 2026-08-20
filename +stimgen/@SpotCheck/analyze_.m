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

warnings = string.empty(1, 0);

% ---- What was asked for -------------------------------------------------
% Read through active_variant_values so a vectorized stimulus reports the
% combination that actually produced this waveform, without advancing the
% selection to the next one just by asking.
variant     = stimObj.active_variant_values();
requestedDb = double(active_value_(stimObj, "SoundLevel", variant));
calType     = string(stimObj.CalibrationType);

[mode, anchorHz] = measurement_mode_(stimObj, variant, fs);

hasCalData  = false;
try
    C = stimObj.Calibration;
    hasCalData = isa(C, 'stimgen.StimCalibration') ...
        && isstruct(C.CalibrationData) && ~isempty(C.CalibrationData);
catch
end
calibrated = logical(stimObj.ApplyCalibration) && hasCalData;

% ---- What came back -----------------------------------------------------
switch mode
    case "specfreq"
        measurement = stimgen.calibration.Engine.spectral_rms( ...
            y, anchorHz, fs, Spectral = eng.spectral_options());
        mRms      = measurement;
        levelRef  = sprintf('spectral rms at %.4g Hz', anchorHz);
    case "peak"
        measurement = max(abs(y));
        mRms        = measurement / sqrt(2);
        levelRef    = 'peak, as rms equivalent';
    otherwise
        measurement = rms_(y);
        mRms        = measurement;
        levelRef    = 'broadband rms';
end

measuredDb = eng.spl_from_volts(mRms);

if isfinite(capture.noise.rms_v) && capture.noise.rms_v > 0
    noiseDb = eng.spl_from_volts(capture.noise.rms_v);
    snrDb   = 20 * log10(rms_(y) / capture.noise.rms_v);
else
    noiseDb = nan;
    snrDb   = nan;
end

% ---- The two waveforms, characterized the same way ----------------------
% The inspector's own analysis, so the numbers stored in a saved result and
% the numbers on screen in the inspector window cannot drift apart.
nH = stimgen.StimInspector.NHarmonics;
stimMetrics = stimgen.StimInspector.signal_metrics(x, fs, nH);
capMetrics  = stimgen.StimInspector.signal_metrics(y, fs, nH);

% ---- Everything that qualifies the comparison ---------------------------
if ~logical(stimObj.ApplyCalibration)
    warnings(end+1) = "Apply Calibration is off for this stimulus, so its " + ...
        "waveform is normalized rather than scaled to volts. The measured " + ...
        "level is real, but Sound Level is nominal and the error is meaningless.";
elseif ~hasCalData
    warnings(end+1) = "The stimulus asks for calibration but carries no " + ...
        "calibration data, so it was played un-scaled. The measured level is " + ...
        "real; the requested one is not.";
end

if capture.delay_at_bound
    warnings(end+1) = sprintf( ...
        "The response delay reached the %.0f ms search bound, so the record " + ...
        "was probably cut in the wrong place. Raise Post Delay above the " + ...
        "rig's round-trip latency and run again.", capture.post_delay_s * 1e3);
end

if capture.headroom.responseClippingLikely
    warnings(end+1) = sprintf( ...
        "The recording looks clipped (peak %.4g V, %.1f%% of samples flat at " + ...
        "the peak). Reduce the input gain; every level here is understated.", ...
        capture.headroom.responsePeakV, ...
        100 * capture.headroom.responseFlatTopFraction);
end

if capture.headroom.excitationClippingLikely
    warnings(end+1) = sprintf( ...
        "The excitation peaks at %.4g V, at or above the %.4g V output " + ...
        "ceiling, so the converter clipped it before the speaker saw it.", ...
        capture.headroom.excitationPeakV, capture.headroom.assumedFullScaleV);
end

if isfinite(snrDb) && snrDb < 10
    warnings(end+1) = sprintf( ...
        "Only %.1f dB above the noise floor in this record. The level and " + ...
        "every distortion figure below are dominated by noise.", snrDb);
end

if isfinite(measuredDb) && ~isfinite(eng.MicSensitivity)
    warnings(end+1) = "No microphone sensitivity is set, so dB SPL is " + ...
        "relative to an unmeasured reference.";
end

if capture.repeats > 1
    warnings(end+1) = sprintf( ...
        "%d acquisitions were averaged, which lowers noise on the response " + ...
        "but not on the noise floor it is compared with, so the %.1f dB SNR " + ...
        "is pessimistic by up to %.1f dB.", capture.repeats, snrDb, ...
        10 * log10(capture.repeats));
end

% ---- Assemble -----------------------------------------------------------
if calibrated
    errorDb = measuredDb - requestedDb;
else
    errorDb = nan;
end

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
    'mic_sensitivity_v_per_pa', eng.MicSensitivity, ...
    'reference_level_db',       eng.ReferenceLevel, ...
    'max_output_v',             eng.MaxOutputVoltage, ...
    'ac_coupled',               logical(eng.AcCoupleResponse), ...
    'spectral_window',          eng.SpectralWindow, ...
    'notes',                    eng.Notes);
results.warnings   = warnings;
results.measuredOn = capture.measuredOn;
end % analyze_


% =========================================================================

function [mode, anchorHz] = measurement_mode_(stimObj, variant, fs)
% [mode, anchorHz] = measurement_mode_(stimObj, variant, fs)
% How to measure this stimulus's level, chosen to match the calibration table
% it was scaled by. See the header of this file for why it matters.
%
% Returns:
%   mode     - "specfreq" | "peak" | "rms", the Engine's own measurement modes
%   anchorHz - frequency the spectral measurement is taken at; NaN otherwise

anchorHz = nan;

switch string(stimObj.CalibrationType)
    case "tone"
        anchorHz = double(active_value_(stimObj, "Frequency", variant));
        mode     = "specfreq";

    case "click"
        mode = "peak";

    case "swept_sine"
        % The LUT is keyed on the geometric mean of the sweep limits, but a
        % sweep's energy is spread across its whole span and there is no single
        % bin holding it. Broadband rms is the honest instrument for the
        % waveform even though the table was keyed on one frequency.
        mode = "rms";

    otherwise
        mode = "rms";
end

if mode == "specfreq" && (~isfinite(anchorHz) || anchorHz <= 0 || anchorHz >= fs/2)
    % An unusable anchor would make spectral_rms measure an arbitrary bin.
    mode     = "rms";
    anchorHz = nan;
end
end


function v = active_value_(stimObj, propName, variant)
% v = active_value_(stimObj, propName, variant)
% One property's value for the active variant, without advancing the cycle.
% Scalar properties are returned as they are; vectorized ones come from the
% combination table that active_variant_values already resolved.
name = char(propName);

if ~isprop(stimObj, name)
    v = nan;
    return
end

raw = stimObj.(name);
if numel(raw) <= 1
    v = raw;
    return
end

if isstruct(variant) && isfield(variant, name)
    v = variant.(name);
else
    v = raw(1);
end
end


function r = rms_(y)
% r = rms_(y) - Root mean square over the finite samples; 0 for none.
y = y(isfinite(y));
if isempty(y)
    r = 0;
else
    r = sqrt(mean(y .^ 2));
end
end
