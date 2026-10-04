function sync_control_enable_(obj)
% sync_control_enable_() - Enable each control only when it can work.
% The run lock (lock_bank_controls_) disables the bank-editing
% controls during a session; on top of that, a control stays
% off while its precondition is missing:
%   Load Protocol (menu, toolbar, recent) - needs a host
%   Remove, Duplicate, Play, Show All Combinations,
%   Export Signal                          - need a selected item
%   Play All                               - needs a selected item
%                                            (or is its own Stop)
%   Export All / Export Bank               - need a non-empty bank
%   Output dropdown                        - needs a hardware route
%                                            (it has one choice
%                                            without; left on while
%                                            showing "Hardware")
% Called after every change to one of those inputs and at the
% end of lock_bank_controls_, so unlocking cannot re-enable a
% control the lock list knows nothing about.
h = obj.handles;
unlocked = ~obj.CaptureLocked_;
hasSel   = ~isempty(obj.selected_bank_index_());
hasItems = ~isempty(obj.StimPlayObjs);
hasHost  = ~isempty(obj.Host);
hasRoute = obj.has_hardware_route_ || obj.PlaybackOutput == "Hardware";

rules = { ...
    {'LoadProtocolMenu','LoadProtocolTool','RecentProtocolsMenu'}, hasHost; ...
    {'DuplicateBtn','DuplicateStimTool','DuplicateStimMenu', ...
     'RemoveBtn','RemoveStimTool','RemoveStimMenu', ...
     'CombinationsMenu','CombinationsTool','ExportSignalMenu'}, hasSel; ...
    {'PlayBtn','PlayTool','PlayMenu'}, hasSel && ~obj.PlayAllActive_; ...
    {'PlayAllBtn'}, hasSel || obj.PlayAllActive_; ...
    {'ExportAllMenu','ExportObjsMenu'}, hasItems; ...
    {'OutputDD'}, hasRoute};
for r = 1:size(rules, 1)
    state = matlab.lang.OnOffSwitchState(unlocked && rules{r, 2});
    names = rules{r, 1};
    for k = 1:numel(names)
        f = names{k};
        if isfield(h, f) && ~isempty(h.(f)) && isvalid(h.(f))
            h.(f).Enable = state;
        end
    end
end

if isfield(h, 'OutputDD') && ~isempty(h.OutputDD) && isvalid(h.OutputDD)
    if obj.has_hardware_route_
        h.OutputDD.Tooltip = stimgen.util.tooltip('StimPlayer', 'OutputDD');
    else
        h.OutputDD.Tooltip = stimgen.util.tooltip('StimPlayer', 'OutputDDNoHardware');
    end
end
end
