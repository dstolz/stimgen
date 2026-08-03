function update_output_(obj)
% update_output_(obj)
% Plot the finished stimulus output. Unlike update_preview_, this never
% follows the canvas selection: it always shows the patch's final Signal, so
% the effect of an edit stays visible without deselecting.

ax = obj.h.OutputAx;
cla(ax);

% Duration lives beside this plot, so refresh it here rather than in
% build_inspector_ -- Revert restores the property without going through its
% field, and so does any programmatic write while the window is open.
sc = stimgen.StimType.display_scale(obj.Patch.get_prop_meta(), 'Duration');
obj.h.DurationField.Value = ...
    stimgen.PatchEditor.format_field_value_(obj.Patch.Duration * sc);

try
    if isempty(obj.Patch.Signal)
        obj.Patch.update_signal();
    end
    y = obj.Patch.Signal;
catch ME
    text(ax, 0.5, 0.5, ME.message, 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'Color', [0.7 0.1 0.1], 'Interpreter', 'none');
    title(ax, 'Output unavailable');
    obj.h.PlayBtn.Enable = 'off';
    return
end

if isempty(y)
    obj.h.PlayBtn.Enable = 'off';
    return
end
obj.h.PlayBtn.Enable = 'on';

% Time axis in ms, matching every other plot in this package. Decimate for
% drawing only: a 1 s stimulus at 97.6 kHz is 97k points and the panel is a
% couple of hundred pixels wide.
t = (0:numel(y)-1) ./ double(obj.Patch.Fs) .* 1e3;
step = max(1, floor(numel(y) / 4000));
plot(ax, t(1:step:end), y(1:step:end), 'LineWidth', 0.5, 'Color', [0.15 0.55 0.25]);

xlabel(ax, 'Time (ms)');
xlim(ax, [0 max(t(end), eps)]);
title(ax, 'Stimulus output', 'Interpreter', 'none');
grid(ax, 'on');
end
