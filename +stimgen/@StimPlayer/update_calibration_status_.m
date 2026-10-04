function update_calibration_status_(obj)
% update_calibration_status_() - Refresh the calibration status label.
% The label answers two questions at once: is a calibration in
% use, and does the selected preview output actually reproduce
% it. Speaker preview normalizes to unit peak, so a loaded
% calibration shapes hardware output only — the label goes
% amber, not green, while speakers are selected.

h = obj.handles;
if ~isfield(h, 'CalibrationStatusLabel') || isempty(h.CalibrationStatusLabel) ...
        || ~isvalid(h.CalibrationStatusLabel)
    return
end

nItems  = numel(obj.StimPlayObjs);
nActive = 0;
for i = 1:nItems
    if obj.stim_has_calibration_(obj.StimPlayObjs(i).StimObj)
        nActive = nActive + 1;
    end
end

COLOR_ACTIVE   = [0.00 0.55 0.20];  % calibration reproduced by current output
COLOR_BYPASSED = [0.80 0.50 0.05];  % calibration present but output ignores levels
COLOR_NONE     = [0.75 0.15 0.15];  % no calibration at all

loaded = isa(obj.Calibration, 'stimgen.StimCalibration') && ...
    ~isempty(obj.Calibration.CalibrationData);

if loaded || nActive > 0
    if loaded && strlength(obj.CalibrationFile) > 0
        [~, fn, ext] = fileparts(char(obj.CalibrationFile));
        srcName = string([fn ext]);
    else
        srcName = "embedded";
    end
    displayName = srcName;
    if strlength(displayName) > 22
        displayName = extractBefore(displayName, 21) + "...";
    end

    tipText = "Calibration: " + srcName;
    if strlength(obj.CalibrationFile) > 0
        tipText = tipText + newline + obj.CalibrationFile;
    end
    if loaded
        ts = obj.Calibration.CalibrationTimestamp;
        if ~isempty(ts)
            tipText = tipText + newline + "Measured: " + string(ts);
        end
        calFs = obj.Calibration.Fs;
        if isscalar(calFs) && isfinite(calFs) && calFs > 0 && abs(calFs - obj.Fs) > 0.5
            tipText = tipText + newline + sprintf( ...
                'WARNING: calibration was measured at %g Hz but the bank plays at %g Hz.', ...
                calFs, obj.Fs);
        end
    end
    tipText = tipText + newline + ...
        sprintf('Applied by %d of %d bank item(s).', nActive, nItems);

    if obj.PlaybackOutput == "Hardware"
        h.CalibrationStatusLabel.Text      = char("Cal: " + displayName + " > HW");
        h.CalibrationStatusLabel.FontColor = COLOR_ACTIVE;
        tipText = tipText + newline + ...
            "Preview output is the calibrated hardware: calibrated levels are reproduced.";
    else
        h.CalibrationStatusLabel.Text      = char("Cal: " + displayName + " (speakers)");
        h.CalibrationStatusLabel.FontColor = COLOR_BYPASSED;
        tipText = tipText + newline + ...
            "Preview output is the computer speakers: the signal is normalized " + ...
            "for audition, so calibrated levels are NOT reproduced. Set Output to " + ...
            "Calibrated Hardware to hear the calibrated signal.";
    end
    tipText = tipText + newline + ...
        "A hardware Run always plays the generated (calibrated) waveform.";
else
    h.CalibrationStatusLabel.Text      = 'No calibration';
    h.CalibrationStatusLabel.FontColor = COLOR_NONE;
    tipText = "No calibration is loaded: stimulus levels are arbitrary. " + ...
        "Load one from the Calibration menu, or create one with the Calibration GUI.";
end

h.CalibrationStatusLabel.Tooltip = char(tipText);
end
