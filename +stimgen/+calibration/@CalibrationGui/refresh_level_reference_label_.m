function refresh_level_reference_label_(obj)
% SPL the equalized source produces at unity hardware gain, and
% the factor that brings it to the normative level. This is what a
% hardware chain (source -> FIR -> gain) needs, because
% apply_calibration's renormalize-then-scale runs in software
% only: without it the filter's insertion loss lands on the output
% level. Shown for a 1 V RMS white-noise source -- the closed-form
% case; a shaped source needs Engine.filter_level_reference with
% its actual waveform.
try
    r = obj.Engine.filter_level_reference(1);
    % char(215) is the multiplication sign; the scale reads as
    % "multiply the filtered source (or the taps) by this".
    obj.LevelRefLabel.Text = sprintf('%.1f dB SPL  (%c%.3g)', ...
        r.unityGainSpl, char(215), r.scale);
catch
    % No filter, or no LUT to anchor it -- either way there is no
    % reference to report yet.
    obj.LevelRefLabel.Text = 'Not designed';
end
end
