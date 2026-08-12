function results = test_clicks(obj, durs, levels, options)
% results = test_clicks(obj)
% results = test_clicks(obj, durs)
% results = test_clicks(obj, durs, levels)
% results = test_clicks(obj, durs, levels, Name=Value)
% Verify the click lookup table by playing clicks at requested levels and
% measuring what actually came out.
%
% For every duration/level pair the drive voltage is taken from
% compute_adjusted_voltage -- the same call apply_calibration makes when it
% scales a stimgen.ClickTrain -- so this measures the level normalization a
% real experiment gets, not a reimplementation of it. A single click is
% played at that voltage, its peak is measured the way calibrate_clicks
% measures one, and the level that comes back is compared to the level that
% was asked for. A working LUT leaves that error near zero at every duration
% and every level.
%
% By default the test durations are the geometric midpoints between
% successive LUT durations: the durations the calibration never measured,
% where makima interpolation is doing all the work. Reusing the LUT's own
% durations would interrogate the interpolant's knots, which reproduce the
% measurement by construction, and say nothing about what happens between
% them. Testing several levels also exercises the other half of the model --
% that level scales as 20*log10 of drive voltage away from NormativeValue --
% which a single-level test cannot see at all.
%
% The click is rendered by the same stimgen.ClickTrain configuration
% calibrate_clicks sweeps with, and measured by the same peak metric: a
% difference in either would surface as a level error the LUT never had.
% Clicks are broadband and brief, so there is no burst schedule and no
% conduction delay to resolve -- the peak of the record is the peak of the
% click wherever in the record it landed.
%
% Requires an adapter and a click calibration. Nothing in the LUTs is
% modified; results are returned and also stored in
% CalibrationData.clickTest, so a saved .esgc records that its click table
% was verified and how accurate it proved.
%
% Durations shorter than one sample at the current Fs cannot be rendered and
% are dropped with a message. Points whose required drive exceeds
% MaxOutputVoltage are skipped rather than played: they would clip, and
% clipping measures the amplifier, not the LUT. They are reported in
% results.skipped and logged, never dropped silently.
%
% While the test runs, LiveUpdate events are broadcast with stage
% "click_test" (gated by ShowLivePlots), so an attached LiveMonitor shows the
% measured level fill in against the requested one, one level at a time.
%
% Parameters:
%   durs   - (1,:) double test click durations in seconds (default:
%            geometric midpoints of the LUT durations, at most 10 of them)
%   levels - (1,:) double requested levels in dB SPL (default:
%            NormativeValue - [20 10 0])
%
% Name-Value Parameters:
%   RepeatCount - measurements averaged per point (default: 2)
%   ToleranceDb - absolute level error at or below which the test is
%                 reported passed (default: 3)
%   MinSnrDb    - SNR below which a point is treated as unreliable and
%                 excluded from the verdict (default: 10)
%
% Returns:
%   results - struct. Matrices are duration-by-level:
%     duration, level_db     - the grid that was tested
%     drive_voltage          - volts the LUT asked for at each point
%     measured_spl_db        - level that came back (peak-equivalent, the
%                              scale the click LUT itself is on)
%     error_db               - measured minus requested
%     sd_db                  - across-repeat spread of the measured level
%     snr_db, thd_db         - measurement quality per point
%     clipping               - response clipped at this point
%     extrapolated           - (D,1) duration outside the LUT's span
%     tested                 - point was played and measured
%     reliable               - tested, in SNR, and unclipped: the verdict set
%     max_abs_error_db, rms_error_db, bias_db - over the reliable set
%     level_bias_db          - (1,L) mean error at each requested level
%     level_max_abs_error_db - (1,L) worst error at each requested level
%     duration_max_abs_error_db - (D,1) worst error at each duration
%     worst                  - struct: duration, level_db, error_db of the
%                              single worst reliable point
%     skipped                - struct of duration, level_db, drive_voltage,
%                              reason for every point not played
%     tolerance_db, min_snr_db - the criteria applied
%     repeat_count           - test condition
%     passed                 - true when every reliable point is within
%                              ToleranceDb and at least one point was reliable
%     testedOn               - datetime of the run
%
% Example:
%   eng.calibrate_clicks();
%   r = eng.test_clicks();
%   fprintf('worst LUT error %.2f dB at %.1f us / %g dB SPL\n', ...
%       r.worst.error_db, r.worst.duration*1e6, r.worst.level_db);
%
% See also: stimgen.calibration.Engine/calibrate_clicks,
%           stimgen.calibration.Engine/compute_adjusted_voltage,
%           stimgen.calibration.Engine/test_tones
arguments
    obj
    durs   (1,:) double {mustBePositive, mustBeFinite} = []
    levels (1,:) double {mustBeFinite} = []
    options.RepeatCount (1,1) double {mustBeInteger, mustBePositive, mustBeFinite} = 2
    options.ToleranceDb (1,1) double {mustBePositive, mustBeFinite} = 3
    options.MinSnrDb    (1,1) double {mustBeFinite} = 10
end

% At most this many default test points, so a 20-point LUT does not turn into
% a 19-point-by-3-level run nobody asked for.
MAX_DEFAULT_POINTS = 10;

obj.assert_adapter_();
obj.reset_cancel_();

fs = obj.Fs;
if ~isfinite(fs) || fs <= 0
    error('stimgen:calibration:Engine:noSampleRate', ...
        'The click LUT test needs a sample rate, which comes from the hardware adapter.');
end

cal = obj.CalibrationData;
if ~obj.IsCalibrated || ~isfield(cal, 'click') || isempty(cal.click)
    error('stimgen:calibration:Engine:missingTypeCalibration', ...
        ['Calibration data for type "click" is not available. Run a click ' ...
         'calibration before testing the click lookup table.']);
end
lutDur = double(cal.click.duration(:)).';

if isempty(durs)
    durs = default_test_durs_(lutDur, MAX_DEFAULT_POINTS);
end
if isempty(levels)
    levels = obj.NormativeValue - [20 10 0];
end
durs   = unique(durs);     % also sorts, so the transfer curve is drawn in order
levels = unique(levels);

% ClickTrain renders round(fs*dur) samples and requires at least one, the same
% floor calibrate_clicks applies to its own sweep.
resolvable = round(fs .* durs) >= 1;
if ~all(resolvable)
    stimgen.util.vprintf(0, 1, ...
        'Click LUT test: dropping %d duration(s) below one sample at Fs = %.0f Hz (minimum %.2f us).', ...
        nnz(~resolvable), fs, 0.5e6 / fs);
    durs = durs(resolvable);
end
if isempty(durs)
    error('stimgen:calibration:Engine:noTestDurations', ...
        'No test duration reaches one sample at Fs = %.0f Hz.', fs);
end

% Outside the LUT's span makima extrapolates, which is a property of the
% interpolant rather than of the calibration. Such points are still played and
% still count -- an extrapolated level really is what a stimulus there would
% get -- but they are flagged so a failure is not mistaken for a bad LUT.
extrapolated = durs(:) < min(lutDur) | durs(:) > max(lutDur);
if any(extrapolated)
    stimgen.util.vprintf(0, 1, ...
        ['Click LUT test: %d test duration(s) lie outside the %.2f-%.2f us LUT span ' ...
         'and are extrapolated.'], nnz(extrapolated), min(lutDur)*1e6, max(lutDur)*1e6);
end

nD = numel(durs);
nL = numel(levels);

% --- Drive voltages, through the same call apply_calibration makes ---------
drive = nan(nD, nL);
for li = 1:nL
    drive(:, li) = reshape(obj.compute_adjusted_voltage("click", durs, levels(li)), [], 1);
end

playable = isfinite(drive) & drive > 0 & drive <= obj.MaxOutputVoltage;
[skipped, nOver] = skipped_points_(durs, levels, drive, playable, obj.MaxOutputVoltage);
if nOver > 0
    stimgen.util.vprintf(0, 1, ...
        ['Click LUT test: skipping %d of %d point(s) needing more than the %g V ' ...
         'output ceiling; they would clip. See results.skipped.'], ...
        nOver, nD * nL, obj.MaxOutputVoltage);
end
if ~any(playable(:))
    error('stimgen:calibration:Engine:noPlayablePoints', ...
        ['Every requested duration/level pair needs more than the %g V output ' ...
         'ceiling. Test lower levels, or raise MaxOutputVoltage if the rig allows it.'], ...
        obj.MaxOutputVoltage);
end

% --- Stimulus, identical to the one calibrate_clicks sweeps with -----------
% Everything is set at construction, before the listeners attach: the class
% default ClickDuration (20 us) is less than one sample at the lower TDT
% rates, so assigning Fs to an already-listening object would fail
% update_signal until the first real duration lands.
so = stimgen.ClickTrain('Fs', fs, 'ClickDuration', durs(1), ...
    'Duration', 0.05, 'Rate', 1, 'WindowFcn', "", 'OnsetDelay', 0.01);

nReps = options.RepeatCount;

measSplAll = nan(nReps, nD, nL);   % dB SPL per repeat
measAll    = nan(nReps, nD, nL);   % linear peak volts, for the spread
snrAll     = nan(nReps, nD, nL);
thdAll     = nan(nReps, nD, nL);
clipAny    = false(nD, nL);

axisMeta = {'XLabel', "click duration (\mus)", 'XScale', "log", 'XFactor', 1e6};
captureNum    = 0;
totalCaptures = nnz(playable) * nReps;

tbl = obj.empty_table_(nD);
tbl.x = durs(:).';

obj.begin_run_();
obj.emit_live_("click_test", "start", 'Table', tbl, 'Total', nD, ...
    'RepeatTotal', nReps, 'Progress', 0, axisMeta{:});

try
    for li = 1:nL
        levelDb = levels(li);

        % One table per level: the curve on screen is the measured level
        % against the one level that was requested, so mixing levels into it
        % would draw a staircase and hide the error the run exists to show.
        tbl = obj.empty_table_(nD);
        tbl.x = durs(:).';

        stimgen.util.vprintf(1, 'Click LUT test: level %d/%d, %g dB SPL, %d point(s)', ...
            li, nL, levelDb, nnz(playable(:, li)));

        for i = 1:nD
            obj.throw_if_cancelled_();
            if ~playable(i, li), continue; end

            so.ClickDuration = durs(i);
            so.update_signal();
            y = drive(i, li) .* so.Signal;
            obj.ExcitationSignal = y;

            for rep = 1:nReps
                obj.throw_if_cancelled_();
                stimgen.util.vprintf(2, '[%d/%d] Click test: %.2f us at %g dB SPL, %.4f V', ...
                    rep, nReps, durs(i)*1e6, levelDb, drive(i, li));

                m = obj.measure_(y, "peak");
                measAll(rep, i, li)    = m;
                measSplAll(rep, i, li) = obj.compute_spl_voltage_(m, "peak");

                response = obj.ResponseSignal;
                [~, snrAll(rep, i, li)] = obj.estimate_noise_snr_(response, fs, nan);
                thdAll(rep, i, li) = thd(response, fs);

                h = obj.estimate_headroom_(y, response);
                clipAny(i, li) = clipAny(i, li) || ...
                    h.responseClippingLikely || h.excitationClippingLikely;

                captureNum = captureNum + 1;
                if obj.ShowLivePlots
                    % Running average rather than the finished point: on a
                    % many-pass run that is the difference between a curve
                    % that grows steadily and one that stalls for seconds.
                    tbl.measurement(i) = mean(measAll(1:rep, i, li), 'omitnan');
                    tbl.spl_db(i)      = mean(measSplAll(1:rep, i, li), 'omitnan');
                    tbl.voltage(i)     = drive(i, li);
                    tbl.sd_db          = obj.level_sd_db_(measAll(:, :, li));
                    obj.emit_live_("click_test", "measure", 'Table', tbl, ...
                        'Index', i, 'Total', nD, ...
                        'Repeat', rep, 'RepeatTotal', nReps, ...
                        'Progress', captureNum / totalCaptures, ...
                        axisMeta{:}, ...
                        'Metrics', struct('spl_db', tbl.spl_db(i), ...
                                          'voltage', drive(i, li), ...
                                          'snr_db', snrAll(rep, i, li), ...
                                          'thd_db', thdAll(rep, i, li)));
                end
            end
        end
    end
catch ME
    stimgen.util.vprintf(0, 2, 'Click LUT test aborted: %s', ME.message);
    rethrow(ME);
end

% --- Accuracy statistics ---------------------------------------------------
measuredSpl = reshape(mean(measSplAll, 1, 'omitnan'), nD, nL);
snr         = reshape(mean(snrAll,     1, 'omitnan'), nD, nL);
thdDb       = reshape(mean(thdAll,     1, 'omitnan'), nD, nL);

sd = nan(nD, nL);
for li = 1:nL
    sd(:, li) = obj.level_sd_db_(measAll(:, :, li)).';
end

tested   = playable & isfinite(measuredSpl);
error_db = measuredSpl - repmat(levels(:).', nD, 1);

% Only the SNR floor disqualifies a point. A noise-dominated measurement reads
% high and would fail the test for something the LUT did not do, so it has to
% be excluded. Clipping is the opposite case: it reads low, and that error is
% real -- a level the rig cannot deliver cleanly is a level the LUT does not
% deliver. Such points stay in the verdict and results.clipping says why they
% missed.
reliable = tested & isfinite(snr) & snr >= options.MinSnrDb;

results = struct;
results.duration        = durs(:);
results.level_db        = levels(:).';
results.drive_voltage   = drive;
results.measured_spl_db = measuredSpl;
results.error_db        = error_db;
results.sd_db           = sd;
results.snr_db          = snr;
results.thd_db          = thdDb;
results.clipping        = clipAny;
results.extrapolated    = extrapolated;
results.tested          = tested;
results.reliable        = reliable;

e = error_db(reliable);
results.max_abs_error_db = max_or_nan_(abs(e));
results.rms_error_db     = sqrt(mean(e .^ 2, 'omitnan'));
results.bias_db          = mean(e, 'omitnan');
if isempty(e)
    results.rms_error_db = nan;
    results.bias_db      = nan;
end

results.level_bias_db          = nan(1, nL);
results.level_max_abs_error_db = nan(1, nL);
for li = 1:nL
    el = error_db(reliable(:, li), li);
    results.level_bias_db(li)          = mean(el, 'omitnan');
    results.level_max_abs_error_db(li) = max_or_nan_(abs(el));
end

results.duration_max_abs_error_db = nan(nD, 1);
for di = 1:nD
    results.duration_max_abs_error_db(di) = max_or_nan_(abs(error_db(di, reliable(di, :))));
end

results.worst = worst_point_(durs, levels, error_db, reliable);

results.skipped      = skipped;
results.tolerance_db = options.ToleranceDb;
results.min_snr_db   = options.MinSnrDb;
results.repeat_count = nReps;
results.passed       = any(reliable(:)) && ...
    results.max_abs_error_db <= options.ToleranceDb;
results.testedOn     = datetime('now');

obj.CalibrationData.clickTest = results;

obj.emit_live_("click_test", "done", 'Table', tbl, ...
    'Index', 0, 'Total', nD, 'Repeat', nReps, 'RepeatTotal', nReps, ...
    'Progress', 1, axisMeta{:});

if results.passed
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
stimgen.util.vprintf(1, ...
    ['Click LUT test %s: worst error %.2f dB (tolerance %.1f dB), bias %+.2f dB, ' ...
     'rms %.2f dB over %d of %d point(s)'], ...
    verdict, results.max_abs_error_db, options.ToleranceDb, ...
    results.bias_db, results.rms_error_db, nnz(reliable), nD * nL);

nUnreliable = nnz(tested & ~reliable);
if nUnreliable > 0
    stimgen.util.vprintf(0, 1, ...
        ['Click LUT test: %d measured point(s) fell below the %g dB SNR floor and ' ...
         'were excluded from the verdict.'], nUnreliable, options.MinSnrDb);
end

nClipped = nnz(clipAny & tested);
if nClipped > 0
    stimgen.util.vprintf(0, 1, ...
        ['Click LUT test: %d point(s) clipped. Their level error is real but is the ' ...
         'rig running out of range, not a bad lookup table.'], nClipped);
end
end

% ------------------------------------------------------------------------ %
function d = default_test_durs_(lutDur, maxPoints)
% Geometric midpoints between successive LUT durations, thinned to at most
% maxPoints. These are the durations the calibration never measured, so they
% are where the LUT's interpolation is the only thing setting the level.
lutDur = unique(lutDur(lutDur > 0));
if numel(lutDur) < 2
    d = lutDur;
    return
end

d = sqrt(lutDur(1:end-1) .* lutDur(2:end));
if numel(d) > maxPoints
    d = d(unique(round(linspace(1, numel(d), maxPoints))));
end
end

% ------------------------------------------------------------------------ %
function [skipped, nOver] = skipped_points_(durs, levels, drive, playable, maxV)
% Record every point that will not be played, and why. Reported rather than
% dropped: a level the rig cannot reach is a finding about the rig, and a test
% that silently narrowed its own grid would read as full coverage.
[di, li] = find(~playable);
nOver = numel(di);

reason = repmat("", nOver, 1);
for k = 1:nOver
    v = drive(di(k), li(k));
    if ~isfinite(v) || v <= 0
        reason(k) = "lookup returned no usable voltage";
    else
        reason(k) = sprintf("needs %.2f V, above the %g V output ceiling", v, maxV);
    end
end

skipped = struct( ...
    'duration',      durs(di(:)).', ...
    'level_db',      levels(li(:)).', ...
    'drive_voltage', drive(sub2ind(size(drive), di(:), li(:))), ...
    'reason',        reason);
end

% ------------------------------------------------------------------------ %
function w = worst_point_(durs, levels, error_db, reliable)
% The single reliable point furthest from its requested level -- the one
% number that answers "how wrong can this LUT be".
w = struct('duration', nan, 'level_db', nan, 'error_db', nan);
if ~any(reliable(:))
    return
end

e = error_db;
e(~reliable) = nan;
[~, k] = max(abs(e(:)));
[di, li] = ind2sub(size(e), k);

w.duration = durs(di);
w.level_db = levels(li);
w.error_db = error_db(di, li);
end

% ------------------------------------------------------------------------ %
function m = max_or_nan_(v)
% max() already skips NaN, but returns empty for an empty set; a statistics
% field has to stay a scalar so a caller can format it without checking first.
m = max(v);
if isempty(m)
    m = nan;
end
end
