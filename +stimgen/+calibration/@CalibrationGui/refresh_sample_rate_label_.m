function refresh_sample_rate_label_(obj)
% %.10g keeps non-integer converter rates exact on screen; %g
% would show 24414.0625 as 24414.1, and a user transcribing that
% rounded figure gets a filter assert_filter_rate refuses.
% Lives in the settings window, so with that closed there
% is nothing to update; reopening it refreshes from the engine.
if isempty(obj.SampleRateLabel) || ~isvalid(obj.SampleRateLabel)
    return
end
fs = obj.Engine.Fs;
if fs > 0
    txt = sprintf('%.10g Hz', fs);
else
    txt = 'No adapter';
end

% An FIR's taps carry the rate they were designed for, so a loaded
% calibration whose filter was cut at another rate equalizes the
% wrong frequencies. apply_calibration refuses it (through
% stimgen.util.assert_filter_rate), so a stimulus would fail at
% playback; report it here, where the rate is read, so it is seen
% before then.
designFs = obj.filter_design_rate_();
mismatched = designFs > 0 && (fs <= 0 || abs(designFs - fs) > 1e-6 * fs);
if mismatched
    txt = sprintf('%s (filter designed at %.10g Hz)', txt, designFs);
    obj.SampleRateLabel.FontColor = [0.7 0 0];
else
    obj.SampleRateLabel.FontColor = [0 0 0];
end
obj.SampleRateLabel.Text = txt;
end
