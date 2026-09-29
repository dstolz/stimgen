function viewer = show_all_combinations(obj, ~, ~)
% viewer = show_all_combinations(obj)
% Open every variant combination of the selected bank item in a new window.
%
% The signal plot shows one combination at a time; this generates all of
% them and draws them side by side in a stimgen.CombinationViewer -- as
% small multiples, overlaid, or stacked, as waveforms or spectra -- with a
% table of the parameter values behind each one. Any combination can be
% taken on into a stimgen.StimInspector from there.
%
% Each call opens a NEW window, so two bank items (or one item before and
% after an edit) can be compared side by side. The viewer works on copies,
% so the bank item keeps its active combination and selection order; its
% Refresh button regenerates from the bank item, picking up later edits.
% Open viewers close with the player.
%
% It is refused while a session is running: generating a large family
% happens on the same thread as the playback timer, and a late trigger is
% worse than a window that opens after the run.
%
% Parameters (both ignored; present so this can be a GUI callback):
%   src, event
%
% Returns:
%   viewer - stimgen.CombinationViewer, or [] when nothing was opened
%
% See also: stimgen.CombinationViewer, stimgen.StimInspector

viewer = [];

if ~isempty(obj.Timer) && isvalid(obj.Timer) && strcmp(obj.Timer.Running, 'on')
    obj.set_status_("Stop the session before opening the combination viewer.");
    return
end

sp = obj.selected_or_current_spobj_();
if isempty(sp)
    obj.show_gui_message_("Select a stimulus bank item to view its combinations.", ...
        "Nothing To Show", "warning");
    return
end

try
    obj.set_computing_(true);
    computing = onCleanup(@() obj.set_computing_(false));
    viewer = stimgen.CombinationViewer(sp.CurrentStimObj, string(sp.Name));
    clear computing

    keep = cellfun(@(v) ~isempty(v) && isvalid(v), obj.CombinationViewers_);
    obj.CombinationViewers_ = [obj.CombinationViewers_(keep), {viewer}];

    obj.set_status_(sprintf('Showing all %d combination(s) of "%s".', ...
        numel(viewer.Combos), sp.Name));
catch ME
    viewer = [];
    obj.report_gui_error_(ME, "Combination Viewer Error", ...
        "StimPlayer could not display the combinations of the selected stimulus.");
end

if nargout == 0, clear viewer; end
end
