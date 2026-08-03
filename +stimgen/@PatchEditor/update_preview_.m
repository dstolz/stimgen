function update_preview_(obj)
% update_preview_(obj)
% Plot the selected node's output, or the finished stimulus when nothing is
% selected. Seeing a modulator's own waveform is usually what explains what a
% connection is doing.

ax = obj.h.PreviewAx;
cla(ax);

try
    if obj.selKind == "node" && obj.selIdx >= 1 && obj.selIdx <= numel(obj.geom)
        label = obj.geom(obj.selIdx).Label;
        y     = obj.Patch.node_output(label);
        ttl   = label + " output (pre-level, pre-gate)";
    else
        if isempty(obj.Patch.Signal)
            obj.Patch.update_signal();
        end
        y   = obj.Patch.Signal;
        ttl = "Stimulus output";
    end
catch ME
    text(ax, 0.5, 0.5, ME.message, 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'Color', [0.7 0.1 0.1], 'Interpreter', 'none');
    title(ax, 'Preview unavailable');
    return
end

if isempty(y)
    return
end

% Time axis in ms, matching every other plot in this package.
t = (0:numel(y)-1) ./ double(obj.Patch.Fs) .* 1e3;

% Decimate for drawing only: a 1 s stimulus at 97.6 kHz is 97k points and the
% preview is a couple of hundred pixels wide.
step = max(1, floor(numel(y) / 4000));
plot(ax, t(1:step:end), y(1:step:end), 'LineWidth', 0.5, 'Color', [0.15 0.35 0.65]);

xlabel(ax, 'Time (ms)');
xlim(ax, [0 max(t(end), eps)]);
title(ax, ttl, 'Interpreter', 'none');
grid(ax, 'on');
end
