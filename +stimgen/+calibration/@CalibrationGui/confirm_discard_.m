function proceed = confirm_discard_(obj, actionText)
% proceed = confirm_discard_(obj, actionText)
% Ask before an action that would drop an unsaved calibration:
% Save (then proceed if the save completed), Discard, or Cancel.
% True straight away when nothing is unsaved -- or nothing could be
% saved, since Engine.save refuses an engine with no tables.
proceed = true;
if ~obj.Dirty_ || ~obj.Engine.IsCalibrated
    return
end
msg = sprintf(['This calibration has results that have not been saved. ' ...
    'Save them before %s?'], actionText);
choice = uiconfirm(obj.Figure, msg, 'Unsaved Calibration', ...
    Options={'Save', 'Discard', 'Cancel'}, DefaultOption=1, ...
    CancelOption=3, Icon='warning');
switch choice
    case 'Save'
        try
            ffn = obj.run_save_('');
        catch ME
            obj.set_status_(ME.message, true);
            uialert(obj.Figure, ME.message, 'Save Failed', Icon='error');
            proceed = false;
            return
        end
        % An empty path is a save dialog cancelled: nothing was
        % written, so nothing may be dropped either.
        proceed = ~isempty(ffn);
    case 'Discard'
        proceed = true;
    otherwise
        proceed = false;
end
end
