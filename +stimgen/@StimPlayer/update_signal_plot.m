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
% A stimulus with a Background is drawn embedded in a stretch of it either
% side (as long as the stimulus itself, to a quarter second), on a time axis
% whose zero is still the stimulus onset: a gap or an FM epoch is not
% visible as anything on its own.
if ~isempty(stimObj.Signal)
    % Axis is labelled in ms (see create.m)
    t = stimObj.Time;
    y = stimObj.Signal;
    try
        if ~isempty(stimObj.get_background())
            pad = min(0.25, numel(y) / double(stimObj.Fs));
            [y, t] = stimObj.embedded_signal(pad, pad);
        end
    catch ME
        % The plot must still show the stimulus when its background cannot
        % be built (an invalid band, say); the reason is logged once here
        % and reported in full by whatever plays or exports it.
        stimgen.util.vprintf(1, 1, 'StimPlayer: background not drawn: %s', ME.message);
    end
    set(h.SignalLine, 'XData', t * 1e3, 'YData', y);
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
