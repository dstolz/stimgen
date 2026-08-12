function calibrate_swept_sine(obj, duration, freqs, repeatCount, tailDuration)
% calibrate_swept_sine(obj)
% calibrate_swept_sine(obj, duration)
% calibrate_swept_sine(obj, duration, freqs)
% calibrate_swept_sine(obj, duration, freqs, repeatCount)
% calibrate_swept_sine(obj, duration, freqs, repeatCount, tailDuration)
%
% Perform broadband calibration using a log-sine chirp sweep.
% The chirp exponentially increases frequency from ~100 Hz to
% Nyquist, covering the entire spectrum in one measurement. The
% excitation/response pair is deconvolved into a transfer function, which
% is sampled at discrete frequency points to yield a frequency-dependent
% SPL calibration on the same scale as calibrate_tones.
%
% The log-sine chirp has exceptional properties for measuring
% frequency response: naturally pink spectrum, low crest factor (~4 dB),
% and unique time-separation of harmonic distortion in the impulse
% response. See Chan (2010) "Swept Sine Chirps for Measuring Impulse
% Response" for theory and measurement validation.
%
% Parameters:
%   duration - (1,1) double chirp length in seconds (default: 1)
%   freqs    - (1,:) double frequency vector in Hz where calibration
%              is sampled (default: 50-point log sweep from 100 Hz to
%              min(0.95*Nyquist, 20000) Hz). Points above 0.95*Nyquist are
%              dropped; the sample rate cannot support them. The excitation
%              chirp sweeps a sixth of an octave past both ends of whatever
%              band survives, so every reported point sits inside the sweep
%              rather than on its roll-off -- see the SWEEP_MARGIN_OCT note
%              below.
%   repeatCount - (1,1) double positive integer number of
%                 chirp captures to average (default: 4)
%   tailDuration - (1,1) double seconds of silence appended to the chirp so
%                 the decay is still being recorded after the sweep ends
%                 (default: 0.5). Raise it if the decay is reported as
%                 truncated; it costs recording time, not sweep resolution.
arguments
    obj
    duration (1,1) double {mustBePositive,mustBeFinite} = 1
    freqs (1,:) double = []
    repeatCount (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 4
    tailDuration (1,1) double {mustBeNonnegative,mustBeFinite} = 0.5
end
% The excitation sweeps past both ends of the reported band. A chirp's spectrum
% does not stop at its stop frequency, it rolls off over a transition region
% (~sqrt(df/dt) wide) and takes the deconvolution's usable SNR down with it, so
% a point sampled *at* the stop frequency is read half off the cliff. Reporting
% strictly inside the sweep costs a few percent of sweep time and removes the
% band-edge lift entirely; sweep_transfer_rms_ guards the case where the sample
% rate leaves no room for the margin.
SWEEP_MARGIN_OCT = 1/6;

obj.assert_adapter_();
obj.reset_cancel_();
fs = obj.Fs;
nyquist = fs / 2;
maxUsable = nyquist * 0.95;

if isempty(freqs)
    % Default frequency points: log-distributed across a default reported band.
    lowFreq  = 100;
    highFreq = min(maxUsable, 20000);
    if lowFreq >= highFreq
        error('stimgen:calibration:Engine:sampleRateTooLow', ...
              'Sample rate %g Hz leaves no usable sweep band above %g Hz.', fs, lowFreq);
    end
    freqs = lowFreq .* 2.^(linspace(0, log2(highFreq/lowFreq), 50));
end

% Nothing above 0.95*Nyquist can be measured at this sample rate.
requested = numel(freqs);
freqs = unique(freqs(freqs > 0 & freqs <= maxUsable));
if isempty(freqs)
    error('stimgen:calibration:Engine:noValidFreqs', ...
          'No requested frequency falls at or below %g Hz, the usable limit at Fs=%g Hz.', ...
          maxUsable, fs);
end
if numel(freqs) < requested
    stimgen.util.vprintf(1, 'Dropped %d frequency point(s) above the usable limit of %g Hz at Fs=%g Hz.', ...
        requested - numel(freqs), maxUsable, fs);
end

% Sweep wider than we report, as far as the sample rate allows.
startFreq = max(min(freqs) * 2^(-SWEEP_MARGIN_OCT), eps);
stopFreq  = min(max(freqs) * 2^( SWEEP_MARGIN_OCT), maxUsable);
if startFreq >= stopFreq
    error('stimgen:calibration:Engine:sampleRateTooLow', ...
          'Requested frequency range leaves no usable sweep band below %g Hz at Fs=%g Hz.', maxUsable, fs);
end
if stopFreq <= max(freqs)
    stimgen.util.vprintf(1, ['Sample rate %g Hz leaves no headroom above %g Hz; the top calibration ' ...
        'point sits on the sweep''s roll-off and is the least reliable of the set.'], fs, max(freqs));
end

so = stimgen.SweptSine;
so.Fs = fs;
so.Duration = duration;
so.StartFrequency = startFreq;
so.StopFrequency = stopFreq;
so.ChirpType = "log-sine";
so.ApplyCalibration = false;   % the excitation must stay raw; scaling it by an
                               % existing LUT would fold that LUT into the result
so.update_signal();

% Record past the end of the chirp: play_and_record returns exactly as many
% samples as it is handed, so a bare sweep stops the recording at the instant
% the last (highest) frequency is emitted and its decay is never captured.
% The pad is silence in the excitation only -- sweep.duration below stays the
% chirp length, which is what sets the harmonic wrap geometry.
y = obj.ExcitationVoltage .* so.Signal;
y = [reshape(y, 1, []), zeros(1, round(tailDuration * fs))];
obj.ExcitationSignal = y;

n = numel(freqs);
swept_sine_data = obj.empty_table_(n);
% Every abscissa up front, levels still NaN: that is what lets the monitor
% draw the points still to come alongside the ones already measured.
swept_sine_data.x = freqs(:).';
measAll = nan(repeatCount, n);
responses = cell(repeatCount, 1);

% Axis metadata for the live table; identical on every update of this run.
axisMeta = {'XLabel', "frequency (Hz)", 'XScale', "log", 'XFactor', 1};

obj.begin_run_();
obj.emit_live_("swept_sine", "start", 'Table', swept_sine_data, 'Total', n, ...
    'RepeatTotal', repeatCount, axisMeta{:});

try
    stimgen.util.vprintf(1, 'Analyzing swept sine response at %d frequencies (%d averages)...', n, repeatCount);
    for rep = 1:repeatCount
        obj.throw_if_cancelled_();
        stimgen.util.vprintf(1, '[%d/%d] Capturing swept sine response', rep, repeatCount);
        raw = obj.Adapter.play_and_record(y);

        % trim_response_ only strips trailing padding; deconvolution needs
        % the intact onset, which holds the low-frequency start of the sweep.
        response = obj.demean_response_(obj.trim_response_(raw));
        responses{rep} = response;
        obj.ResponseSignal = response;

        measAll(rep, :) = obj.sweep_transfer_rms_(y, response, freqs, fs, [startFreq stopFreq]);

        % A sweep measures the whole band at once, so a pass fills every point
        % rather than advancing an index. Progress is stated per pass; the
        % point-major default would read it as one point of n.
        if obj.ShowLivePlots
            for i = 1:n
                mAvg = mean(measAll(1:rep, i), 'omitnan');
                [spl, volt] = obj.compute_spl_voltage_(mAvg, "specfreq");
                swept_sine_data.measurement(i) = mAvg;
                swept_sine_data.spl_db(i) = spl;
                swept_sine_data.voltage(i) = volt;
            end
            swept_sine_data.sd_db = obj.level_sd_db_(measAll);
            obj.emit_live_("swept_sine", "measure", 'Table', swept_sine_data, ...
                'Index', 0, 'Total', n, ...
                'Repeat', rep, 'RepeatTotal', repeatCount, ...
                'Progress', rep / repeatCount, axisMeta{:});
        end
    end

    minLen = min(cellfun(@numel, responses));
    stacked = zeros(repeatCount, minLen);
    for rep = 1:repeatCount
        stacked(rep, :) = responses{rep}(1:minLen);
    end
    obj.ResponseSignal = mean(stacked, 1);

    % Distortion comes from time-gating the harmonic impulses that precede the
    % linear impulse response; thd() assumes a stationary sinusoid and returns
    % a meaningless number for a chirp.
    sweepSpec = struct('duration', duration, 'start_freq', startFreq, 'stop_freq', stopFreq);
    analysis = obj.analyze_sweep_response_(y, obj.ResponseSignal, fs, sweepSpec);
    obj.ResponseTHD = analysis.harmonics.thd_db;

    for i = 1:n
        m = mean(measAll(:, i), 'omitnan');
        [spl, volt] = obj.compute_spl_voltage_(m, "specfreq");
        swept_sine_data.measurement(i) = m;
        swept_sine_data.spl_db(i)      = spl;
        swept_sine_data.voltage(i)     = volt;
    end
catch ME
    if isstruct(obj.CalibrationData)
        obj.CalibrationData = stimgen.calibration.Engine.rmfield_safe_(obj.CalibrationData, 'swept_sine');
    end
    stimgen.util.vprintf(0, 2, 'Swept sine calibration aborted: %s', ME.message);
    rethrow(ME);
end

% Commit only on full success
cd_out = obj.commit_cal_data_();
tm = analysis.transfer;
im = analysis.impulse;
hm = analysis.harmonics;
[noiseFloorDb, snrDb] = obj.estimate_noise_snr_(obj.ResponseSignal, fs, nan);
sweptRepeatability = obj.repeatability_stats_(measAll);
sweptHeadroomAll = repmat(struct( ...
    'assumedFullScaleV', nan, ...
    'excitationPeakV', nan, ...
    'excitationHeadroomDb', nan, ...
    'excitationClippingLikely', false, ...
    'responsePeakV', nan, ...
    'responseHeadroomDb', nan, ...
    'responseFlatTopFraction', nan, ...
    'responseClippingLikely', false), repeatCount, 1);
for rep = 1:repeatCount
    sweptHeadroomAll(rep) = obj.estimate_headroom_(y, responses{rep});
end
sweptHeadroom = obj.aggregate_headroom_(sweptHeadroomAll);
sweptSensitivity = swept_sine_data.spl_db(:) - 20*log10(max(obj.ExcitationVoltage, eps));
cd_out.swept_sine = struct( ...
    'frequency',   freqs(:), ...
    'measurement', swept_sine_data.measurement(:), ...
    'spl_db',      swept_sine_data.spl_db(:), ...
    'voltage',     swept_sine_data.voltage(:), ...
    'duration',    duration, ...
    'chirp_type',  "log-sine", ...
    'start_freq',  startFreq, ...
    'stop_freq',   stopFreq, ...
    'metrics', struct( ...
        'frequency_response_hz', tm.frequency_hz, ...
        'frequency_response_db', tm.magnitude_db, ...
        'magnitude_deviation_db', tm.magnitude_deviation_db, ...
        'flatness_std_db', tm.flatness_std_db, ...
        'magnitude_ripple_db', tm.magnitude_ripple_db, ...
        'phase_deg', tm.phase_deg, ...
        'minimum_phase_deg', tm.minimum_phase_deg, ...
        'excess_phase_deg', tm.excess_phase_deg, ...
        'group_delay_samples', tm.group_delay_samples, ...
        'group_delay_seconds', tm.group_delay_seconds, ...
        'excess_group_delay_seconds', tm.excess_group_delay_seconds, ...
        'phase_delay_seconds', tm.phase_delay_seconds, ...
        'group_delay_variation_s', tm.group_delay_variation_s, ...
        'bulk_delay_s', tm.bulk_delay_s, ...
        'free_field', analysis.free_field, ...
        'impulse_response', im.impulse_response, ...
        'impulse_response_time_s', im.impulse_response_time_s, ...
        'impulse_response_fs', im.impulse_response_fs, ...
        'arrival_delay_s', im.arrival_delay_s, ...
        'peak_delay_s', im.peak_delay_s, ...
        'direct_polarity', im.direct_polarity, ...
        'reflections', im.reflections, ...
        'decay', im.decay, ...
        'octave_bands', im.octave_bands, ...
        'rt60_s', im.decay.rt60_s, ...
        'edt_s', im.decay.edt_s, ...
        't20_s', im.decay.t20_s, ...
        't30_s', im.decay.t30_s, ...
        'c50_db', im.c50_db, ...
        'c80_db', im.c80_db, ...
        'd50', im.d50, ...
        'center_time_s', im.center_time_s, ...
        'drr_db', im.drr_db, ...
        'impulse_noise_ratio_db', im.inr_db, ...
        'record_truncated', im.record_truncated, ...
        'harmonics', hm, ...
        'calibrated_level_sensitivity_db_per_v', sweptSensitivity, ...
        'noise_floor_db', noiseFloorDb, ...
        'snr_db', snrDb, ...
        'thd_db', hm.thd_db, ...
        'thd_percent', hm.thd_percent, ...
        'h2_db', hm.h2_db, ...
        'h3_db', hm.h3_db, ...
        'repeatability', sweptRepeatability, ...
        'clipping_headroom', sweptHeadroom));
obj.CalibrationData = cd_out;
obj.CalibrationTimestamp = datetime('now');

swept_sine_data.sd_db = obj.level_sd_db_(measAll);
obj.emit_live_("swept_sine", "done", 'Table', swept_sine_data, ...
    'Index', 0, 'Total', n, 'Repeat', repeatCount, 'RepeatTotal', repeatCount, ...
    'Progress', 1, axisMeta{:}, ...
    'Metrics', struct('snr_db', snrDb, 'thd_db', hm.thd_db, ...
                      'h2_db', hm.h2_db, 'h3_db', hm.h3_db));

stimgen.util.vprintf(1, 'Swept sine calibration complete. %d points over %g-%g Hz, SNR: %.1f dB', ...
    n, freqs(1), freqs(end), snrDb);
stimgen.util.vprintf(1, ['  response %+.1f dB ripple, group delay %.2f ms bulk / %.2f ms variation, ' ...
    'THD %.2f%% (H2 %.1f dB, H3 %.1f dB)'], ...
    tm.magnitude_ripple_db, tm.bulk_delay_s * 1e3, tm.group_delay_variation_s * 1e3, ...
    hm.thd_percent, hm.h2_db, hm.h3_db);
stimgen.util.vprintf(1, ['  RT60 %.0f ms (%s), EDT %.0f ms, C50 %.1f dB, DRR %.1f dB, ' ...
    'first reflection %.2f ms at %.1f dB'], ...
    im.decay.rt60_s * 1e3, im.decay.rt60_source, im.decay.edt_s * 1e3, ...
    im.c50_db, im.drr_db, im.reflections.first_delay_ms, im.reflections.first_level_db);
if im.record_truncated
    stimgen.util.vprintf(0, 1, ['Swept sine decay did not reach the noise floor before the record ended; ' ...
        'reverberation times are lower bounds. Raise tailDuration above %.2f s.'], tailDuration);
end
end
