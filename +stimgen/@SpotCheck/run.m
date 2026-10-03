function results = run(obj)
% results = run(obj)
% obj.run
% Play the loaded stimulus, record it, and characterize what came back.
%
% The whole measurement, in order:
%
%   1. the stimulus waveform is taken as it stands, on the combination
%      VariantIndex names (regenerated only if Signal is empty or the
%      stimulus has moved off that combination, so what is measured is what
%      the object is holding; StepVariant moves one along first)
%   2. Engine.play_and_capture sends it, records the microphone, and cuts the
%      response back to the stimulus's own time base using the delay it
%      measures from the record itself
%   3. the record is wrapped in a stimgen.CapturedSignal and characterized by
%      stimgen.StimInspector.signal_metrics -- the same analysis the inspector
%      window shows, so the numbers reported here and the ones on screen there
%      are one computation
%   4. the level that came back is compared with the level that was asked for
%
% Sample rates must already agree. run() will not change the stimulus to make
% them: altering Fs regenerates the waveform, and quietly editing an object a
% caller is about to run in an experiment is not a decision this tool should
% make on its own. match_hardware_rate() is the explicit fix.
%
% Returns:
%   results - struct with fields:
%     stimulus  - what was asked for: class, label, file, fs, duration_s,
%                 calibration_type, requested_level_db, level_reference,
%                 measurement_mode, frequency_hz, variant, calibrated
%     capture   - the raw struct from Engine.play_and_capture
%     measured  - what came back: level_db_spl, level_error_db, rms_v, peak_v,
%                 crest_factor_db, noise_db_spl, snr_db, thd_percent,
%                 fundamental_hz, clipping, delay_s
%     stimulus_metrics / capture_metrics - full signal_metrics structs for the
%                 two waveforms, so every number the inspector shows for either
%                 is in the saved result too
%     warnings  - string array of everything that qualifies the numbers above
%     measuredOn
%
% Also left on the object: Capture, Recording and Results.
%
% See also: stimgen.calibration.Engine.play_and_capture, stimgen.SpotCheck.save_results

if obj.Running_
    error('stimgen:SpotCheck:alreadyRunning', ...
        'A spot check is already in progress.');
end

stimObj = obj.Stimulus;

if isempty(stimObj) || ~isvalid(stimObj)
    error('stimgen:SpotCheck:noStimulus', ...
        'Load a stimulus before running a spot check.');
end

if isempty(obj.Engine.Adapter)
    error('stimgen:SpotCheck:noAdapter', ...
        ['No acquisition hardware is attached, so nothing can be played or ' ...
         'recorded. Attach an adapter with set_adapter, or construct ' ...
         'stimgen.SpotCheck with one.']);
end

fsHw   = obj.Engine.Fs;
fsStim = double(stimObj.Fs);
if ~isfinite(fsHw) || fsHw <= 0
    error('stimgen:SpotCheck:noSampleRate', ...
        'The attached adapter reports no usable sample rate (%g Hz).', fsHw);
end
if abs(fsStim - fsHw) > 1e-6
    error('stimgen:SpotCheck:sampleRateMismatch', ...
        ['The stimulus runs at %.10g Hz but the hardware runs at %.10g Hz. ' ...
         'A waveform played at the wrong rate is a different waveform, so ' ...
         'the two must agree. Call match_hardware_rate to set the stimulus ' ...
         'to %.10g Hz, or reconfigure the adapter.'], fsStim, fsHw, fsHw);
end

% ---- 1. The waveform to play -------------------------------------------
% The combination the window names (VariantIndex), not whatever the stimulus's
% own selector would pick next. With StepVariant on, a run after one that
% measured this combination moves one along first, so the variant shown and
% the result shown always describe the same run. Otherwise the waveform is
% generated only when missing or on the wrong combination: an object that
% already holds the right signal is measured on that signal rather than on a
% freshly drawn one, which for a noise stimulus would not be the same waveform.
try
    if obj.StepVariant && obj.VariantMeasured_ && obj.variant_count_() > 1
        obj.pin_variant_(obj.VariantIndex + 1);
    else
        obj.sync_variant_();
    end
catch ME
    error('stimgen:SpotCheck:signalGenerationFailed', ...
        'The stimulus could not generate a waveform: %s', ME.message);
end

y = double(stimObj.Signal);
if isempty(y)
    error('stimgen:SpotCheck:emptySignal', ...
        'The stimulus generated an empty waveform; there is nothing to play.');
end
if ~all(isfinite(y))
    error('stimgen:SpotCheck:nonFiniteSignal', ...
        'The stimulus waveform contains non-finite values and cannot be played.');
end

% ---- 2. Play and record -------------------------------------------------
obj.Running_ = true;
cleanup = onCleanup(@() obj.finish_run_());

obj.set_status_(sprintf('Playing %.0f ms and recording (%d acquisition(s))...', ...
    numel(y) / fsStim * 1e3, obj.Repeats));

stimgen.util.vprintf(1, 'SpotCheck: running "%s" (%s) at %.10g Hz', ...
    char(obj.StimulusLabel), class(stimObj), fsStim);

capture = obj.Engine.play_and_capture(y, ...
    PreDelay  = obj.PreDelay, ...
    PostDelay = obj.PostDelay, ...
    Repeats   = obj.Repeats);

obj.Capture = capture;

% ---- 3. Wrap the record so the inspector can read it --------------------
% With the same microphone sensitivity analyze_ reads levels on, so the
% recording inspector reads in Pa and dB SPL on the scale this tool reports.
% NaN when no sensitivity has been measured: the record then stays in volts
% rather than being labelled dB SPL on the 1 V/Pa placeholder.
obj.Recording = stimgen.CapturedSignal.from_capture(capture, ...
    Stimulus       = stimObj, ...
    MicSensitivity = obj.mic_sensitivity_(stimObj), ...
    Spectral       = obj.Engine.spectral_options(), ...
    SourceLabel    = obj.StimulusLabel, ...
    Provenance     = provenance_(obj, stimObj, capture));

% ---- 4. Reduce to the comparison ---------------------------------------
results     = obj.analyze_(capture, stimObj);
obj.Results = results;
obj.VariantMeasured_ = true;

% ---- 5. Report ----------------------------------------------------------
obj.refresh_inspectors_();
if obj.is_open()
    obj.update_compare_plots_();
    obj.refresh_ui_();
end

obj.set_status_(summary_line_(results));

for w = results.warnings
    stimgen.util.vprintf(0, 1, char(w));
end

stimgen.util.vprintf(1, 'SpotCheck: %s', char(summary_line_(results)));
end % run


% =========================================================================

function p = provenance_(obj, stimObj, capture)
% p = provenance_(obj, stimObj, capture)
% What the recording needs to carry so it is still interpretable once it has
% been separated from the tool that made it.
p = struct( ...
    'stimulus_class', string(class(stimObj)), ...
    'stimulus_label', obj.StimulusLabel, ...
    'stimulus_file',  obj.StimulusFile, ...
    'fs',             capture.fs, ...
    'pre_delay_s',    capture.pre_delay_s, ...
    'post_delay_s',   capture.post_delay_s, ...
    'repeats',        capture.repeats, ...
    'delay_s',        capture.delay_s, ...
    'noise_rms_v',    capture.noise.rms_v, ...
    'measuredOn',     capture.measuredOn);
end


function s = summary_line_(r)
% s = summary_line_(r) - One-line verdict for the status bar and the log.
lu = stimgen.SpotCheck.level_unit_(r);
if isfinite(r.measured.level_error_db)
    s = sprintf('%.1f %s measured, %+.1f dB from the %.1f %s requested (%s).', ...
        r.measured.level_db_spl, lu, r.measured.level_error_db, ...
        r.stimulus.requested_level_db, lu, r.stimulus.level_reference);
elseif isfinite(r.measured.level_db_spl)
    s = sprintf('%.1f %s measured (%s); no calibrated level to compare against.', ...
        r.measured.level_db_spl, lu, r.stimulus.level_reference);
else
    s = 'Capture complete.';
end

if ~isempty(r.warnings)
    s = sprintf('%s  %d warning(s) — see the result table.', s, numel(r.warnings));
end
end
