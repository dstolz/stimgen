function results = test_tones(obj, freqs, levels, options)
% results = test_tones(obj)
% results = test_tones(obj, freqs)
% results = test_tones(obj, freqs, levels)
% results = test_tones(obj, freqs, levels, Name=Value)
% Verify the tone lookup table by playing discrete tones at requested levels
% and measuring what actually came out.
%
% For every frequency/level pair the drive voltage is taken from
% compute_adjusted_voltage -- the same call apply_calibration makes when it
% scales a stimgen.Tone -- so this measures the level normalization a real
% experiment gets, not a reimplementation of it. A gated burst is played at
% that voltage, its steady-state middle is measured spectrally, and the level
% that comes back is compared to the level that was asked for. A working LUT
% leaves that error near zero at every point and every level.
%
% By default the test frequencies are the geometric midpoints between
% successive LUT points: the frequencies the calibration never measured, where
% makima interpolation is doing all the work. Reusing the LUT's own
% frequencies would interrogate the interpolant's knots, which reproduce the
% measurement by construction, and say nothing about what happens between
% them. Testing several levels also exercises the other half of the model --
% that level scales as 20*log10 of drive voltage away from NormativeValue --
% which a single-level test cannot see at all.
%
% Which table is tested follows ToneLutSource, so with "Tone Lookup From
% Swept Sine" set this verifies the swept sine table.
%
% Bursts are played as trains, the same way calibrate_tones plays them, and
% segmented by the same extract_burst_ -- a difference in segmentation would
% surface as a level error the LUT never had.
%
% Requires an adapter and a tone (or swept sine) calibration. Nothing in the
% LUTs is modified; results are returned and also stored in
% CalibrationData.toneTest, so a saved .esgc records that its tone table was
% verified and how accurate it proved.
%
% Points whose required drive exceeds MaxOutputVoltage are skipped rather than
% played: they would clip, and clipping measures the amplifier, not the LUT.
% They are reported in results.skipped and logged, never dropped silently.
%
% While the test runs, LiveUpdate events are broadcast with stage "tone_test"
% (gated by ShowLivePlots), so an attached LiveMonitor shows the measured
% level fill in against the requested one, one level at a time.
%
% Parameters:
%   freqs  - (1,:) double test frequencies in Hz (default: geometric
%            midpoints of the LUT frequencies, at most 15 of them)
%   levels - (1,:) double requested levels in dB SPL (default:
%            NormativeValue - [20 10 0])
%
% Name-Value Parameters:
%   RepeatCount         - passes over each train; per-point levels are
%                         averaged (default: 2)
%   BurstDuration       - burst length in seconds (default: 0.1)
%   GapDuration         - silence between bursts in seconds (default: 0.05).
%                         Doubles as the bound on the delay search.
%   MaxSequenceDuration - longest single train in seconds (default: 2)
%   ToleranceDb         - absolute level error at or below which the test is
%                         reported passed (default: 3)
%   MinSnrDb            - SNR below which a point is treated as unreliable and
%                         excluded from the verdict (default: 10)
%
% Returns:
%   results - struct. Matrices are frequency-by-level:
%     frequency, level_db   - the grid that was tested
%     lut_source            - "tone" | "swept_sine", the table under test
%     drive_voltage         - volts the LUT asked for at each point
%     measured_spl_db       - level that came back
%     error_db              - measured minus requested
%     sd_db                 - across-repeat spread of the measured level
%     snr_db, thd_db        - measurement quality per point
%     clipping              - response clipped at this point
%     extrapolated          - (F,1) frequency outside the LUT's span
%     tested                - point was played and measured
%     reliable              - tested, in SNR, and unclipped: the verdict set
%     max_abs_error_db, rms_error_db, bias_db - over the reliable set
%     level_bias_db         - (1,L) mean error at each requested level
%     level_max_abs_error_db- (1,L) worst error at each requested level
%     freq_max_abs_error_db - (F,1) worst error at each frequency
%     worst                 - struct: frequency, level_db, error_db of the
%                             single worst reliable point
%     skipped               - struct of frequency, level_db, drive_voltage,
%                             reason for every point not played
%     tolerance_db, min_snr_db - the criteria applied
%     repeat_count, burst_duration, gap_duration - test conditions
%     passed                - true when every reliable point is within
%                             ToleranceDb and at least one point was reliable
%     testedOn              - datetime of the run
%
% Example:
%   eng.calibrate_tones();
%   r = eng.test_tones();
%   fprintf('worst LUT error %.2f dB at %.0f Hz / %g dB SPL\n', ...
%       r.worst.error_db, r.worst.frequency, r.worst.level_db);
%
% See also: stimgen.calibration.Engine/calibrate_tones,
%           stimgen.calibration.Engine/compute_adjusted_voltage,
%           stimgen.calibration.Engine/test_filter
arguments
    obj
    freqs  (1,:) double {mustBePositive, mustBeFinite} = []
    levels (1,:) double {mustBeFinite} = []
    options.RepeatCount         (1,1) double {mustBeInteger, mustBePositive, mustBeFinite} = 2
    options.BurstDuration       (1,1) double {mustBePositive, mustBeFinite} = 0.1
    options.GapDuration         (1,1) double {mustBePositive, mustBeFinite} = 0.05
    options.MaxSequenceDuration (1,1) double {mustBePositive, mustBeFinite} = 2
    options.ToleranceDb         (1,1) double {mustBePositive, mustBeFinite} = 3
    options.MinSnrDb            (1,1) double {mustBeFinite} = 10
end

% At most this many default test points, so a 50-point LUT does not turn into
% a 49-point-by-3-level run nobody asked for.
MAX_DEFAULT_POINTS = 15;

obj.assert_adapter_();
obj.reset_cancel_();

fs = obj.Fs;
if ~isfinite(fs) || fs <= 0
    error('stimgen:calibration:Engine:noSampleRate', ...
        'The tone LUT test needs a sample rate, which comes from the hardware adapter.');
end

[lutSource, lut] = obj.resolve_tone_lut_();
if isempty(lut)
    error('stimgen:calibration:Engine:missingTypeCalibration', ...
        ['Calibration data for type "%s" is not available. Run a tone (or swept ' ...
         'sine) calibration before testing the tone lookup table.'], lutSource);
end
lutFreq = double(lut.frequency(:)).';

if isempty(freqs)
    freqs = default_test_freqs_(lutFreq, MAX_DEFAULT_POINTS);
end
if isempty(levels)
    levels = obj.NormativeValue - [20 10 0];
end
freqs  = unique(freqs);    % also sorts, so the transfer curve is drawn in order
levels = unique(levels);

% A burst above Nyquist is not a tone, so there is nothing to measure there.
tooHigh = freqs >= fs / 2;
if any(tooHigh)
    stimgen.util.vprintf(0, 1, ...
        'Tone LUT test: dropping %d test frequency(ies) at or above Nyquist (%g Hz).', ...
        nnz(tooHigh), fs / 2);
    freqs(tooHigh) = [];
end
if isempty(freqs)
    error('stimgen:calibration:Engine:noTestFrequencies', ...
        'No test frequency survives the %g Hz sample rate.', fs);
end

% Outside the LUT's span makima extrapolates, which is a property of the
% interpolant rather than of the calibration. Such points are still played and
% still count -- an extrapolated level really is what a stimulus there would
% get -- but they are flagged so a failure is not mistaken for a bad LUT.
extrapolated = freqs(:) < min(lutFreq) | freqs(:) > max(lutFreq);
if any(extrapolated)
    stimgen.util.vprintf(0, 1, ...
        ['Tone LUT test: %d test frequency(ies) lie outside the %g-%g Hz LUT span ' ...
         'and are extrapolated.'], nnz(extrapolated), min(lutFreq), max(lutFreq));
end

nF = numel(freqs);
nL = numel(levels);

% --- Drive voltages, through the same call apply_calibration makes ---------
drive = nan(nF, nL);
for li = 1:nL
    drive(:, li) = reshape(obj.compute_adjusted_voltage("tone", freqs, levels(li)), [], 1);
end

playable = isfinite(drive) & drive > 0 & drive <= obj.MaxOutputVoltage;
[skipped, nOver] = skipped_points_(freqs, levels, drive, playable, obj.MaxOutputVoltage);
if nOver > 0
    stimgen.util.vprintf(0, 1, ...
        ['Tone LUT test: skipping %d of %d point(s) needing more than the %g V ' ...
         'output ceiling; they would clip. See results.skipped.'], ...
        nOver, nF * nL, obj.MaxOutputVoltage);
end
if ~any(playable(:))
    error('stimgen:calibration:Engine:noPlayablePoints', ...
        ['Every requested frequency/level pair needs more than the %g V output ' ...
         'ceiling. Test lower levels, or raise MaxOutputVoltage if the rig allows it.'], ...
        obj.MaxOutputVoltage);
end

% --- Train layout, identical to calibrate_tones ----------------------------
burstDur = options.BurstDuration;
gapDur   = options.GapDuration;
nReps    = options.RepeatCount;

strideDur = burstDur + gapDur;
if gapDur + strideDur > options.MaxSequenceDuration
    error('stimgen:calibration:Engine:sequenceTooLong', ...
        ['MaxSequenceDuration (%g s) cannot hold one %g s burst with its %g s ' ...
         'gaps. Raise MaxSequenceDuration or shorten BurstDuration.'], ...
        options.MaxSequenceDuration, burstDur, gapDur);
end
burstsPerTrain = floor((options.MaxSequenceDuration - gapDur) / strideDur);

% Every level's trains are laid out up front so progress can be reported
% against the whole run: levels differ in how many points are playable, so the
% total is not levels times trains.
trains = cell(1, nL);
for li = 1:nL
    p = find(playable(:, li)).';
    starts = 1:burstsPerTrain:numel(p);
    trains{li} = arrayfun(@(s) p(s : min(s + burstsPerTrain - 1, numel(p))), ...
        starts, UniformOutput=false);
end
totalCaptures = sum(cellfun(@numel, trains)) * nReps;

maxLag = max(round(gapDur * fs), 1);

measSplAll = nan(nReps, nF, nL);   % dB SPL per repeat
snrAll     = nan(nReps, nF, nL);
thdAll     = nan(nReps, nF, nL);
clipAny    = false(nF, nL);

axisMeta = {'XLabel', "frequency (Hz)", 'XScale', "log", 'XFactor', 1};
captureNum = 0;

tbl = obj.empty_table_(nF);
tbl.x = freqs(:).';

obj.begin_run_();
obj.emit_live_("tone_test", "start", 'Table', tbl, 'Total', nF, ...
    'RepeatTotal', nReps, 'Progress', 0, axisMeta{:});

try
    for li = 1:nL
        levelDb = levels(li);

        % One table per level: the curve on screen is the measured level
        % against the one level that was requested, so mixing levels into it
        % would draw a staircase and hide the error the run exists to show.
        tbl = obj.empty_table_(nF);
        tbl.x = freqs(:).';

        stimgen.util.vprintf(1, 'Tone LUT test: level %d/%d, %g dB SPL, %d point(s)', ...
            li, nL, levelDb, nnz(playable(:, li)));

        for b = 1:numel(trains{li})
            obj.throw_if_cancelled_();
            idx = trains{li}{b};

            [seq, schedule] = obj.build_tone_sequence_(freqs(idx), burstDur, gapDur);

            % Each burst carries its own LUT voltage, which is the whole point
            % of the test: calibrate_tones scales the entire train by one
            % excitation voltage, but here the per-point drive IS the quantity
            % under test.
            x = seq;
            for k = 1:numel(idx)
                s = schedule(k);
                span = s.onset : s.onset + s.nsamples - 1;
                x(span) = drive(idx(k), li) .* x(span);
            end
            obj.ExcitationSignal = x;

            for rep = 1:nReps
                obj.throw_if_cancelled_();
                stimgen.util.vprintf(2, '[%d/%d] Tone test train: %d bursts, %.3f-%.3f kHz at %g dB SPL', ...
                    rep, nReps, numel(idx), ...
                    freqs(idx(1))/1000, freqs(idx(end))/1000, levelDb);

                response = obj.Adapter.play_and_record(x);
                response = response(:).';
                obj.ResponseSignal = response;

                [lag, atBound] = obj.align_response_(x, response, maxLag);
                if atBound
                    stimgen.util.vprintf(0, 1, ...
                        ['Response delay reached the %.1f ms search bound; burst ' ...
                         'segmentation may be off. Increase GapDuration.'], gapDur * 1e3);
                end

                for k = 1:numel(idx)
                    obj.throw_if_cancelled_();
                    i = idx(k);

                    [exBurst, rsBurst, rsSteady, steadySpan] = ...
                        obj.extract_burst_(x, response, schedule(k), lag);

                    m = stimgen.calibration.Engine.spectral_rms(rsSteady, freqs(i), fs);
                    measSplAll(rep, i, li) = obj.compute_spl_voltage_(m, "specfreq");
                    [~, snrAll(rep, i, li)] = obj.estimate_noise_snr_(rsSteady, fs, freqs(i));
                    thdAll(rep, i, li) = obj.estimate_harmonics_(rsSteady, fs, freqs(i));

                    h = obj.estimate_headroom_(exBurst, rsBurst);
                    clipAny(i, li) = clipAny(i, li) || ...
                        h.responseClippingLikely || h.excitationClippingLikely;

                    captureNum = captureNum + 1;
                    if obj.ShowLivePlots
                        tbl.measurement(i) = m;
                        tbl.spl_db(i)      = mean(measSplAll(1:rep, i, li), 'omitnan');
                        tbl.voltage(i)     = drive(i, li);
                        tbl.sd_db          = obj.level_sd_db_(...
                            10 .^ (measSplAll(:, :, li) ./ 20));
                        obj.emit_live_("tone_test", "measure", 'Table', tbl, ...
                            'Span', steadySpan, ...
                            'Markers', freqs(i) .* [1 2 3], ...
                            'MarkerLabels', ["f0" "2f0" "3f0"], ...
                            'Index', i, 'Total', nF, ...
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
    end
catch ME
    stimgen.util.vprintf(0, 2, 'Tone LUT test aborted: %s', ME.message);
    rethrow(ME);
end

% --- Accuracy statistics ---------------------------------------------------
measuredSpl = reshape(mean(measSplAll, 1, 'omitnan'), nF, nL);
snr         = reshape(mean(snrAll,     1, 'omitnan'), nF, nL);
thd         = reshape(mean(thdAll,     1, 'omitnan'), nF, nL);

sd = nan(nF, nL);
for li = 1:nL
    % level_sd_db_ works on linear measurements, so the dB levels go back
    % through 10^(x/20) to be turned into a spread the same way every other
    % run reports one.
    sd(:, li) = obj.level_sd_db_(10 .^ (measSplAll(:, :, li) ./ 20)).';
end

tested   = playable & isfinite(measuredSpl);
error_db = measuredSpl - repmat(levels(:).', nF, 1);

% Only the SNR floor disqualifies a point. A noise-dominated measurement reads
% high and would fail the test for something the LUT did not do, so it has to
% be excluded. Clipping is the opposite case: it reads low, and that error is
% real -- a level the rig cannot deliver cleanly is a level the LUT does not
% deliver. Such points stay in the verdict and results.clipping says why they
% missed.
reliable = tested & isfinite(snr) & snr >= options.MinSnrDb;

results = struct;
results.frequency       = freqs(:);
results.level_db        = levels(:).';
results.lut_source      = lutSource;
results.drive_voltage   = drive;
results.measured_spl_db = measuredSpl;
results.error_db        = error_db;
results.sd_db           = sd;
results.snr_db          = snr;
results.thd_db          = thd;
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

results.freq_max_abs_error_db = nan(nF, 1);
for fi = 1:nF
    results.freq_max_abs_error_db(fi) = max_or_nan_(abs(error_db(fi, reliable(fi, :))));
end

results.worst = worst_point_(freqs, levels, error_db, reliable);

results.skipped        = skipped;
results.tolerance_db   = options.ToleranceDb;
results.min_snr_db     = options.MinSnrDb;
results.repeat_count   = nReps;
results.burst_duration = burstDur;
results.gap_duration   = gapDur;
results.passed         = any(reliable(:)) && ...
    results.max_abs_error_db <= options.ToleranceDb;
results.testedOn       = datetime('now');

obj.CalibrationData.toneTest = results;

obj.emit_live_("tone_test", "done", 'Table', tbl, ...
    'Index', 0, 'Total', nF, 'Repeat', nReps, 'RepeatTotal', nReps, ...
    'Progress', 1, axisMeta{:});

if results.passed
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
stimgen.util.vprintf(1, ...
    ['Tone LUT test %s against the "%s" table: worst error %.2f dB (tolerance %.1f dB), ' ...
     'bias %+.2f dB, rms %.2f dB over %d of %d point(s)'], ...
    verdict, lutSource, results.max_abs_error_db, options.ToleranceDb, ...
    results.bias_db, results.rms_error_db, nnz(reliable), nF * nL);

nUnreliable = nnz(tested & ~reliable);
if nUnreliable > 0
    stimgen.util.vprintf(0, 1, ...
        ['Tone LUT test: %d measured point(s) fell below the %g dB SNR floor and ' ...
         'were excluded from the verdict.'], nUnreliable, options.MinSnrDb);
end

nClipped = nnz(clipAny & tested);
if nClipped > 0
    stimgen.util.vprintf(0, 1, ...
        ['Tone LUT test: %d point(s) clipped. Their level error is real but is the ' ...
         'rig running out of range, not a bad lookup table.'], nClipped);
end
end

% ------------------------------------------------------------------------ %
function f = default_test_freqs_(lutFreq, maxPoints)
% Geometric midpoints between successive LUT frequencies, thinned to at most
% maxPoints. These are the frequencies the calibration never measured, so they
% are where the LUT's interpolation is the only thing setting the level.
lutFreq = unique(lutFreq(lutFreq > 0));
if numel(lutFreq) < 2
    f = lutFreq;
    return
end

f = sqrt(lutFreq(1:end-1) .* lutFreq(2:end));
if numel(f) > maxPoints
    f = f(unique(round(linspace(1, numel(f), maxPoints))));
end
end

% ------------------------------------------------------------------------ %
function [skipped, nOver] = skipped_points_(freqs, levels, drive, playable, maxV)
% Record every point that will not be played, and why. Reported rather than
% dropped: a level the rig cannot reach is a finding about the rig, and a test
% that silently narrowed its own grid would read as full coverage.
[fi, li] = find(~playable);
nOver = numel(fi);

reason = repmat("", nOver, 1);
for k = 1:nOver
    v = drive(fi(k), li(k));
    if ~isfinite(v) || v <= 0
        reason(k) = "lookup returned no usable voltage";
    else
        reason(k) = sprintf("needs %.2f V, above the %g V output ceiling", v, maxV);
    end
end

skipped = struct( ...
    'frequency',     freqs(fi(:)).', ...
    'level_db',      levels(li(:)).', ...
    'drive_voltage', drive(sub2ind(size(drive), fi(:), li(:))), ...
    'reason',        reason);
end

% ------------------------------------------------------------------------ %
function w = worst_point_(freqs, levels, error_db, reliable)
% The single reliable point furthest from its requested level -- the one
% number that answers "how wrong can this LUT be".
w = struct('frequency', nan, 'level_db', nan, 'error_db', nan);
if ~any(reliable(:))
    return
end

e = error_db;
e(~reliable) = nan;
[~, k] = max(abs(e(:)));
[fi, li] = ind2sub(size(e), k);

w.frequency = freqs(fi);
w.level_db  = levels(li);
w.error_db  = error_db(fi, li);
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
