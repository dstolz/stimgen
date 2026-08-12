function results = measure_background(obj, duration, repeatCount, options)
% results = measure_background(obj)
% results = measure_background(obj, duration)
% results = measure_background(obj, duration, repeatCount)
% results = measure_background(obj, duration, repeatCount, Name=Value)
% Capture and characterize the acoustic background with nothing presented.
%
% Nothing is played: the engine records the microphone through
% HwAdapter.record, the same silent acquisition path calibrate_reference uses.
% What comes back is whatever the room, the rig, and the acquisition chain
% contribute on their own -- fan noise, mains hum, amplifier hiss, a colony
% room next door.
%
% This is the floor every other measurement sits on. A tone calibration point
% only means what it says while the tone is well above it, and a behavioural
% threshold cannot be lower than it, so measuring it explicitly turns "the SNR
% looked fine" into a number that is recorded with the calibration and can be
% compared across days.
%
% Levels are in dB SPL on the scale set by the last calibrate_reference, so run
% the reference first -- with the calibrator removed again before this step.
% Without one, MicSensitivity is whatever it was and the levels are volts
% dressed as pascals.
%
% Requires an adapter. No lookup table is touched; results are returned and
% stored in CalibrationData.background, so a saved .esgc carries the noise
% floor its tables were measured over. Repeated calls overwrite that record.
% CalibrationTimestamp is deliberately left alone: a background capture does
% not re-date the transfer measurements.
%
% Broadcasts LiveUpdate with stage "background" (gated by ShowLivePlots) as
% each record is acquired, and polls cancel() between records. Because the
% analysis is spectral and runs once over all the records, the band curve is
% drawn by stimgen.calibration.LiveMonitor/show_background when the run
% finishes rather than filling in during it.
%
% Parameters:
%   duration    - seconds per record (default: 2)
%   repeatCount - number of records; their spectra are power-averaged and the
%                 spread of their levels reports how steady the room is
%                 (default: 3)
%
% Name-Value Parameters:
%   FractionalOctave     - band resolution: 1, 3, 6, or 12 bands per octave
%                          (default: 3, i.e. third-octave)
%   TonalProminenceDb    - how far a spectral peak must stand above the local
%                          floor to be reported as a tonal component
%                          (default: 6)
%   MaxPeaks             - most tonal components to report (default: 8)
%   StabilityToleranceDb - spread across records at or below which the
%                          background is called steady (default: 3)
%
% Returns:
%   results - struct; see analyze_background_ for the full field list. The
%             headline fields are spl_db, spl_dba, bands, peaks, mains,
%             stable and flags.
%
% Example:
%   eng.calibrate_reference();     % with the calibrator on the mic
%   % ... calibrator removed, mic back in the test position ...
%   r = eng.measure_background(2, 3);
%   fprintf('background %.1f dB SPL (%.1f dBA)\n', r.spl_db, r.spl_dba);
%
% See also: stimgen.calibration.Engine/calibrate_reference,
%           stimgen.calibration.LiveMonitor/show_background,
%           documentation/stimgen_calibration.md
arguments
    obj
    duration    (1,1) double {mustBePositive, mustBeFinite} = 2
    repeatCount (1,1) double {mustBeInteger, mustBePositive, mustBeFinite} = 3
    options.FractionalOctave     (1,1) double {mustBeMember(options.FractionalOctave, [1 3 6 12])} = 3
    options.TonalProminenceDb    (1,1) double {mustBePositive, mustBeFinite} = 6
    options.MaxPeaks             (1,1) double {mustBeInteger, mustBeNonnegative} = 8
    options.StabilityToleranceDb (1,1) double {mustBePositive, mustBeFinite} = 3
end

% Below this there are too few samples for a band analysis to mean anything;
% the spectral floor would be dominated by the estimator rather than the room.
MIN_DURATION = 0.05;

obj.assert_adapter_();
obj.reset_cancel_();

fs = obj.Fs;
if ~isfinite(fs) || fs <= 0
    error('stimgen:calibration:Engine:noSampleRate', ...
        'The background measurement needs a sample rate, which comes from the hardware adapter.');
end
if duration < MIN_DURATION
    error('stimgen:calibration:Engine:backgroundTooShort', ...
        'A background record must be at least %g s; %g s was requested.', ...
        MIN_DURATION, duration);
end

nsamps = max(round(duration * fs), 1);

% Nothing is played, so there is no excitation to draw behind the response, and
% no fundamental for a THD figure to be about. Both are cleared rather than
% left holding values from an earlier run that would be read as belonging to
% this record.
obj.ExcitationSignal = [];
obj.ResponseTHD      = nan;

axisMeta = {'XLabel', "frequency (Hz)", 'XScale', "log", 'XFactor', 1};

obj.begin_run_();
obj.emit_live_("background", "start", 'Total', repeatCount, ...
    'RepeatTotal', repeatCount, 'Progress', 0, axisMeta{:});

records = cell(1, repeatCount);
try
    for rep = 1:repeatCount
        obj.throw_if_cancelled_();
        stimgen.util.vprintf(2, '[%d/%d] Background: recording %.2f s of silence', ...
            rep, repeatCount, nsamps / fs);

        y = obj.Adapter.record(nsamps);
        y = obj.trim_response_(double(y(:)).');

        % An all-zero record is the acquisition path being disconnected, not a
        % silent room: a microphone always returns something. Caught here
        % because every level downstream would otherwise be -Inf dB.
        if isempty(y) || ~any(y)
            error('stimgen:calibration:Engine:silentAcquisition', ...
                ['The acquisition input returned only zeros. This step records the ' ...
                 'microphone with nothing played, so an all-zero record means the ' ...
                 'microphone is not reaching the input -- check the mic, its power ' ...
                 'supply, and the input channel the adapter is reading.']);
        end

        % The analysis gets the record as acquired whatever AcCoupleResponse
        % says: analyze_background_ removes each record's mean itself, and
        % reports it as dc_offset_v -- an acquisition-health number that
        % AC coupling first would silently turn into zero -- and the band
        % levels are meant to describe the floor the room actually has, not a
        % high-passed view of it. The displayed copy follows the option, so
        % the panel shows the record in the form the sweeps would see it.
        records{rep} = y;
        obj.ResponseSignal = obj.ac_couple_response_(y);

        % The last slot of the progress bar belongs to the analysis, which runs
        % once over every record and is not free at high sample rates.
        obj.emit_live_("background", "measure", ...
            'Index', rep, 'Total', repeatCount, ...
            'Repeat', rep, 'RepeatTotal', repeatCount, ...
            'Progress', rep / (repeatCount + 1), axisMeta{:}, ...
            'Metrics', struct('spl_db', ...
                obj.compute_spl_voltage_(sqrt(mean((y - mean(y)) .^ 2)), "rms")));
    end

    obj.throw_if_cancelled_();
    results = obj.analyze_background_(records, fs, options);
catch ME
    % Nothing is committed on the way through, so an abort leaves any earlier
    % background record in place rather than half-replacing it.
    stimgen.util.vprintf(0, 2, 'Background measurement aborted: %s', ME.message);
    rethrow(ME);
end

cd_out = obj.commit_cal_data_();
cd_out.background = results;
obj.CalibrationData = cd_out;

obj.emit_live_("background", "done", 'Total', repeatCount, 'Index', repeatCount, ...
    'Repeat', repeatCount, 'RepeatTotal', repeatCount, 'Progress', 1, axisMeta{:}, ...
    'Metrics', struct('spl_db', results.spl_db));

stimgen.util.vprintf(1, ...
    'Background: %.1f dB SPL (%.1f dB(A)) over %g s x %d, loudest 1/%d-octave band %.0f Hz at %.1f dB SPL', ...
    results.spl_db, results.spl_dba, duration, repeatCount, ...
    options.FractionalOctave, results.worst_band.frequency, results.worst_band.level_db);

for k = 1:numel(results.flags)
    stimgen.util.vprintf(0, 1, 'Background: %s', results.flags(k));
end
end
