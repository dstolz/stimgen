function show_capture_inspector_(obj, rec, label)
% show_capture_inspector_(rec, label) - Show a capture in its own inspector.
% One per player, reused for each new capture and kept apart from
% the inspector that follows the bank selection: that one shows
% what will be played, this one what came back.
insp = obj.CaptureInspector_;
if isempty(insp) || ~isvalid(insp) || ~insp.is_open()
    insp = stimgen.StimInspector();
    obj.CaptureInspector_ = insp;
end
insp.set_source(rec, label);
insp.show();
end
