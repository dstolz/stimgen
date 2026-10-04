function idx = select_next_idx(obj)
% select_next_idx() - Pick the next bank index using SerialType scheduling.
% Returns -1 when all bank items have reached their rep target.
%
% Returns:
%   idx - index into StimPlayObjs, or -1 if session complete

if isempty(obj.StimPlayObjs)
    idx = -1;
    return
end

presented = arrayfun(@(sp) sp.StimPresented, obj.StimPlayObjs);
totals    = arrayfun(@(sp) sp.StimTotal,     obj.StimPlayObjs);
remaining = totals - presented;

if all(remaining <= 0)
    idx = -1;
    return
end

candidates = find(remaining > 0);

switch obj.SelectionType
    case "Serial"
        idx = candidates(1);
    case "Shuffle"
        idx = candidates(randperm(numel(candidates), 1));
end
end
