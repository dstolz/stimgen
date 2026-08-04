function calibrate_reference(obj)
% calibrate_reference(obj)
% Measure the microphone sensitivity using a 1-second tone at
% ReferenceFrequency. Updates MicSensitivity.
%
% Broadcasts LiveUpdate around the measurement when ShowLivePlots is set. The
% harmonic markers matter here more than anywhere else in the calibration: the
% whole scale rests on this one number, and a reference tone with visible
% distortion or a wandering level is the cheapest failure to catch.
obj.assert_adapter_();
obj.begin_run_();
fs = obj.Fs;

so         = stimgen.Tone;
so.Fs      = fs;
so.Duration = 1;
so.Frequency = obj.ReferenceFrequency;
so.update_signal();

y = obj.ExcitationVoltage .* so.Signal;
obj.ExcitationSignal = y;

f0 = obj.ReferenceFrequency;
marks  = [f0 2*f0 3*f0];
labels = ["f0" "2f0" "3f0"];
obj.emit_live_("reference", "start", ...
    'Markers', marks, 'MarkerLabels', labels, 'Total', 1, 'Index', 1);

r = obj.measure_(y, "specfreq", StimFrequency=f0);

% Convert measured RMS voltage to V/Pa.
% At ReferenceLevel dB SPL (standard 94 dB = 1 Pa),
% dv = 1 -> MicSensitivity = r V/Pa.
dv = 10 ^ ((obj.ReferenceLevel - 94) / 20);
obj.MicSensitivity = r / dv;

% Emitted after MicSensitivity is updated so the spectrum is drawn on the
% scale the measurement just established, not the one it replaced.
[~, snrDb] = obj.estimate_noise_snr_(obj.ResponseSignal, fs, f0);
[thdDb, h2Db, h3Db] = obj.estimate_harmonics_(obj.ResponseSignal, fs, f0);
obj.emit_live_("reference", "done", ...
    'Markers', marks, 'MarkerLabels', labels, 'Total', 1, 'Index', 1, ...
    'Metrics', struct('spl_db', obj.ReferenceLevel, 'snr_db', snrDb, ...
                      'thd_db', thdDb, 'h2_db', h2Db, 'h3_db', h3Db));

stimgen.util.vprintf(1, 'Mic sensitivity = %.4f V @ %.1f dB SPL = %.4f V/Pa', ...
    r, obj.ReferenceLevel, obj.MicSensitivity);
end
