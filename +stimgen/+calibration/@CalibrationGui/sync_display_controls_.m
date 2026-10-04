function sync_display_controls_(obj)
% Push the display state to every control that mirrors it: the
% View menu, the display toolbar, and the Display section's
% checkbox. One writer for all three, so a change made through any
% of them shows on the others without each callback having to know
% what the others are. Setting a toggle tool's State
% programmatically does not fire its ClickedCallback, so this
% cannot re-enter the handler that called it.
%
% Which measurement is on screen is not among them: the tab strip
% is the only control that says so, and it is its own mirror.
if isempty(obj.Monitor) || ~isvalid(obj.Monitor)
    return
end

set_checked_(obj.GhostMenu,   obj.Monitor.ShowGhost);
set_checked_(obj.VoltageMenu, obj.Monitor.ShowVoltage);
% Checked means every sample, which is the monitor's flag off.
set_checked_(obj.WaveformResMenu, ~obj.Monitor.DecimateWaveforms);

set_tool_state_(obj.ToolGhost,   obj.Monitor.ShowGhost);
set_tool_state_(obj.ToolVoltage, obj.Monitor.ShowVoltage);
set_tool_state_(obj.ToolLogX,    obj.Monitor.LogX);

if ~isempty(obj.TransferLogXCheck) && all(isgraphics(obj.TransferLogXCheck))
    obj.TransferLogXCheck.Value = obj.Monitor.LogX;
end
end
