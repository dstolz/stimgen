function update_signal_plot(obj, stimObj, label)
% update_signal_plot(obj) - Refresh the signal plot with the current bank item.
% update_signal_plot(obj, stimObj, label) - Draw stimObj under label instead.
% Developer guide: documentation/stimgen_StimPlayer.md
% Uses the listbox selection when idle; falls back to CurrentSPObj during playback.
%
% This is the single funnel for "the selection changed" in the GUI, so it also
% refreshes the stimulus inspector window when one is open. The second form
% draws a stimulus that is not a bank item -- Play All's pinned copy -- and
% leaves the inspector on the bank item, which that copy does not change.

h = obj.handles;
if ~isfield(h, 'SignalLine') || ~isvalid(h.SignalLine)
    return
end
ax = obj.handles.SignalAx;

if nargin >= 2 && ~isempty(stimObj)
    draw_(h, ax, stimObj, string(label));
    return
end

sp = obj.selected_or_current_spobj_();

if isempty(sp)
    set(h.SignalLine, 'XData', nan, 'YData', nan);
    title(ax, '');
    obj.refresh_inspector_;
    return
end

stimObj = sp.CurrentStimObj;
if isempty(stimObj.Signal)
    obj.set_computing_(true);
    computingCleanup = onCleanup(@() obj.set_computing_(false));
    stimObj.update_signal;
end

draw_(h, ax, stimObj, string(sp.Name));

obj.refresh_inspector_;
end


function draw_(h, ax, stimObj, name)
% The waveform, titled with its name and the parameters it was made from.
if ~isempty(stimObj.Signal)
    % Axis is labelled in ms (see create.m)
    set(h.SignalLine, 'XData', stimObj.Time * 1e3, 'YData', stimObj.Signal);
    summary = stimObj.current_parameter_summary();
    if strlength(summary) > 0
        title(ax, {char(name), char(summary)});
    else
        title(ax, char(name));
    end
else
    set(h.SignalLine, 'XData', nan, 'YData', nan);
    title(ax, char(name));
end
end
