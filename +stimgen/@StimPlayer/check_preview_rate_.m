function check_preview_rate_(~, hwFs, stimFs)
% check_preview_rate_(hwFs, stimFs) - Refuse a rate-mismatched preview.
if isfinite(hwFs) && hwFs > 0 && abs(hwFs - stimFs) > 0.5
    error('stimgen:StimPlayer:HardwareRateMismatch', ...
        'The hardware plays at %.2f Hz but this stimulus was generated at %.2f Hz.', ...
        hwFs, stimFs);
end
end
