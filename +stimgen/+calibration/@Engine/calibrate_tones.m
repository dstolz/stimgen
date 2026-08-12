function calibrate_tones(obj, freqs, repeatCount, options)
% calibrate_tones(obj)
% calibrate_tones(obj, freqs)
% calibrate_tones(obj, freqs, repeatCount)
% calibrate_tones(obj, freqs, repeatCount, Name=Value)
%
% Sweep across frequencies and build the tone calibration LUT.
% Aborts and clears any prior tone data on error.
%
% The sweep is pregenerated as one train of gated tone bursts separated by
% silence and played with a single play_and_record per repeat, instead of one
% hardware transaction per frequency. Each burst is then recovered from the
% recording at its known position -- offset by the rig's conduction delay,
% measured once at the start of the run with a click probe (see
% measure_conduction_delay) -- and measured spectrally over its steady-state
% middle with the same flat-top periodogram estimate the per-frequency
% version used, so the LUT stays on its original scale. If the click probe
% cannot be trusted (no response above the noise), the delay falls back to a
% per-train cross-correlation.
%
% Because the bursts are separated in time rather than in frequency, the
% analysis holds for any frequency list: adjacent points may sit closer
% together than their spectral lobes are wide.
%
% Long sweeps are split into consecutive trains no longer than
% MaxSequenceDuration. The excitation has to fit the hardware output buffer,
% which for an RPvds circuit is a fixed allocation sized in the .rcx.
%
% Parameters:
%   freqs       - (1,:) double frequency vector in Hz (default: 50-point
%                 log sweep from 100 Hz to Nyquist)
%   repeatCount - (1,1) double positive integer number of times each train
%                 is played; per-frequency measurements are averaged
%   BurstDuration       - (1,1) double burst length in seconds (default 0.1)
%   GapDuration         - (1,1) double silence between bursts in seconds
%                         (default 0.05). Doubles as the bound on the delay
%                         search, so raise it for a device whose round-trip
%                         latency exceeds it.
%   MaxSequenceDuration - (1,1) double longest single train in seconds
%                         (default 2)
arguments
    obj
    freqs (1,:) double = []
    repeatCount (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 1
    options.BurstDuration (1,1) double {mustBePositive,mustBeFinite} = 0.1
    options.GapDuration (1,1) double {mustBePositive,mustBeFinite} = 0.05
    options.MaxSequenceDuration (1,1) double {mustBePositive,mustBeFinite} = 2
end
obj.assert_adapter_();
obj.reset_cancel_();
fs = obj.Fs;

if isempty(freqs)
    freqs = 100 .* 2.^(linspace(0, 9, 50));
    freqs(freqs > fs * 0.5) = [];
end

burstDur = options.BurstDuration;
gapDur   = options.GapDuration;

% Smallest possible train is the leading gap plus one burst and its own gap.
strideDur = burstDur + gapDur;
if gapDur + strideDur > options.MaxSequenceDuration
    error('stimgen:calibration:Engine:sequenceTooLong', ...
        ['MaxSequenceDuration (%g s) cannot hold one %g s burst with its %g s ' ...
         'gaps. Raise MaxSequenceDuration or shorten BurstDuration.'], ...
        options.MaxSequenceDuration, burstDur, gapDur);
end
burstsPerTrain = floor((options.MaxSequenceDuration - gapDur) / strideDur);

n         = numel(freqs);
tone_data = obj.empty_table_(n);
% Every abscissa up front, levels still NaN: that is what lets the monitor
% draw the points still to come alongside the ones already measured.
tone_data.x = freqs(:).';
toneMeasAll = nan(repeatCount, n);
toneSnrAll = nan(repeatCount, n);
toneNoiseFloorAll = nan(repeatCount, n);
toneThdAll = nan(repeatCount, n);
toneH2All = nan(repeatCount, n);
toneH3All = nan(repeatCount, n);
toneHeadroomAll = repmat(struct( ...
    'assumedFullScaleV', nan, ...
    'excitationPeakV', nan, ...
    'excitationHeadroomDb', nan, ...
    'excitationClippingLikely', false, ...
    'responsePeakV', nan, ...
    'responseHeadroomDb', nan, ...
    'responseFlatTopFraction', nan, ...
    'responseClippingLikely', false), repeatCount, n);

maxLag = max(round(gapDur * fs), 1);

% Axis metadata for the live table; identical on every update of this run.
axisMeta = {'XLabel', "frequency (Hz)", 'XScale', "log", 'XFactor', 1};

obj.begin_run_();
obj.emit_live_("tone", "start", 'Table', tone_data, 'Total', n, ...
    'RepeatTotal', repeatCount, axisMeta{:});

try
    % One click-probe latency measurement for the whole run: the delay is a
    % property of the rig -- speaker-to-mic distance plus converter latency
    % -- so it is measured once here rather than re-estimated from every
    % train, where a tonal record gives the cross-correlation a
    % quasi-periodic ridge to wander along and the analysis window lands
    % early by exactly the unaccounted delay. GapDuration bounds the search
    % because it is the largest delay the segmentation can absorb.
    delayInfo = obj.measure_conduction_delay(MaxDelay=gapDur);
    if ~delayInfo.valid
        stimgen.util.vprintf(0, 1, ...
            ['Falling back to per-train cross-correlation for burst ' ...
             'segmentation; analysis windows may include pre-response samples.']);
    end

    trainStarts = 1:burstsPerTrain:n;
    for b = 1:numel(trainStarts)
        obj.throw_if_cancelled_();
        idx = trainStarts(b) : min(trainStarts(b) + burstsPerTrain - 1, n);

        [seq, schedule] = obj.build_tone_sequence_(freqs(idx), burstDur, gapDur);
        x = obj.ExcitationVoltage .* seq;
        obj.ExcitationSignal = x;

        stimgen.util.vprintf(1, '[%d/%d] Tone train: %d bursts, %.3f-%.3f kHz, %.2f s', ...
            b, numel(trainStarts), numel(idx), ...
            freqs(idx(1))/1000, freqs(idx(end))/1000, numel(x)/fs);

        for rep = 1:repeatCount
            obj.throw_if_cancelled_();
            response = obj.Adapter.play_and_record(x);
            response = obj.demean_response_(response(:).');
            obj.ResponseSignal = response;

            if delayInfo.valid
                lag = delayInfo.delay_samples;
            else
                [lag, atBound] = obj.align_response_(x, response, maxLag);
                if atBound
                    stimgen.util.vprintf(0, 1, ...
                        ['Response delay reached the %.1f ms search bound; burst ' ...
                         'segmentation may be off. Increase GapDuration.'], gapDur * 1e3);
                end
                stimgen.util.vprintf(2, 'Train %d rep %d: acquisition delay %.2f ms', ...
                    b, rep, lag / fs * 1e3);
            end

            for k = 1:numel(idx)
                obj.throw_if_cancelled_();
                i = idx(k);
                s = schedule(k);

                [exBurst, rsBurst, rsSteady, steadySpan] = ...
                    obj.extract_burst_(x, response, s, lag);

                toneMeasAll(rep, i) = stimgen.calibration.Engine.spectral_rms( ...
                    rsSteady, freqs(i), fs);
                [toneNoiseFloorAll(rep, i), toneSnrAll(rep, i)] = ...
                    obj.estimate_noise_snr_(rsSteady, fs, freqs(i));
                [toneThdAll(rep, i), toneH2All(rep, i), toneH3All(rep, i)] = ...
                    obj.estimate_harmonics_(rsSteady, fs, freqs(i));
                toneHeadroomAll(rep, i) = obj.estimate_headroom_(exBurst, rsBurst);

                % One update per burst, carrying the span it was measured
                % over. A whole train is a single record, so without the span
                % the waveform panel could not show which burst a level came
                % from -- and mis-segmentation is the failure this sweep is
                % most prone to.
                if obj.ShowLivePlots
                    mAvg = mean(toneMeasAll(1:rep, i), 'omitnan');
                    [splRep, voltRep] = obj.compute_spl_voltage_(mAvg, "specfreq");
                    tone_data.measurement(i) = mAvg;
                    tone_data.spl_db(i)      = splRep;
                    tone_data.voltage(i)     = voltRep;
                    tone_data.sd_db          = obj.level_sd_db_(toneMeasAll);

                    % Trains are measured train-major, not point-major, so the
                    % payload has to state its own progress rather than let it
                    % be inferred from the point index.
                    done = (b - 1) * repeatCount + (rep - 1) + k / numel(idx);
                    obj.emit_live_("tone", "measure", 'Table', tone_data, ...
                        'Span', steadySpan, ...
                        'Markers', freqs(i) .* [1 2 3], ...
                        'MarkerLabels', ["f0" "2f0" "3f0"], ...
                        'Index', i, 'Total', n, ...
                        'Repeat', rep, 'RepeatTotal', repeatCount, ...
                        'Progress', done / (numel(trainStarts) * repeatCount), ...
                        axisMeta{:}, ...
                        'Metrics', struct('spl_db', splRep, 'voltage', voltRep, ...
                                          'snr_db', toneSnrAll(rep, i), ...
                                          'thd_db', toneThdAll(rep, i), ...
                                          'h2_db', toneH2All(rep, i), ...
                                          'h3_db', toneH3All(rep, i)));
                end
            end
        end
    end

    for i = 1:n
        m = mean(toneMeasAll(:, i), 'omitnan');
        [spl, volt] = obj.compute_spl_voltage_(m, "specfreq");
        tone_data.measurement(i) = m;
        tone_data.spl_db(i)      = spl;
        tone_data.voltage(i)     = volt;
    end
catch ME
    % Abort: do not persist partial data.
    if isstruct(obj.CalibrationData)
        obj.CalibrationData = stimgen.calibration.Engine.rmfield_safe_(obj.CalibrationData, 'tone');
    end
    stimgen.util.vprintf(0, 2, 'Tone calibration aborted: %s', ME.message);
    rethrow(ME);
end

% Commit only on full success.
% NaN records that the windows were cut by per-train correlation instead.
if delayInfo.valid
    conductionDelayS = delayInfo.delay_s;
else
    conductionDelayS = nan;
end
cd_out = obj.commit_cal_data_();
toneSensitivity = tone_data.spl_db(:) - 20*log10(max(obj.ExcitationVoltage, eps));
toneRepeatability = obj.repeatability_stats_(toneMeasAll);
toneHeadroom = obj.aggregate_headroom_(toneHeadroomAll(:));
toneNoiseFloor = mean(toneNoiseFloorAll, 1, 'omitnan');
toneSnr = mean(toneSnrAll, 1, 'omitnan');
toneThd = mean(toneThdAll, 1, 'omitnan');
toneH2 = mean(toneH2All, 1, 'omitnan');
toneH3 = mean(toneH3All, 1, 'omitnan');

% One train mixes every frequency, so a whole-record thd() is meaningless
% here; summarize the per-burst figures instead.
obj.ResponseTHD = median(toneThd, 'omitnan');

cd_out.tone = struct( ...
    'frequency',   freqs(:), ...
    'measurement', tone_data.measurement(:), ...
    'spl_db',      tone_data.spl_db(:), ...
    'voltage',     tone_data.voltage(:), ...
    'burst_duration', burstDur, ...
    'gap_duration',   gapDur, ...
    'conduction_delay_s', conductionDelayS, ...
    'metrics', struct( ...
        'frequency_response_hz', freqs(:), ...
        'frequency_response_db_spl', tone_data.spl_db(:), ...
        'calibrated_level_sensitivity_db_per_v', toneSensitivity, ...
        'noise_floor_db', toneNoiseFloor(:), ...
        'snr_db', toneSnr(:), ...
        'thd_db', toneThd(:), ...
        'h2_db', toneH2(:), ...
        'h3_db', toneH3(:), ...
        'repeatability', toneRepeatability, ...
        'clipping_headroom', toneHeadroom));
obj.CalibrationData = cd_out;
obj.CalibrationTimestamp = datetime('now');

tone_data.sd_db = obj.level_sd_db_(toneMeasAll);
obj.emit_live_("tone", "done", 'Table', tone_data, ...
    'Index', n, 'Total', n, 'Repeat', repeatCount, 'RepeatTotal', repeatCount, ...
    'Progress', 1, axisMeta{:});

stimgen.util.vprintf(1, 'Tone calibration complete. %d points over %g-%g Hz in %d train(s) x %d repeat(s)', ...
    n, freqs(1), freqs(end), numel(trainStarts), repeatCount);
end
