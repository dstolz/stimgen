function on_calibrate_tones_(obj)
if ~obj.apply_controls_to_engine_()
    return
end
[freqs, repeatCount, refine, wasCancelled] = obj.prompt_vector_parameter_( ...
    'toneFreqs', 'toneRepeats', "Tone Frequencies (Hz)", ...
    'DlgToneFrequencies', 'Tone Calibration', obj.IterativeCheck.Value);
if wasCancelled
    obj.set_status_('Tone calibration cancelled.', false);
    return
end
obj.with_busy_state_(@() obj.run_calibrate_tones_(freqs, repeatCount, refine), ...
    'Running tone calibration...', true);
end
