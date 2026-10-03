function save_bank(obj, ffn)
% save_bank(obj)
% save_bank(obj, ffn)
% Serialize the stimulus bank to a .spl file (MATLAB mat format).
%
% With no file, the bank is written to BankFile -- the file it was last
% loaded from or saved to -- without asking. A bank that has no file yet, or
% whose file's folder has gone, is handed to save_bank_as, which asks. On
% success BankFile becomes ffn and the bank is marked saved.
%
% Parameters:
%   ffn - full file path (optional)

if nargin < 2 || isempty(ffn)
    if strlength(obj.BankFile) > 0 && isfolder(fileparts(char(obj.BankFile)))
        ffn = char(obj.BankFile);
    else
        obj.save_bank_as();
        return
    end
end
ffn = char(ffn);

bank = struct();
bank.ISI           = obj.ISI;
bank.SelectionType = obj.SelectionType;
bank.NItems        = numel(obj.StimPlayObjs);
bank.Items         = arrayfun(@(sp) sp.toStruct, obj.StimPlayObjs, 'uni', false);

try
    save(ffn, '-struct', 'bank', '-v7');
    obj.mark_bank_clean_(ffn);
    obj.DataPath = string(fileparts(ffn));
    obj.remember_recent_bank_(ffn);
    stimgen.util.vprintf(1, 'StimPlayer: bank saved to "%s"', ffn);
    obj.set_status_("Saved bank: " + string(ffn));
catch ME
    obj.report_gui_error_(ME, "Save Bank Error", ...
        "StimPlayer could not save the current bank.");
end
end
