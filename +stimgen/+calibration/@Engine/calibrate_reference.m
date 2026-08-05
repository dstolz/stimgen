function calibrate_reference(obj)
% calibrate_reference(obj)
% Measure the microphone sensitivity from an external acoustic calibrator
% (PCB CAL150, B&K 4231, ...) seated on the microphone. Updates
% MicSensitivity.
%
% Nothing is played. The reference tone is produced by the calibrator, not by
% the rig: that is the whole point of the step, since a known acoustic level
% at the microphone is what turns recorded volts into pascals. Driving the
% speaker here would only add a second, uncalibrated source to the recording.
% The engine records for REC_DURATION seconds and reads the level at
% ReferenceFrequency out of that record.
%
% Broadcasts LiveUpdate around the measurement when ShowLivePlots is set. The
% harmonic markers matter here more than anywhere else in the calibration: the
% whole scale rests on this one number, and a reference tone with visible
% distortion or a wandering level is the cheapest failure to catch.
REC_DURATION   = 1;    % s of microphone record to analyse
MIN_TONE_SNR_DB = 20;  % below this the calibrator is off, absent, or misseated

obj.assert_adapter_();
obj.begin_run_();
fs = obj.Fs;

f0     = obj.ReferenceFrequency;
marks  = [f0 2*f0 3*f0];
labels = ["f0" "2f0" "3f0"];

% No excitation exists to plot behind the response; cleared so a stale
% waveform from an earlier run is not drawn as if it belonged to this one.
obj.ExcitationSignal = [];

obj.emit_live_("reference", "start", ...
    'Markers', marks, 'MarkerLabels', labels, 'Total', 1, 'Index', 1);

nsamps = max(round(REC_DURATION * fs), 1);
r = obj.measure_(zeros(1, nsamps), "specfreq", StimFrequency=f0, Record=true);

[~, snrDb] = obj.estimate_noise_snr_(obj.ResponseSignal, fs, f0);

% A silent or noise-only record would otherwise be accepted and scale every
% subsequent measurement by a meaningless sensitivity.
if r <= 0 || (isfinite(snrDb) && snrDb < MIN_TONE_SNR_DB)
    error('stimgen:calibration:Engine:noReferenceTone', ...
        ['No %g Hz reference tone in the recording (SNR %.1f dB). This step ' ...
        'records only -- the tone must come from an acoustic calibrator on ' ...
        'the microphone, not from the speaker. Check that the calibrator is ' ...
        'switched on, seated on the microphone, and set to %g Hz / %g dB SPL, ' ...
        'and that the microphone reaches the acquisition input.'], ...
        f0, snrDb, f0, obj.ReferenceLevel);
end

% Convert measured RMS voltage to V/Pa.
% At ReferenceLevel dB SPL (standard 94 dB = 1 Pa),
% dv = 1 -> MicSensitivity = r V/Pa.
dv = 10 ^ ((obj.ReferenceLevel - 94) / 20);
obj.MicSensitivity = r / dv;

% Emitted after MicSensitivity is updated so the spectrum is drawn on the
% scale the measurement just established, not the one it replaced.
[thdDb, h2Db, h3Db] = obj.estimate_harmonics_(obj.ResponseSignal, fs, f0);
obj.emit_live_("reference", "done", ...
    'Markers', marks, 'MarkerLabels', labels, 'Total', 1, 'Index', 1, ...
    'Metrics', struct('spl_db', obj.ReferenceLevel, 'snr_db', snrDb, ...
                      'thd_db', thdDb, 'h2_db', h2Db, 'h3_db', h3Db));

stimgen.util.vprintf(1, 'Mic sensitivity = %.4f V @ %.1f dB SPL = %.4f V/Pa', ...
    r, obj.ReferenceLevel, obj.MicSensitivity);
end
