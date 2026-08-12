function results = test_filter(obj, options)
% results = test_filter(obj)
% results = test_filter(obj, Name=Value)
% Empirically verify the equalization filter designed by design_filter.
%
% Plays the same log-sine chirp twice at ExcitationVoltage: once raw, and
% once passed through the filter and renormalized to peak - the same
% filter -> normalize path apply_calibration drives a real stimulus through.
% Both responses are deconvolved against the *raw* chirp, so the first
% measurement is the speaker's transfer function and the second is the
% filter+speaker chain. A working filter leaves that second curve
% approximately flat: its ripple should collapse toward the design residual
% rather than track the speaker's raw response. Deconvolving the filtered
% response by the filtered excitation instead would divide the filter back
% out and measure the bare speaker twice.
%
% Requires an adapter and a designed filter. Nothing in the calibration
% LUTs is modified; results are returned and also stored in
% CalibrationData.filterTest, so a saved .esgc records that its filter was
% verified and how flat the equalized response came out.
%
% While the test runs, LiveUpdate events are broadcast with stage
% "filter_test" (gated by ShowLivePlots), so an attached LiveMonitor shows
% the unfiltered transfer curve fill in and then be replaced by the
% flattened one.
%
% Name-Value Parameters:
%   Duration          - chirp length in seconds (default: 1)
%   RepeatCount       - captures to average per condition (default: 2)
%   TailDuration      - trailing silence in seconds so the decay is still
%                       recorded after the sweep ends (default: 0.5)
%   NumPoints         - frequency points sampled across the equalized band
%                       (default: 50)
%   RippleToleranceDb - peak-to-peak ripple of the equalized response at or
%                       below which the test is reported passed (default: 6)
%
% Returns:
%   results - struct:
%     frequency        - (N,1) sampled frequencies in Hz
%     band             - [lo hi] Hz equalized band under test
%     sweep_band       - [start stop] Hz band the chirp actually swept
%     duration, repeat_count, excitation_voltage - test conditions
%     unfiltered       - struct: measurement (mic V), level_db,
%                        deviation_db (re band mean), spl_db,
%                        flatness_std_db, ripple_db
%     filtered         - same fields for the filter+speaker chain
%     ripple_improvement_db - unfiltered ripple minus filtered ripple
%     std_improvement_db    - same comparison for the flatness std
%     ripple_tolerance_db   - the pass criterion applied
%     passed           - true when filtered ripple <= RippleToleranceDb
%     testedOn         - datetime of the run
%
% Example:
%   eng.design_filter("swept_sine", SmoothingOctaves=1/6);
%   r = eng.test_filter();
%   fprintf('ripple %.1f -> %.1f dB\n', r.unfiltered.ripple_db, r.filtered.ripple_db);
%
% See also: stimgen.calibration.Engine/design_filter,
%           stimgen.util.filter_aligned
arguments
    obj
    options.Duration          (1,1) double {mustBePositive, mustBeFinite} = 1
    options.RepeatCount       (1,1) double {mustBeInteger, mustBePositive, mustBeFinite} = 2
    options.TailDuration      (1,1) double {mustBeNonnegative, mustBeFinite} = 0.5
    options.NumPoints         (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual(options.NumPoints, 5)} = 50
    options.RippleToleranceDb (1,1) double {mustBePositive, mustBeFinite} = 6
end

% Same margin calibrate_swept_sine uses, for the same reason: a point sampled
% at the chirp's stop frequency is read off the roll-off shoulder.
SWEEP_MARGIN_OCT = 1/6;

obj.assert_adapter_();
obj.reset_cancel_();

cal = obj.CalibrationData;
if ~isstruct(cal) || ~isfield(cal, 'filter') || isempty(cal.filter)
    error('stimgen:calibration:Engine:noFilter', ...
        'No equalization filter to test. Run design_filter after a tone or swept sine calibration.');
end
filt = cal.filter;

gd = 0;
if isfield(cal, 'filterGrpDelay')
    gd = round(cal.filterGrpDelay);
end

fs = obj.Fs;
if ~isfinite(fs) || fs <= 0
    error('stimgen:calibration:Engine:noSampleRate', ...
        'The filter test needs a sample rate, which comes from the hardware adapter.');
end
nyq       = fs / 2;
maxUsable = 0.95 * nyq;

% A FIR's coefficients realize the designed magnitude only at the rate it was
% designed for; testing it at another rate would report the wrong response as
% the filter's fault.
if isfield(cal, 'filterDesign') && isfinite(cal.filterDesign.sampleRate) ...
        && abs(cal.filterDesign.sampleRate - fs) > 1e-6 * fs
    error('stimgen:calibration:Engine:filterRateMismatch', ...
        'The filter was designed at Fs = %.4f Hz but the adapter runs at %.4f Hz. Redesign the filter at the current rate.', ...
        cal.filterDesign.sampleRate, fs);
end

% --- Band under test: the band the filter was designed to equalize ---------
band = [];
if isfield(cal, 'filterDesign') && isfield(cal.filterDesign, 'frequencyRange')
    band = double(cal.filterDesign.frequencyRange);
end
if numel(band) ~= 2 || ~all(isfinite(band))
    % Filter predates filterDesign metadata: fall back to the span of the LUT
    % it was designed from.
    src = "tone";
    if isfield(cal, 'filterSource'), src = string(cal.filterSource); end
    if ~isfield(cal, src) || isempty(cal.(src))
        error('stimgen:calibration:Engine:noFilterBand', ...
            'Cannot determine the equalized band: the filter records no design range and no %s LUT is present.', src);
    end
    band = [min(cal.(src).frequency), max(cal.(src).frequency)];
end
band(1) = max(band(1), fs / 1e6);
band(2) = min(band(2), maxUsable);
if band(2) <= band(1)
    error('stimgen:calibration:Engine:sampleRateTooLow', ...
        'Sample rate %g Hz leaves no usable test band inside the filter''s %g-%g Hz design range.', ...
        fs, band(1), band(2));
end

freqs = logspace(log10(band(1)), log10(band(2)), options.NumPoints);

% Sweep wider than we report, as far as the sample rate allows.
startFreq = max(band(1) * 2^(-SWEEP_MARGIN_OCT), eps);
stopFreq  = min(band(2) * 2^( SWEEP_MARGIN_OCT), maxUsable);

so = stimgen.SweptSine;
so.Fs             = fs;
so.Duration       = options.Duration;
so.StartFrequency = startFreq;
so.StopFrequency  = stopFreq;
so.ChirpType      = "log-sine";
so.ApplyCalibration = false;   % the raw condition must stay raw; scaling by
                               % the LUT would fold it into both measurements
so.update_signal();

base = reshape(so.Signal, 1, []);
pad  = zeros(1, round(options.TailDuration * fs));

xRaw = [obj.ExcitationVoltage .* base, pad];

% Filter, then renormalize to peak, exactly as apply_calibration does before
% level scaling - so the chain measured here is the chain a stimulus takes.
xf = stimgen.util.filter_aligned(filt, base, gd);
xf = xf ./ max(max(abs(xf)), eps);
xFilt = [obj.ExcitationVoltage .* xf, pad];

n         = numel(freqs);
condNames = ["unfiltered", "filtered"];
condSigs  = {xRaw, xFilt};
nReps     = options.RepeatCount;
measured  = cell(1, 2);

axisMeta = {'XLabel', "frequency (Hz)", 'XScale', "log", 'XFactor', 1};
totalCaptures = 2 * nReps;
captureNum    = 0;
clipWarned    = false;

tbl = obj.empty_table_(n);
tbl.x = freqs(:).';

obj.begin_run_();
obj.emit_live_("filter_test", "start", 'Table', tbl, 'Total', n, ...
    'RepeatTotal', nReps, 'Progress', 0, axisMeta{:});

try
    for c = 1:2
        x = condSigs{c};
        obj.ExcitationSignal = x;
        measAll = nan(nReps, n);
        tbl = obj.empty_table_(n);
        tbl.x = freqs(:).';

        for rep = 1:nReps
            obj.throw_if_cancelled_();
            stimgen.util.vprintf(1, '[%d/%d] Capturing %s sweep for filter test...', ...
                rep, nReps, condNames(c));
            raw = obj.Adapter.play_and_record(x);
            response = obj.demean_response_(obj.trim_response_(raw));
            obj.ResponseSignal = response;

            % Both conditions deconvolve against the raw chirp - see the note
            % in the header. The filtered condition's flat renormalization
            % gain rides along, which flatness statistics cannot see.
            measAll(rep, :) = obj.sweep_transfer_rms_(xRaw, response, freqs, fs, ...
                [startFreq stopFreq]);

            h = obj.estimate_headroom_(x, response);
            if ~clipWarned && (h.responseClippingLikely || h.excitationClippingLikely)
                clipWarned = true;
                stimgen.util.vprintf(0, 1, ...
                    'Filter test: clipping likely during the %s sweep; the flatness result is unreliable. Lower ExcitationVoltage.', ...
                    condNames(c));
            end

            captureNum = captureNum + 1;
            if obj.ShowLivePlots
                for i = 1:n
                    mAvg = mean(measAll(1:rep, i), 'omitnan');
                    [spl, volt] = obj.compute_spl_voltage_(mAvg, "specfreq");
                    tbl.measurement(i) = mAvg;
                    tbl.spl_db(i)      = spl;
                    tbl.voltage(i)     = volt;
                end
                tbl.sd_db = obj.level_sd_db_(measAll);
                obj.emit_live_("filter_test", "measure", 'Table', tbl, ...
                    'Index', 0, 'Total', n, 'Repeat', rep, 'RepeatTotal', nReps, ...
                    'Progress', captureNum / totalCaptures, axisMeta{:});
            end
        end

        measured{c} = mean(measAll, 1, 'omitnan');
    end
catch ME
    stimgen.util.vprintf(0, 2, 'Filter test aborted: %s', ME.message);
    rethrow(ME);
end

% --- Flatness statistics ---------------------------------------------------
results = struct;
results.frequency          = freqs(:);
results.band               = band;
results.sweep_band         = [startFreq stopFreq];
results.duration           = options.Duration;
results.repeat_count       = nReps;
results.excitation_voltage = obj.ExcitationVoltage;

for c = 1:2
    m   = measured{c}(:);
    lvl = 20 * log10(max(m, eps));
    dev = lvl - mean(lvl);
    spl = nan(n, 1);
    for i = 1:n
        spl(i) = obj.compute_spl_voltage_(m(i), "specfreq");
    end
    results.(condNames(c)) = struct( ...
        'measurement',     m, ...
        'level_db',        lvl, ...
        'deviation_db',    dev, ...
        'spl_db',          spl, ...
        'flatness_std_db', std(dev), ...
        'ripple_db',       max(lvl) - min(lvl));
end

results.ripple_improvement_db = results.unfiltered.ripple_db - results.filtered.ripple_db;
results.std_improvement_db    = results.unfiltered.flatness_std_db - results.filtered.flatness_std_db;
results.ripple_tolerance_db   = options.RippleToleranceDb;
results.passed                = results.filtered.ripple_db <= options.RippleToleranceDb;
results.testedOn              = datetime('now');

obj.CalibrationData.filterTest = results;

% Final table shows the equalized curve - the state the run exists to verify.
obj.emit_live_("filter_test", "done", 'Table', tbl, ...
    'Index', 0, 'Total', n, 'Repeat', nReps, 'RepeatTotal', nReps, ...
    'Progress', 1, axisMeta{:});

if results.passed
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
stimgen.util.vprintf(1, ...
    'Filter test %s over %g-%g Hz: ripple %.1f -> %.1f dB (tolerance %.1f dB), flatness std %.2f -> %.2f dB', ...
    verdict, band(1), band(2), ...
    results.unfiltered.ripple_db, results.filtered.ripple_db, options.RippleToleranceDb, ...
    results.unfiltered.flatness_std_db, results.filtered.flatness_std_db);
end
