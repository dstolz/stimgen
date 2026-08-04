function open_calibration_gui(obj)
% open_calibration_gui(obj)
% Launch the stimgen calibration GUI from StimPlayer.
%
% Opens stimgen.calibration.CalibrationGui in a separate window, forwarding
% this StimPlayer's Host (if any) so File > Initialize Runtime From
% Protocol... can drive the same hardware. Without a host, the calibration
% GUI opens offline and the runtime menu actions are unavailable.

try
    stimgen.calibration.CalibrationGui(obj.Host);
    if isempty(obj.Host)
        obj.show_gui_message_( ...
            "Calibration GUI opened in offline mode; this StimPlayer has no hardware host attached.", ...
            "Calibration GUI", "info");
    else
        obj.show_gui_message_( ...
            "Calibration GUI opened. Initialize hardware there using File > Initialize Runtime From Protocol....", ...
            "Calibration GUI", "info");
    end
catch ME
    obj.report_gui_error_(ME, "Calibration GUI Error", ...
        "StimPlayer could not open the calibration GUI.");
end
end
