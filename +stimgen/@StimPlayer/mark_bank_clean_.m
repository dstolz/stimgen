function mark_bank_clean_(obj, ffn)
% mark_bank_clean_(ffn) - Record that the bank matches the file ffn.
obj.BankFile = string(ffn);
obj.Dirty_   = false;
obj.update_title_;
end
