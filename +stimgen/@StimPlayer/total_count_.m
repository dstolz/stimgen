function n = total_count_(obj)
% n = total_count_() - Presentations a full run makes, summed over the bank.
n = 0;
if ~isempty(obj.StimPlayObjs)
    n = sum(arrayfun(@(sp) sp.StimTotal, obj.StimPlayObjs));
end
end
