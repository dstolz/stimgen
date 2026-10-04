function n = presented_count_(obj)
% n = presented_count_() - Presentations so far, summed over the bank.
n = 0;
if ~isempty(obj.StimPlayObjs)
    n = sum(arrayfun(@(sp) sp.StimPresented, obj.StimPlayObjs));
end
end
