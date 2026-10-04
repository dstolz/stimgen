function update_title_(obj)
% update_title_() - "StimPlayer - <bank file> *" (the star while unsaved).
if isempty(obj.hFig) || ~isvalid(obj.hFig)
    return
end
t = "StimPlayer";
if strlength(obj.BankFile) > 0
    [~, fn, ext] = fileparts(char(obj.BankFile));
    t = t + " - " + string([fn ext]);
end
if obj.Dirty_
    t = t + " *";
end
obj.hFig.Name = char(t);
end
