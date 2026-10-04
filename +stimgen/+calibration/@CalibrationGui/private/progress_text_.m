function s = progress_text_(p)
% s = progress_text_(p)
% Engine.RunProgress as a few words for the status line: "Tone 12/40, pass
% 1/3 (28%)". Empty when there is nothing to say yet.
names = struct('tone', 'Tone', 'click', 'Click', 'swept_sine', 'Swept sine', ...
    'tone_test', 'Tone test', 'click_test', 'Click test', ...
    'filter_test', 'Filter test', 'background', 'Background record', ...
    'reference', 'Reference', 'latency', 'Delay probe');
stage = char(p.stage);
if isempty(stage)
    s = "";
    return
end
if isfield(names, stage)
    what = names.(stage);
else
    what = strrep(stage, '_', ' ');
end
s = string(what);
if p.total > 0 && p.index > 0
    s = s + sprintf(' %d/%d', round(p.index), round(p.total));
end
if p.repeatTotal > 1 && p.repeat > 0
    s = s + sprintf(', pass %d/%d', round(p.repeat), round(p.repeatTotal));
end
if isfinite(p.fraction)
    s = s + sprintf(' (%d%%)', round(100 * min(max(p.fraction, 0), 1)));
end
end
