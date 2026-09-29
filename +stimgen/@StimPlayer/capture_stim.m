function rec = capture_stim(obj, ~, ~)
% rec = capture_stim(obj)
% Play the selected stimulus through the rig, record the microphone, and
% open the recording in an inspector that reads it as sound.
%
% The combination on screen is played exactly as it would be presented --
% the generated, calibrated waveform, in volts, no normalization -- through
% hardware that records while it plays: CaptureAdapter when one is set, else
% the attached host's calibration adapter. stimgen.calibration.Engine's
% play_and_capture does the acquisition, on the same path every calibration
% measurement takes: silence before the stimulus (CapturePreDelay, which the
% noise floor is measured over), silence after it (CapturePostDelay, which
% bounds the search for the response delay), CaptureRepeats acquisitions
% each aligned on its own delay, and the response cut back onto the
% stimulus's own time base.
%
% The record comes back as a stimgen.CapturedSignal and opens in this
% player's capture inspector -- one window, reused by every capture, and
% separate from the inspector that follows the bank selection. With a
% calibration loaded (the stimulus's own, else the player's) the record
% carries that calibration's microphone sensitivity, so the inspector shows
% it in pascals and dB SPL: sound-level-meter readouts, band levels, the
% noise floor under it, and the level the stimulus asked for against the
% level that came back, measured the way its calibration table was measured
% (stimgen.util.level_request / level_as_calibrated). Without one it opens
% in volts and says why.
%
% THE RATE THE HARDWARE RUNS AT WINS, AND THE BANK IS NOT TOUCHED. A
% waveform played at a rate it was not generated at is a different
% waveform, so when the bank's rate and the hardware's disagree the
% selected combination is regenerated natively at the hardware rate on a
% copy -- pinned to the same combination, never resampled -- and the copy is
% what is played. The bank keeps its rate and its signals. For a noise
% stimulus the copy is a fresh draw from the same parameters, which is also
% what a host regenerating the bank at its own rate would play.
%
% Parameters (both ignored; present so this can be a GUI callback):
%   src, event
%
% Returns:
%   rec - stimgen.CapturedSignal, also left in LastCapture; [] when the
%         capture did not happen (the reason is on the status line)
%
% Example:
%   sp = stimgen.StimPlayer;
%   sp.open_stim(stimgen.Tone('Frequency', 4000, 'SoundLevel', 70));
%   sp.load_calibration_('rigB.esgc');
%   sp.CaptureAdapter = stimgen.calibration.WindowsSoundCardAdapter(SampleRate=96000);
%   rec = sp.capture_stim;
%
% See also: stimgen.calibration.Engine.play_and_capture,
%           stimgen.CapturedSignal.from_capture, stimgen.StimInspector,
%           stimgen.SpotCheck

rec = [];

if obj.Capturing_
    obj.set_status_("A capture is already in progress.");
    return
end

try
    if obj.CaptureLocked_ || (~isempty(obj.Timer) && isvalid(obj.Timer) ...
            && strcmp(obj.Timer.Running, 'on'))
        error('stimgen:StimPlayer:CaptureDuringRun', ...
            'A session is holding the hardware; stop it before capturing.');
    end

    sp = obj.selected_or_current_spobj_();
    if isempty(sp)
        obj.show_gui_message_("Select a stimulus to capture.", ...
            "Nothing To Capture", "warning");
        return
    end

    obj.Capturing_ = true;
    finished = onCleanup(@() obj.capture_finished_());
    obj.sync_capture_controls_;

    stimObj = sp.CurrentStimObj;

    % ---- 1. The route, and the rate it runs at ----------------------------
    adapter = obj.resolve_capture_adapter_;
    fsHw = double(adapter.sample_rate());
    if ~(isscalar(fsHw) && isfinite(fsHw) && fsHw > 0)
        error('stimgen:StimPlayer:NoCaptureRate', ...
            'The capture hardware reports no usable sample rate (%g Hz).', fsHw);
    end

    % ---- 2. The waveform as it will be played -----------------------------
    obj.set_computing_(true);
    computing = onCleanup(@() obj.set_computing_(false));
    [playObj, regenerated] = waveform_at_rate_(stimObj, fsHw);
    clear computing

    y = double(playObj.Signal);
    if isempty(y)
        error('stimgen:StimPlayer:EmptyCaptureSignal', ...
            'The selected stimulus generated an empty waveform; there is nothing to play.');
    end
    if ~all(isfinite(y))
        error('stimgen:StimPlayer:EmptyCaptureSignal', ...
            'The selected stimulus waveform contains non-finite values and cannot be played.');
    end

    % ---- 3. The scale the record will be read on --------------------------
    % A fresh engine rather than the calibration's own: attaching an adapter
    % to that one would change what every bank item sharing it reports (its
    % Fs follows the adapter). It takes the settings that decide how a
    % record is conditioned and measured, so a capture is treated as the
    % calibration's own measurements were.
    [calObj, calSource] = obj.capture_calibration_(stimObj);
    eng  = stimgen.calibration.Engine(adapter);
    sens = NaN;
    if ~isempty(calObj)
        ce = calObj.Engine;
        eng.set_configuration( ...
            MicSensitivity    = ce.MicSensitivity, ...
            MaxOutputVoltage  = ce.MaxOutputVoltage, ...
            AcCoupleResponse  = ce.AcCoupleResponse, ...
            AcCoupleFrequency = ce.AcCoupleFrequency, ...
            SpectralWindow    = ce.SpectralWindow, ...
            SpectralFftLength = ce.SpectralFftLength);
        sens = ce.MicSensitivity;
    end

    peakV = max(abs(y));
    if peakV > eng.MaxOutputVoltage
        error('stimgen:StimPlayer:CaptureVoltageOutOfRange', ...
            'The waveform peaks at %.3g V, beyond the %.3g V output range.', ...
            peakV, eng.MaxOutputVoltage);
    end

    % ---- 4. Play and record -----------------------------------------------
    label = capture_label_(sp, stimObj);
    obj.set_status_(sprintf('Capturing "%s": %.0f ms at %.10g Hz, %d acquisition(s)...', ...
        label, numel(y) / fsHw * 1e3, fsHw, obj.CaptureRepeats));
    drawnow

    capture = eng.play_and_capture(y, ...
        PreDelay  = obj.CapturePreDelay, ...
        PostDelay = obj.CapturePostDelay, ...
        Repeats   = obj.CaptureRepeats, ...
        Stage     = "stimplayer_capture");

    % ---- 5. Wrap it with everything the inspector reads ------------------
    if regenerated
        regenHz = fsHw;
    else
        regenHz = NaN;
    end
    prov = struct( ...
        'bank_item',          string(sp.Name), ...
        'stimulus_class',     string(class(stimObj)), ...
        'stimulus_fs',        double(stimObj.Fs), ...
        'regenerated_at_hz',  regenHz, ...
        'calibration_source', calSource, ...
        'parameters',         string(playObj.current_parameter_summary()));

    rec = stimgen.CapturedSignal.from_capture(capture, ...
        Stimulus       = playObj, ...
        MicSensitivity = sens, ...
        Spectral       = eng.spectral_options(), ...
        SourceLabel    = label, ...
        Provenance     = prov);
    obj.LastCapture = rec;

    % ---- 6. Show it -------------------------------------------------------
    obj.show_capture_inspector_(rec, "Recording — " + label);

    summary = summary_line_(rec, label, eng.spectral_options());
    obj.set_status_(summary, isError=~isempty(rec.Warnings));
    stimgen.util.vprintf(1, 'StimPlayer: %s', char(summary));
    for w = rec.Warnings
        stimgen.util.vprintf(1, 1, 'StimPlayer capture: %s', char(w));
    end
catch ME
    rec = [];
    obj.report_gui_error_(ME, "Capture Error", ...
        "StimPlayer could not capture the selected stimulus.");
end
end


% =========================================================================

function [playObj, regenerated] = waveform_at_rate_(stimObj, fsHw)
% [playObj, regenerated] = waveform_at_rate_(stimObj, fsHw)
% The selected combination as it will be played at fsHw.
%
% At the bank's own rate that is the object itself, holding the signal the
% player is showing. At another rate it is a copy regenerated natively there
% and pinned to the combination on screen. copy() is safe for this: the
% original's property listeners and plot handles are carried over but stay
% attached to the original, so nothing the copy does redraws the player.
% VariantReselectOnUpdate is forced off first, or reading the copy's
% parameters afterwards would advance its selection and describe a
% different combination than the one just generated (the same reason
% mabr.stim.fromStimgen gives).
regenerated = abs(double(stimObj.Fs) - fsHw) > 0.5;

if ~regenerated
    playObj = stimObj;
    if isempty(playObj.Signal)
        playObj.update_signal();
    end
    return
end

info = stimObj.get_variant_info();
playObj = copy(stimObj);
playObj.VariantReselectOnUpdate = false;
playObj.Fs = fsHw;
playObj.set_variant_index(max(1, info.ActiveIndex));
stimgen.util.vprintf(1, ['StimPlayer: capture regenerates "%s" at the hardware ' ...
    'rate, %.10g Hz (the bank stays at %.10g Hz).'], class(stimObj), fsHw, double(stimObj.Fs));
end


function label = capture_label_(sp, stimObj)
% The bank item's name, with the combination when it has several.
label = string(sp.Name);
try
    info = stimObj.get_variant_info();
    if info.NumCombinations > 1
        label = label + sprintf(' [combo %d/%d]', info.ActiveIndex, info.NumCombinations);
    end
catch
end
end


function s = summary_line_(rec, label, spectral)
% One line for the status bar and the log: the level that came back and,
% when the stimulus asked for a calibrated one, how far it landed from it.
% Built as a string from the start: + between two char vectors is arithmetic.
s = string(sprintf('Captured "%s".', label));
if ~rec.has_spl_scale()
    s = s + " No calibration loaded, so it is shown in volts.";
else
    m = stimgen.util.level_as_calibrated(rec.Waveform, rec.Fs, rec.Request, ...
        rec.MicSensitivity, spectral);
    if isfinite(m.error_db)
        s = s + sprintf(' %.1f %s (%s), %+.1f dB from the %.1f %s requested.', ...
            m.level_db, m.level_unit, m.level_reference, m.error_db, ...
            m.requested_db, m.level_unit);
    elseif isfinite(m.level_db)
        s = s + sprintf(' %.1f %s (%s); the requested level is nominal.', ...
            m.level_db, m.level_unit, m.level_reference);
    end
end
if ~isempty(rec.Warnings)
    s = s + sprintf(' %d warning(s) - see the capture inspector.', numel(rec.Warnings));
end
end
