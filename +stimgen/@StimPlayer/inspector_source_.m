function [stimObj, label] = inspector_source_(obj)
% [stimObj, label] = inspector_source_() - Source provider for StimInspector.
% Handed to stimgen.StimInspector.set_source_provider so the
% inspector re-resolves the selection on every refresh instead of
% holding a stale stimulus handle.

stimObj = [];
label   = "";

sp = obj.selected_or_current_spobj_();
if isempty(sp)
    return
end

stimObj = sp.CurrentStimObj;
label   = sp.Name;
end
