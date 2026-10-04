function messageText = format_gui_error_message_(obj, ME, fallbackText)
% format_gui_error_message_() - Convert common errors into user-facing guidance.
arguments
    obj (1,1) stimgen.StimPlayer
    ME (1,1) MException
    fallbackText (1,1) string
end

if isempty(obj)
    messageText = fallbackText + newline + newline + string(ME.message);
    return
end

messageText = fallbackText + newline + newline + string(ME.message);

switch string(ME.identifier)
    case "StimPlayer:InvalidISI"
        messageText = "Enter either one positive ISI value in milliseconds, such as 1000, or a two-value range such as [500 1500].";
    case "stimgen:StimPlayer:SampleRateNotSupported"
        messageText = string(ME.message) + newline + newline + ...
            "The sample rate is unchanged. A rate change moves the highest frequency that can be represented, so bring the parameters of those stimuli inside the new range first, then set the rate again.";
    case "StimPlayer:InvalidCalibrationFile"
        messageText = "The selected calibration file did not contain a usable calibration object.";
    case "stimgen:StimPlayer:NoHardwareHost"
        messageText = "StimPlayer has no hardware to play through, so only speaker preview is available. " + ...
            "Open StimPlayer from the host application (e.g. EPsych), or set CaptureAdapter " + ...
            "to a stimgen.calibration.HwAdapter, to play through calibrated hardware.";
    case "stimgen:StimPlayer:HardwareRateMismatch"
        messageText = string(ME.message) + newline + newline + ...
            "A waveform generated at one rate plays at the wrong frequencies and duration at another. " + ...
            "Set the bank Sample Rate to the hardware rate, then preview again.";
    case "stimgen:StimPlayer:PreviewVoltageOutOfRange"
        messageText = string(ME.message) + newline + newline + ...
            "Lower the stimulus Sound Level so the calibrated drive voltage fits the output range.";
    case "stimgen:StimPlayer:HardwareLost"
        messageText = string(ME.message) + newline + newline + ...
            "The session was stopped rather than continued without output. Check the hardware connection and the loaded protocol, then Run again. StimOrder, StimOrderTime, StimPolarity and StimVariant hold the presentations made before the loss.";
    case "stimgen:StimPlayer:HardwareWriteFailed"
        messageText = string(ME.message) + newline + newline + ...
            "The next stimulus could not be loaded into the hardware buffer, so the session was stopped rather than trigger a stale buffer. Check the hardware connection, then Run again.";
    case "stimgen:StimPlayer:PreviewDuringRun"
        messageText = "The hardware is presenting the bank right now. Stop the session, then preview through hardware.";
    case "stimgen:StimPlayer:CaptureDuringRun"
        messageText = "A session is holding the hardware (running or paused). Stop it, then capture.";
    case "stimgen:StimPlayer:NoCaptureHardware"
        messageText = "Capture needs hardware that can play and record at once, with a microphone on its input. " + ...
            "Set CaptureAdapter to a stimgen.calibration.HwAdapter -- for example " + ...
            "stimgen.calibration.WindowsSoundCardAdapter -- or a function returning one, " + ...
            "or open StimPlayer from a host application that supplies a calibration adapter.";
    case "stimgen:StimPlayer:BadCaptureAdapter"
        messageText = string(ME.message) + newline + newline + ...
            "CaptureAdapter has to be something capture can play and record through.";
    case "stimgen:StimPlayer:CaptureVoltageOutOfRange"
        messageText = string(ME.message) + newline + newline + ...
            "Lower the stimulus Sound Level so the calibrated drive voltage fits the output range.";
    case "stimgen:StimPlayer:EmptyCaptureSignal"
        messageText = string(ME.message) + newline + newline + ...
            "Check the stimulus parameters: nothing was generated to play.";
    case "stimgen:util:filterRateMismatch"
        messageText = string(ME.message) + newline + newline + ...
            "An equalization filter only corrects the frequencies it was designed for at the sample rate it was designed at. Redesign the filter for this rate in the calibration GUI (Design Filter, ""Design sample rate"" field) -- the measurement itself does not have to be repeated -- or set the sample rate back to the one the calibration was designed at.";
    case "stimgen:StimType:UnknownWindowFcn"
        messageText = string(ME.message) + newline + newline + ...
            "Window Shape names a MATLAB window function. Pick one of the listed shapes, or supply a function on the path that takes a length in samples and returns that many window values.";
    case "stimgen:StimType:NonVectorizableProperty"
        messageText = "This property must stay scalar in StimPlayer. Use a single value rather than a vector or expression that expands to multiple values.";
    case "stimgen:StimType:PairwiseLengthMismatch"
        messageText = [ ...
            "Variant lengths do not match the selected combination mode." + newline + ...
            "Use equal-length vectors for PairwiseStrict, or use scalar-or-max-length vectors for PairwiseScalarExpand." ...
        ];
    case "stimgen:StimType:MissingSelectorClass"
        messageText = "Variant Selection is set to CustomSelector, but no selector class was provided.";
    case "stimgen:StimType:SelectorClassNotFound"
        messageText = "StimPlayer could not find the requested variant selector class on the MATLAB path.";
    case "stimgen:StimType:SelectorClassType"
        messageText = "The selected variant selector must define both initialize() and selectNext() methods.";
    case "stimgen:StimType:InvalidSelectorIndex"
        messageText = "The custom selector returned an invalid variant index for the available combinations.";
    case "stimgen:StimType:InvalidCombinationMode"
        messageText = "The selected variant combination mode is not recognized.";
    case "stimgen:StimType:InvalidSelectionMode"
        messageText = "The selected variant selection mode is not recognized.";
    case "stimgen:TORC:TemporalOrthogonality"
        messageText = "Two ripple components landed on the same modulation rate, which is what a TORC exists to avoid. Spread the rates apart, or lengthen Duration to make the rate grid finer.";
    case "stimgen:TORC:RateBelowFundamental"
        messageText = "Ripple rates cannot be slower than one cycle per ripple period. Raise the rate, lengthen Duration, or reduce Ripple Periods.";
    case "stimgen:TORC:BandwidthExceedsNyquist"
        messageText = "The highest carrier would exceed half the sample rate. Lower Low Frequency or Bandwidth, or raise Fs.";
    case {"stimgen:TORC:InvalidComponentList", "stimgen:TORC:EmptyComponentList"}
        messageText = "Enter the ripple components as a list of numbers, such as 4 8 12 16 or 4:4:24.";
    case "stimgen:TORC:InvalidRate"
        messageText = "Component rates must all be positive. Set the direction of travel with the sign of the ripple density instead.";
    case "stimgen:TORC:InvalidRateRange"
        messageText = "Highest Rate must be greater than or equal to Lowest Rate.";
    case "stimgen:SoundFile:EmptyCatalog"
        messageText = "This sound file stimulus has no files yet. Use the Browse... button to add one or more sound files.";
    case {"stimgen:SoundFile:FileNotFound", "stimgen:SoundFile:FileNotReadable"}
        messageText = [ ...
            "A sound file referenced by this stimulus could not be read." + newline + ...
            "It may have been moved, renamed, or deleted. Re-add it with Browse..., or embed the files (embed) so the bank no longer depends on them." + newline + newline + ...
            string(ME.message) ...
        ];
    case "stimgen:SoundFile:IndexOutOfRange"
        messageText = "File Index refers to a file that is not in the catalog. Use the Use All Files button, or enter an index or range within the catalog size.";
    case "stimgen:SoundFile:InvalidChannel"
        messageText = [ ...
            "The requested channel does not exist in that sound file." + newline + ...
            "Use 0 to average all channels to mono, or a channel number within the file." + newline + newline + ...
            string(ME.message) ...
        ];
    case "stimgen:SoundFile:WindowTooLong"
        messageText = [ ...
            "The onset/offset window is longer than the selected sound file." + newline + ...
            "Reduce Window Duration, or clear Apply Window." + newline + newline + ...
            string(ME.message) ...
        ];
    case "stimgen:SoundFile:NoEqualizer"
        messageText = "Calibration Mode is set to Filtered, but the loaded calibration has no equalization filter. Design one in the calibration GUI, or set Calibration Mode to Direct.";
    case "stimgen:SoundFile:VoltageOutOfRange"
        messageText = [ ...
            "The requested Sound Level would clip the output." + newline + ...
            "Natural sounds have a high crest factor, so the peak exceeds 10 V well before the RMS level does. Lower Sound Level." + newline + newline + ...
            string(ME.message) ...
        ];
    otherwise
        rawMessage = string(ME.message);
        if contains(rawMessage, "Expression cannot be empty.")
            messageText = "Enter a numeric value or MATLAB expression, such as 4000 or 500*2.^(0:3).";
        elseif contains(rawMessage, "Assignments are not allowed in expressions.")
            messageText = "Use expressions only. Do not include assignments like Frequency = ....";
        elseif contains(rawMessage, "Only a single expression is allowed.")
            messageText = "Enter one expression only. Separate values with spaces or MATLAB vector syntax rather than semicolons.";
        elseif contains(rawMessage, "must evaluate to a numeric or logical value.")
            messageText = "That expression did not resolve to numeric values. Try a numeric vector such as [1000 2000 4000] or an expression like 500*2.^(0:3).";
        elseif contains(rawMessage, "must evaluate to finite numeric values.")
            messageText = "The expression must evaluate to finite numbers only. Remove NaN, Inf, or divisions by zero.";
        end
end
end
