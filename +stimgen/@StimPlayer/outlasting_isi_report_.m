function lines = outlasting_isi_report_(obj)
% lines = outlasting_isi_report_() - Bank items longer than the shortest ISI.
% ISI is measured from one onset to the next (timer_runtimefcn triggers one
% ISI after the last trigger), so a stimulus longer than the shortest ISI
% the run can draw is still playing when the next presentation is triggered.
% One "<name>: <longest duration> ms" line per affected bank item, logged as
% a warning too. Empty when every item fits.
%
% A vectorized Duration counts by its longest value. A stimulus whose
% Duration follows something else (a SoundFile's follows the selected file)
% is judged by the Duration it has now.
lines  = strings(0, 1);
isiMin = obj.ISI(1);
for i = 1:numel(obj.StimPlayObjs)
    sp = obj.StimPlayObjs(i);
    longest = 0;
    for k = 1:numel(sp.StimObj)
        d = double(sp.StimObj(k).Duration);
        d = d(isfinite(d));
        if ~isempty(d)
            longest = max(longest, max(d));
        end
    end
    if longest > isiMin
        lines(end+1, 1) = string(sp.Name) + ": " + string(sprintf('%.6g', 1e3 * longest)) + " ms"; %#ok<AGROW>
    end
end
for i = 1:numel(lines)
    stimgen.util.vprintf(1, 1, 'StimPlayer: longer than the shortest ISI (%g ms): %s', ...
        1e3 * isiMin, char(lines(i)));
end
end
