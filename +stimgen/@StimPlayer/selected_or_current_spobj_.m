function sp = selected_or_current_spobj_(obj)
% sp = selected_or_current_spobj_() - Bank item the GUI is showing.
% Prefers the listbox selection when idle and falls back to the
% playback cursor, so every view of "the current stimulus" (signal
% plot, inspector) agrees.
%
% Returns:
%   sp - stimgen.StimPlay, or [] when the bank is empty

sp = [];
h  = obj.handles;
if isfield(h, 'BankList') && ~isempty(h.BankList) && isvalid(h.BankList) && ...
        ~isempty(h.BankList.Value)
    idx = h.BankList.Value;
    if idx >= 1 && idx <= numel(obj.StimPlayObjs)
        sp = obj.StimPlayObjs(idx);
    end
end
if isempty(sp)
    sp = obj.CurrentSPObj;
end
end
