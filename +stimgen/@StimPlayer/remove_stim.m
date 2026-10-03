function remove_stim(obj, ~, ~)
% remove_stim(obj) - Remove the currently selected bank item, after confirming.
% Deletes the corresponding StimPlay from StimPlayObjs,
% refreshes the listbox, and clears the tab group. The removal cannot be
% undone, so it is confirmed first (Cancel is the default).

h = obj.handles;

if isempty(h.BankList.ItemsData) || isempty(h.BankList.Value)
    return
end

idx = h.BankList.Value;
if idx < 1 || idx > numel(obj.StimPlayObjs)
    return
end

name = obj.StimPlayObjs(idx).Name;

if ~isempty(obj.hFig) && isvalid(obj.hFig)
    choice = uiconfirm(obj.hFig, ...
        sprintf('Remove "%s" from the bank? This cannot be undone.', char(name)), ...
        'Remove Stimulus', 'Options', {'Remove', 'Cancel'}, ...
        'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
    if ~strcmp(choice, 'Remove')
        return
    end
end

obj.StimPlayObjs(idx) = [];
obj.mark_bank_dirty_;

obj.refresh_listbox_;
obj.refresh_combo_controls_;
obj.update_calibration_status_;

% Clear tab group back to placeholder
obj.clear_tabs_;

stimgen.util.vprintf(2, 'StimPlayer: removed bank item "%s"', name);
obj.set_status_("Removed stimulus: " + string(name));
