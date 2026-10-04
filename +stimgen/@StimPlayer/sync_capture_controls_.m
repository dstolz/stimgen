function sync_capture_controls_(obj)
% sync_capture_controls_() - Enable capture only when it can run.
% It needs a route to record through, no session holding the
% hardware (running or paused), and no capture already in
% progress. The tooltip says when the route is what is missing,
% since a greyed button cannot.
h = obj.handles;
hasRoute = ~isempty(obj.CaptureAdapter) || ~isempty(obj.Host);
enable   = hasRoute && ~obj.CaptureLocked_ && ~obj.Capturing_;

if hasRoute
    tipText = stimgen.util.tooltip('StimPlayer', 'CaptureStimTool');
else
    tipText = stimgen.util.tooltip('StimPlayer', 'CaptureNoHardware');
end

for f = ["CaptureStimTool", "CaptureStimMenu"]
    if isfield(h, f) && ~isempty(h.(f)) && isvalid(h.(f))
        h.(f).Enable = matlab.lang.OnOffSwitchState(enable);
    end
end
if isfield(h, 'CaptureStimTool') && ~isempty(h.CaptureStimTool) && isvalid(h.CaptureStimTool)
    h.CaptureStimTool.Tooltip = tipText;
end
end
