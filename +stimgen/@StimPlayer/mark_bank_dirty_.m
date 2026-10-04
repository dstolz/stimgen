function mark_bank_dirty_(obj)
% mark_bank_dirty_() - Record that the bank differs from its file.
% Called by every bank edit: add, open, duplicate, remove, a
% parameter or label edit, Reps/ISI/order/sample rate, applying a
% calibration. Close, Load Bank and Remove ask before losing it.
obj.Dirty_ = true;
obj.update_title_;
end
