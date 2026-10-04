function set_busy_(obj, tf, cancellable)
% Disable calibration actions while an operation is running.
% Stop is only enabled for operations that actually poll cancel().
if tf
    obj.BtnReference.Enable = 'off';
    obj.BtnBackground.Enable = 'off';
    obj.BtnTones.Enable = 'off';
    obj.BtnClicks.Enable = 'off';
    obj.BtnSweptSine.Enable = 'off';
    obj.BtnTestTones.Enable = 'off';
    obj.BtnTestClicks.Enable = 'off';
    obj.BtnFilter.Enable = 'off';
    obj.BtnTestFilter.Enable = 'off';
    obj.BtnCopyFilter.Enable = 'off';
    obj.BtnDelay.Enable = 'off';
    obj.BtnReset.Enable = 'off';
    if cancellable
        obj.BtnStop.Enable = 'on';
    else
        obj.BtnStop.Enable = 'off';
    end
else
    obj.BtnStop.Enable = 'off';
    obj.BtnReset.Enable = 'on';
end
end
