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
% recording at its known position -- offset by the bulk acquisition delay,
% measured once per train by cross-correlation -- and measured spectrally
% over its steady-state middle with the same flat-top periodogram estimate
% the per-frequency version used, so the LUT stays on its original scale.
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

if obj.ShowLivePlots
    obj.plot_reset();
end

try
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
            response = response(:).';
            obj.ResponseSignal = response;

            [lag, atBound] = obj.align_response_(x, response, maxLag);
            if atBound
                stimgen.util.vprintf(0, 1, ...
                    ['Response delay reached the %.1f ms search bound; burst ' ...
                     'segmentation may be off. Increase GapDuration.'], gapDur * 1e3);
            end
            stimgen.util.vprintf(2, 'Train %d rep %d: acquisition delay %.2f ms', ...
                b, rep, lag / fs * 1e3);

            for k = 1:numel(idx)
                obj.throw_if_cancelled_();
                i = idx(k);
                s = schedule(k);

                [exBurst, rsBurst] = slice_(x, response, s.onset, 0, s.nsamples, lag);
                [aRel, bRel] = steady_span_(s, fs);
                [~, rsSteady] = slice_(x, response, s.onset, aRel, bRel, lag);

                toneMeasAll(rep, i) = stimgen.calibration.Engine.spectral_rms( ...
                    rsSteady, freqs(i), fs);
                [toneNoiseFloorAll(rep, i), toneSnrAll(rep, i)] = ...
                    obj.estimate_noise_snr_(rsSteady, fs, freqs(i));
                [toneThdAll(rep, i), toneH2All(rep, i), toneH3All(rep, i)] = ...
                    obj.estimate_harmonics_(rsSteady, fs, freqs(i));
                toneHeadroomAll(rep, i) = obj.estimate_headroom_(exBurst, rsBurst);
            end

            if obj.ShowLivePlots
                for k = 1:numel(idx)
                    i = idx(k);
                    m = mean(toneMeasAll(1:rep, i), 'omitnan');
                    [spl, volt] = obj.compute_spl_voltage_(m, "specfreq");
                    tone_data.x(i)           = freqs(i);
                    tone_data.measurement(i) = m;
                    tone_data.spl_db(i)      = spl;
                    tone_data.voltage(i)     = volt;
                end
                obj.plot_signal();
                obj.plot_spectrum();
                obj.plot_transfer('tone', tone_data);
            end
        end
    end

    for i = 1:n
        m = mean(toneMeasAll(:, i), 'omitnan');
        [spl, volt] = obj.compute_spl_voltage_(m, "specfreq");
        tone_data.x(i)           = freqs(i);
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

stimgen.util.vprintf(1, 'Tone calibration complete. %d points over %g-%g Hz in %d train(s) x %d repeat(s)', ...
    n, freqs(1), freqs(end), numel(trainStarts), repeatCount);
end

% ------------------------------------------------------------------------ %
function [aRel, bRel] = steady_span_(s, fs)
% Half-open [aRel, bRel) sample offsets of the burst's steady-state middle,
% relative to its onset. Falls back to the whole burst when the ramps leave
% too little to estimate a level from.
aRel = s.rampSamples;
bRel = s.nsamples - s.rampSamples;

minLen = max(32, ceil(4 * fs / s.frequency));
if bRel - aRel < minLen
    aRel = 0;
    bRel = s.nsamples;
end
end

% ------------------------------------------------------------------------ %
function [exSeg, rsSeg] = slice_(x, response, onset, aRel, bRel, lag)
% Cut the same half-open span out of the excitation and, shifted by the
% acquisition delay, out of the response. Both are clamped to their records:
% the trailing gap normally covers the shift, but a mis-estimated delay or a
% short return from the adapter must not index past the end.
a = onset + aRel;
b = onset + bRel - 1;

exSeg = x(max(a,1) : min(b, numel(x)));
rsSeg = response(max(a + lag, 1) : min(b + lag, numel(response)));
end
