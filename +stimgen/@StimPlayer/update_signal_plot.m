function update_signal_plot(obj)
% update_signal_plot(obj) - Refresh the signal plot with the current bank item.
% Developer guide: documentation/stimgen_StimPlayer.md
% Uses the listbox selection when idle; falls back to CurrentSPObj during playback.
%
% This is the single funnel for "the selection changed" in the GUI, so it also
% refreshes the stimulus inspector window when one is open.

h = obj.handles;
if ~isfield(h, 'SignalLine') || ~isvalid(h.SignalLine)
    return
end
ax = obj.handles.SignalAx;

sp = obj.selected_or_current_spobj_();

if isempty(sp)
    set(h.SignalLine, 'XData', nan, 'YData', nan);
    title(ax, '');
    obj.refresh_inspector_;
    return
end

stimObj = sp.CurrentStimObj;
if isempty(stimObj.Signal)
    stimObj.update_signal;
end

if ~isempty(stimObj.Signal)
    % Axis is labelled in ms (see create.m)
    set(h.SignalLine, 'XData', stimObj.Time * 1e3, 'YData', stimObj.Signal);
    summary = stimObj.current_parameter_summary();
    if strlength(summary) > 0
        title(ax, {char(sp.Name), char(summary)});
    else
        title(ax, char(sp.Name));
    end
else
    set(h.SignalLine, 'XData', nan, 'YData', nan);
    title(ax, char(sp.Name));
end

obj.refresh_inspector_;
end
