function edit_graph(obj)
% edit_graph(obj)
% Open the patch editor on this stimulus.
%
% Bound to the "Edit Graph..." button in propMeta. Runs modally, because
% StimPlayer rebuilds the whole parameter panel after a button action
% (@StimPlayer/on_bank_selection_changed.m, run_action_) and the new node set
% has to exist by the time it does.

stimgen.PatchEditor(obj);
end
