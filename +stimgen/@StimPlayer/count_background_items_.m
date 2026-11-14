function n = count_background_items_(obj)
% n = count_background_items_() - Bank items whose stimulus has a Background.
% Used by confirm_run_: a Run plays Signal alone, so these would be
% presented without the background they are designed to sit in.
n = 0;
for k = 1:numel(obj.StimPlayObjs)
    try
        s = obj.StimPlayObjs(k).CurrentStimObj;
        if isprop(s, 'Background') && string(s.Background) ~= "None"
            n = n + 1;
        end
    catch
        % An item that cannot be read is not counted; Run reports it itself.
    end
end
end
