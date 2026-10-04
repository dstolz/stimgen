function on_reset_calibration_(obj)
% Discard acquired calibration data and start over. The engine's
% adapter, its persistent parameters (including mic sensitivity
% from Measure Reference), and this window's preferences are left
% untouched -- only CalibrationData, the last response record, and
% the calibration timestamp are cleared.
if obj.Engine.IsCalibrated
    msg = ['Discard all acquired tone/click/swept-sine calibration ' ...
        'data and any designed filter?' newline newline ...
        'The attached adapter, loaded protocol, mic sensitivity, ' ...
        'and other settings are kept.'];
    choice = uiconfirm(obj.Figure, msg, 'Reset Calibration', ...
        Options={'Reset', 'Cancel'}, DefaultOption=2, CancelOption=2, ...
        Icon='warning');
    if ~strcmp(choice, 'Reset')
        obj.set_status_('Reset cancelled.', false);
        return
    end
end

obj.Engine.reset_calibration();
% Nothing is left to save, so nothing is left unsaved.
obj.Dirty_ = false;
obj.refresh_all_plots_();
obj.update_runtime_state_();
obj.set_status_('Calibration reset. Ready to measure again.', false);
end
