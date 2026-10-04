function refresh_listbox_(obj)
% refresh_listbox_() - Rebuild listbox items from current StimPlayObjs.
h = obj.handles;
if ~isfield(h,'BankList') || ~isvalid(h.BankList)
    return
end
if isempty(obj.StimPlayObjs)
    h.BankList.Items = {};
    h.BankList.ItemsData = {};
    obj.sync_control_enable_;
    return
end
items = arrayfun(@(sp) sprintf('%s  [%s]', char(sp.Name), sp.Type), ...
    obj.StimPlayObjs, 'uni', false);
h.BankList.Items = items;
h.BankList.ItemsData = num2cell(1:numel(obj.StimPlayObjs));
obj.sync_control_enable_;
end
