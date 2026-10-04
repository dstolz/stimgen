function idx = selected_bank_index_(obj)
% idx = selected_bank_index_() - Listbox selection as a bank index, or [].
idx = [];
h = obj.handles;
if ~isfield(h, 'BankList') || isempty(h.BankList) || ~isvalid(h.BankList) ...
        || isempty(h.BankList.ItemsData) || isempty(h.BankList.Value)
    return
end
v = h.BankList.Value;
if isnumeric(v) && isscalar(v) && v >= 1 && v <= numel(obj.StimPlayObjs)
    idx = v;
end
end
