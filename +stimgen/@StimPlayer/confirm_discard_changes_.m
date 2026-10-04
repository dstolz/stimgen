function tf = confirm_discard_changes_(obj, actionText)
% tf = confirm_discard_changes_(actionText) - Offer to save unsaved bank edits.
% Returns true when it is safe to go on: nothing was unsaved, the
% operator saved (and the save succeeded), or chose Discard.
% Cancel, a cancelled Save dialog or a failed save return false.
%
% Parameters:
%   actionText - what is about to happen, e.g. "closing"
tf = true;
if ~obj.Dirty_ || isempty(obj.hFig) || ~isvalid(obj.hFig)
    return
end
if strlength(obj.BankFile) > 0
    [~, fn, ext] = fileparts(char(obj.BankFile));
    what = sprintf('The bank (%s%s) has', fn, ext);
else
    what = 'The bank has';
end
msg = sprintf('%s unsaved changes. Save them before %s?', what, char(actionText));
choice = uiconfirm(obj.hFig, msg, 'Unsaved Changes', ...
    'Options', {'Save', 'Discard', 'Cancel'}, ...
    'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'warning');
switch choice
    case 'Save'
        obj.save_bank();
        tf = ~obj.Dirty_;
    case 'Discard'
        tf = true;
    otherwise
        tf = false;
end
end
