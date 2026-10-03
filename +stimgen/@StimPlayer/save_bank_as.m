function save_bank_as(obj)
% save_bank_as(obj)
% Ask for a file name, then save the stimulus bank there (save_bank).
% The dialog opens on BankFile when the bank has one, else on
% StimBank.spl in DataPath. Cancelling the dialog saves nothing and leaves
% the bank's unsaved state as it was.

if strlength(obj.BankFile) > 0
    defaultFile = char(obj.BankFile);
else
    defaultFile = fullfile(char(obj.DataPath), 'StimBank.spl');
end

[fn, pn] = uiputfile('*.spl', 'Save Stimulus Bank As', defaultFile);
if isequal(fn, 0)
    return
end
obj.save_bank(fullfile(pn, fn));
end
