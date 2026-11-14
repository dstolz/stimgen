function bank = bank_struct_(obj)
% bank = bank_struct_() - The bank as the struct a .spl file holds.
% The one layout of a serialized bank: save_bank writes it, and a run
% snapshots it at its start so the presentation log can say what bank the
% trials were drawn from even if the bank is edited afterwards.
%
% Returns:
%   bank - struct: ISI, SelectionType, NItems, Items (one StimPlay.toStruct
%          per bank item, in bank order)
bank = struct();
bank.ISI           = obj.ISI;
bank.SelectionType = obj.SelectionType;
bank.NItems        = numel(obj.StimPlayObjs);
bank.Items         = arrayfun(@(sp) sp.toStruct, obj.StimPlayObjs, 'uni', false);
end
