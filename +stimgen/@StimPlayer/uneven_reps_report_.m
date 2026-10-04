function lines = uneven_reps_report_(obj)
% lines = uneven_reps_report_() - Bank items whose Reps a balanced mode cannot split evenly.
% One "<name>: <detail>" line per affected stimulus, logged as a
% warning too. Empty when every item divides evenly.
lines = strings(0, 1);
for i = 1:numel(obj.StimPlayObjs)
    sp = obj.StimPlayObjs(i);
    for k = 1:numel(sp.StimObj)
        [~, uneven, detail] = obj.reps_per_combination_(sp.Reps, sp.StimObj(k));
        if uneven
            lines(end+1, 1) = string(sp.Name) + ": " + detail; %#ok<AGROW>
        end
    end
end
for i = 1:numel(lines)
    stimgen.util.vprintf(1, 1, 'StimPlayer: uneven reps: %s', char(lines(i)));
end
end
