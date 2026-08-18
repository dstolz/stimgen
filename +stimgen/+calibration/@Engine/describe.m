function s = describe(obj)
% describe(obj)
% s = describe(obj)
%
% Describe this calibration in words: what it was measured with, what each
% table covers, how well it verified, and whatever the operator wrote about
% it in Notes.
%
% With no output the description is printed to the command window; with one
% it is returned as a string and nothing is printed. What it reports is what
% a plot cannot be read off: the settings the tables were measured through,
% the span and spread of each table, the verdict of each verification, and
% the fact that a table is missing at all.
%
% Written to the command window rather than through stimgen.util.vprintf: it
% is the answer to a command the operator typed, not a record of something
% that happened, and a verbosity setting must not be able to swallow it.
%
% Returns:
%   s - (1,1) string; the full description, newline-separated
%
% Example:
%   eng = stimgen.calibration.Engine.load('rig_a.esgc');
%   eng.describe
%
% See also: stimgen.calibration.Engine, stimgen.calibration.CalibrationGui

lines = strings(0, 1);

lines(end+1,1) = "Stim calibration";
lines(end+1,1) = string(repmat('=', 1, 60));

if isnat(obj.CalibrationTimestamp)
    lines(end+1,1) = field_("Measured", "not yet -- no sweep has completed");
else
    lines(end+1,1) = field_("Measured", string(datetime(obj.CalibrationTimestamp, ...
        Format='dd-MMM-yyyy HH:mm:ss')));
end

if strlength(strtrim(obj.Notes)) > 0
    lines(end+1,1) = "";
    lines(end+1,1) = "Notes";
    lines = [lines; indent_(obj.Notes)];
end

% --- What the numbers below were measured through ------------------------
lines(end+1,1) = "";
lines(end+1,1) = "Microphone and scale";
lines(end+1,1) = field_("  Reference", sprintf('%.1f dB SPL at %.10g Hz', ...
    obj.ReferenceLevel, obj.ReferenceFrequency));
lines(end+1,1) = field_("  Mic sensitivity", sprintf('%.5g V/Pa', obj.MicSensitivity));
lines(end+1,1) = field_("  Normative level", sprintf('%.10g dB SPL', obj.NormativeValue));

lines(end+1,1) = "";
lines(end+1,1) = "Drive and acquisition";
lines(end+1,1) = field_("  Excitation", sprintf('%.10g V, tone ramp %.3g ms per edge', ...
    obj.ExcitationVoltage, obj.ToneRampDuration * 1e3));
lines(end+1,1) = field_("  Output ceiling", sprintf('%.10g V', obj.MaxOutputVoltage));
% Recorded, never applied -- the gain is already inside every level in the
% tables. Stated here for the same reason it is stored: a table cannot be
% checked against a later one without knowing the knob positions it was made
% at.
lines(end+1,1) = field_("  Rig gain", sprintf('ADC %+.10g dB, DAC %+.10g dB (recorded only)', ...
    obj.AdcGain, obj.DacAttenuation));
if obj.AcCoupleResponse
    lines(end+1,1) = field_("  AC coupling", sprintf('on, %.10g Hz corner', obj.AcCoupleFrequency));
else
    lines(end+1,1) = field_("  AC coupling", "off");
end
lines(end+1,1) = field_("  Spectral analysis", spectral_(obj));
lines(end+1,1) = field_("  Ambient", sprintf('%.1f C, sound travels %.1f m/s', ...
    obj.AmbientTemperature, obj.SpeedOfSound));
if obj.Fs > 0
    lines(end+1,1) = field_("  Sample rate", sprintf('%.10g Hz (from the attached adapter)', obj.Fs));
else
    lines(end+1,1) = field_("  Sample rate", "unknown -- no adapter attached");
end
lines(end+1,1) = field_("  Tone lookups", tone_source_(obj));
lines(end+1,1) = field_("  Conduction delay", delay_(obj.ConductionDelay));

if obj.IsCalibrated
    calData = obj.CalibrationData;

    % --- The tables themselves -------------------------------------------
    lines(end+1,1) = "";
    lines = [lines; table_lines_(calData, 'tone', "Tone table", "Hz", @(v) sprintf('%.10g', v))];
    lines = [lines; table_lines_(calData, 'click', "Click table", "us", @(v) sprintf('%.10g', v * 1e6))];
    lines = [lines; table_lines_(calData, 'swept_sine', "Swept sine table", "Hz", @(v) sprintf('%.10g', v))];

    if isfield_(calData, 'swept_sine')
        lines = [lines; swept_detail_(calData.swept_sine)];
    end

    lines = [lines; verification_lines_(calData, 'toneTest', "Tone table verification", ...
        'frequency', "Hz", @(v) sprintf('%.10g', v))];
    lines = [lines; verification_lines_(calData, 'clickTest', "Click table verification", ...
        'duration', "us", @(v) sprintf('%.10g', v * 1e6))];

    lines = [lines; filter_lines_(calData)];
    lines = [lines; background_lines_(calData)];
else
    lines(end+1,1) = "";
    lines(end+1,1) = "No calibration data. Nothing has been measured into a lookup table yet.";
end

% One exit, so the print-or-return decision is made once. disp rather than
% an assignment to ans: the newlines are meant to render as the lines they
% are, and a command typed for its output should not also leave a variable
% behind.
txt = strjoin(lines, newline);
if nargout > 0
    s = txt;
else
    disp(txt);
end
end

% -------------------------------------------------------------------------
function s = field_(name, value)
% One "caption  value" line, captions in a fixed column so the values read as
% a column of their own.
s = sprintf('%-20s %s', name, string(value));
end

% -------------------------------------------------------------------------
function out = indent_(text)
% Free text as its own indented block, one string per line.
out = "  " + splitlines(strtrim(string(text)));
end

% -------------------------------------------------------------------------
function s = spectral_(obj)
% The window and transform length every level in the tables was measured
% with. "auto" is not one setting but each estimator making its own choice,
% so it is spelled out rather than named.
if obj.SpectralWindow == "auto"
    w = "each estimator picks its own window";
else
    w = sprintf('%s window', obj.SpectralWindow);
end
if obj.SpectralFftLength == 0
    n = "transform length from the record";
else
    n = sprintf('%d-point transform', obj.SpectralFftLength);
end
s = w + ", " + n;
end

% -------------------------------------------------------------------------
function s = tone_source_(obj)
% Which table actually answers a tone lookup, and whether that table exists.
if obj.ToneLutSource == "swept_sine"
    if isfield_(obj.CalibrationData, 'swept_sine')
        s = "served from the swept sine table";
    else
        s = "set to swept sine, but there is none -- falling back to the tone table";
    end
else
    s = "served from the tone table";
end
end

% -------------------------------------------------------------------------
function s = delay_(d)
% The last acquisition speaker-to-microphone delay. Session state rather than
% calibration data -- a loaded file has none -- so the wording says so
% instead of reporting a NaN.
if ~d.valid || ~isfinite(d.delay_s)
    s = "not measured in this session";
    return
end
s = sprintf('%.3f ms (~%.2f m of air at %.1f m/s)', ...
    d.delay_s * 1e3, d.path_m, d.speed_of_sound_ms);
end

% -------------------------------------------------------------------------
function out = table_lines_(calData, fieldName, title, xUnit, xFmt)
% One lookup table: what it covers, what it produced, and how trustworthy the
% measurements behind it were. The abscissa is named by the caller because
% each table is keyed on a different quantity.
out = strings(0, 1);
if ~isfield_(calData, fieldName)
    out(end+1,1) = field_(title, "not measured");
    out(end+1,1) = "";
    return
end
t = calData.(fieldName);

if isfield(t, 'frequency')
    x = t.frequency(:);
else
    x = t.duration(:);
end
out(end+1,1) = sprintf('%s -- %d point(s), %s to %s %s', title, numel(x), ...
    xFmt(min(x)), xFmt(max(x)), xUnit);

spl = t.spl_db(:);
out(end+1,1) = field_("  Level measured", sprintf('%.1f to %.1f dB SPL (median %.1f)', ...
    min(spl), max(spl), median(spl, 'omitnan')));

v = t.voltage(:);
out(end+1,1) = field_("  Drive needed", sprintf('%.4g to %.4g V at the normative level', ...
    min(v), max(v)));

if isfield(t, 'metrics')
    out = [out; metric_lines_(t.metrics, x, xUnit, xFmt)];
end
if isfield(t, 'refinement') && ~isempty(t.refinement)
    out(end+1,1) = field_("  Refinement", refinement_(t.refinement));
end
out(end+1,1) = "";
end

% -------------------------------------------------------------------------
function out = metric_lines_(m, x, xUnit, xFmt)
% The per-point quality figures, reduced to the two numbers worth reading off
% a summary: the typical value, and where the table is at its worst.
out = strings(0, 1);

if isfield(m, 'snr_db')
    out(end+1,1) = field_("  SNR", worst_(m.snr_db(:), x, xUnit, xFmt, 'min', 'dB'));
end
if isfield(m, 'thd_db')
    out(end+1,1) = field_("  Distortion", worst_(m.thd_db(:), x, xUnit, xFmt, 'max', 'dB THD'));
end
if isfield(m, 'repeatability') && isfinite(m.repeatability.overall_cv_percent)
    out(end+1,1) = field_("  Repeatability", sprintf('%.2f%% CV over %d pass(es)', ...
        m.repeatability.overall_cv_percent, m.repeatability.num_repeats));
end
if isfield(m, 'clipping_headroom')
    h = m.clipping_headroom;
    if h.responseClippingLikely
        out(end+1,1) = field_("  Input headroom", sprintf( ...
            'CLIPPING LIKELY -- peak %.4g V, %.1f dB below full scale', ...
            h.responsePeakV, h.responseHeadroomDb));
    elseif isfinite(h.responseHeadroomDb)
        out(end+1,1) = field_("  Input headroom", sprintf('%.1f dB below full scale', ...
            h.responseHeadroomDb));
    end
end
end

% -------------------------------------------------------------------------
function s = worst_(v, x, xUnit, xFmt, direction, unit)
% "median X, worst Y at Z" for a per-point figure. Which end is worst depends
% on the figure, so the caller names it.
v  = v(:);
ok = isfinite(v);
if ~any(ok)
    s = "not measured";
    return
end
vOk = v(ok);
xOk = x(ok);
if strcmp(direction, 'min')
    [w, i] = min(vOk);
else
    [w, i] = max(vOk);
end
s = sprintf('median %.1f %s, worst %.1f at %s %s', ...
    median(vOk), unit, w, xFmt(xOk(i)), xUnit);
end

% -------------------------------------------------------------------------
function s = refinement_(r)
% What the measure-correct-remeasure loop achieved on this table.
if r.converged
    verdict = 'converged';
else
    verdict = 'did NOT converge';
end
s = sprintf('%s in %d pass(es); worst error %.2f -> %.2f dB (tolerance %.2f dB)', ...
    verdict, r.n_iterations, r.initial_max_abs_error_db, ...
    r.final_max_abs_error_db, r.tolerance_db);
end

% -------------------------------------------------------------------------
function out = swept_detail_(t)
% What only a swept sine measures: the flatness of the deconvolved response
% and the room it was measured in. Its levels are already covered above.
out = strings(0, 1);
if ~isfield(t, 'metrics')
    return
end
m = t.metrics;
out(end+1,1) = "Swept sine analysis";
out(end+1,1) = field_("  Sweep", sprintf('%.10g s %s, %.10g to %.10g Hz', ...
    t.duration, t.chirp_type, t.start_freq, t.stop_freq));
if isfield(m, 'flatness_std_db')
    out(end+1,1) = field_("  Response flatness", sprintf('%.2f dB SD, %.1f dB ripple', ...
        m.flatness_std_db, m.magnitude_ripple_db));
end
if isfield(m, 'group_delay_variation_s')
    out(end+1,1) = field_("  Group delay", sprintf( ...
        '%.3f ms bulk, %.3f ms of variation across the band', ...
        m.bulk_delay_s * 1e3, m.group_delay_variation_s * 1e3));
end
if isfield(m, 'reflections') && isfinite(m.reflections.first_delay_ms)
    out(end+1,1) = field_("  Reflections", sprintf( ...
        '%d resolved; first %.2f ms after the direct sound, %.1f dB down', ...
        numel(m.reflections.delay_ms), m.reflections.first_delay_ms, ...
        m.reflections.first_level_db));
else
    out(end+1,1) = field_("  Reflections", "none resolved above the noise");
end
if isfield(m, 'rt60_s') && isfinite(m.rt60_s)
    out(end+1,1) = field_("  Decay", sprintf('RT60 %.0f ms, C50 %.1f dB, DRR %.1f dB', ...
        m.rt60_s * 1e3, m.c50_db, m.drr_db));
end
out(end+1,1) = "";
end

% -------------------------------------------------------------------------
function out = verification_lines_(calData, fieldName, title, xField, xUnit, xFmt)
% A table test is the evidence the table delivers what it promises, so a
% missing one is worth stating rather than omitting.
%
% xField names the abscissa within the results -- a tone test keys on
% frequency, a click test on duration -- and is the same name inside both the
% worst point and the skipped-point record.
out = strings(0, 1);
if ~isfield_(calData, fieldName)
    out(end+1,1) = field_(title, "not run");
    out(end+1,1) = "";
    return
end
r = calData.(fieldName);

if r.passed
    verdict = 'PASSED';
else
    verdict = 'FAILED';
end
out(end+1,1) = sprintf('%s -- %s, worst error %.2f dB against a %.2f dB tolerance', ...
    title, verdict, r.max_abs_error_db, r.tolerance_db);
out(end+1,1) = field_("  Spread", sprintf('%.2f dB RMS, %.2f dB bias', ...
    r.rms_error_db, r.bias_db));
if isfinite(r.worst.error_db)
    out(end+1,1) = field_("  Worst point", sprintf('%.2f dB at %s %s, %.10g dB SPL requested', ...
        r.worst.error_db, xFmt(r.worst.(xField)), xUnit, r.worst.level_db));
end
% One struct of parallel arrays, not an array of structs: the count is the
% length of a column, not numel of the record.
nSkipped = numel(r.skipped.(xField));
if nSkipped > 0
    out(end+1,1) = field_("  Skipped", sprintf( ...
        '%d point(s) the rig could not reach -- see the test results', nSkipped));
end
out(end+1,1) = field_("  Tested", string(datetime(r.testedOn, Format='dd-MMM-yyyy HH:mm')));
out(end+1,1) = "";
end

% -------------------------------------------------------------------------
function out = filter_lines_(calData)
% The equalizer, and whether anyone checked it. Its taps say nothing on their
% own, so the correction span and group delay stand in for what the filter
% will do to a signal.
out = strings(0, 1);
if ~isfield_(calData, 'filter')
    out(end+1,1) = field_("Equalization filter", "not designed");
    out(end+1,1) = "";
    return
end

d = calData.filterDesign;
out(end+1,1) = sprintf('Equalization filter -- %d taps from the %s table', ...
    d.numCoefficients, d.source);
out(end+1,1) = field_("  Correction", sprintf('%.1f dB span over %.10g to %.10g Hz', ...
    d.correctionDb, d.frequencyRange(1), d.frequencyRange(2)));
out(end+1,1) = field_("  Group delay", sprintf('%d samples at %.10g Hz', ...
    calData.filterGrpDelay, d.sampleRate));
out(end+1,1) = field_("  Designed", string(datetime(d.designedOn, Format='dd-MMM-yyyy HH:mm')));

if isfield_(calData, 'filterTest')
    t = calData.filterTest;
    if t.passed
        verdict = 'PASSED';
    else
        verdict = 'FAILED';
    end
    out(end+1,1) = field_("  Verification", sprintf( ...
        '%s -- ripple %.1f -> %.1f dB against a %.1f dB tolerance', ...
        verdict, t.unfiltered.ripple_db, t.filtered.ripple_db, t.ripple_tolerance_db));
else
    out(end+1,1) = field_("  Verification", "not run");
end
out(end+1,1) = "";
end

% -------------------------------------------------------------------------
function out = background_lines_(calData)
% The noise every table above was measured over.
out = strings(0, 1);
if ~isfield_(calData, 'background')
    out(end+1,1) = field_("Background noise", "not measured");
    return
end
r = calData.background;
out(end+1,1) = sprintf('Background noise -- %.1f dB SPL, %.1f dB(A)', r.spl_db, r.spl_dba);
out(end+1,1) = field_("  Loudest band", sprintf('%.0f Hz at %.1f dB SPL', ...
    r.worst_band.frequency, r.worst_band.level_db));
out(end+1,1) = field_("  Below normative", sprintf('%.1f dB', r.headroom_to_normative_db));
if ~isempty(r.peaks.frequency)
    out(end+1,1) = field_("  Tonal components", sprintf( ...
        '%d above the local floor, loudest %.1f Hz', ...
        numel(r.peaks.frequency), r.peaks.frequency(1)));
end
if ~isempty(r.flags)
    out(end+1,1) = field_("  Findings", sprintf('%d -- see Measure Background', numel(r.flags)));
end
out(end+1,1) = field_("  Measured", string(datetime(r.measuredOn, Format='dd-MMM-yyyy HH:mm')));
end

% -------------------------------------------------------------------------
function tf = isfield_(s, fieldName)
% A table counts as present only when the field exists AND holds something:
% an aborted sweep removes its field, but a fresh struct carries an empty
% filter from the start.
tf = isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName));
end
