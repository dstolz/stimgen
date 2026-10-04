function lock_bank_controls_(obj, lockState)
% lock_bank_controls_(obj, lockState) - Enable/disable bank-editing controls.

h = obj.handles;
targetState = 'on';
if lockState
    targetState = 'off';
end

fields = {'AddBtn','DuplicateBtn','RemoveBtn','TypeDropdown','BankList','RepsField', ...
    'ISIField','FsField','OrderDD','OutputDD','ComboPrevBtn','ComboNextBtn','LoadProtocolMenu', ...
    'LoadBankMenu','SaveBankMenu','SaveBankAsMenu','CalibrationMenu','CalibrationGuiMenu', ...
    'RecentProtocolsMenu','RecentBanksMenu','RecentCalibrationsMenu', ...
    'LoadProtocolTool','LoadBankTool','SaveBankTool','CalibrationGuiTool', ...
    'AddStimTool','DuplicateStimTool','RemoveStimTool', ...
    'AddStimMenu','DuplicateStimMenu','RemoveStimMenu', ...
    'CombinationsMenu','CombinationsTool', ...
    ... % These step or regenerate the bank items the timer is playing.
    'PlayBtn','PlayAllBtn','PlayTool','PlayMenu', ...
    'ExportSignalMenu','ExportAllMenu','ExportObjsMenu'};
for i = 1:numel(fields)
    f = fields{i};
    if isfield(h, f) && ~isempty(h.(f)) && isvalid(h.(f))
        h.(f).Enable = targetState;
    end
end

if isfield(h, 'ParamPanel') && ~isempty(h.ParamPanel) && isvalid(h.ParamPanel)
    children = findall(h.ParamPanel);
    for i = 1:numel(children)
        if isprop(children(i), 'Enable')
            children(i).Enable = targetState;
        end
    end
end

% Capture follows the same lock -- a session paused is still a
% session holding the hardware -- but decides the rest for
% itself: unlocking must not enable it on a player with nothing
% to record through.
obj.CaptureLocked_ = lockState;
obj.sync_capture_controls_;

% Unlocking turned everything on; put back off what still
% cannot work (no host, no route, no selection).
obj.sync_control_enable_;
obj.refresh_combo_controls_;
end
