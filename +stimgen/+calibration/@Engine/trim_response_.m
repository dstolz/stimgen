function y = trim_response_(~, y)
% y = trim_response_(obj, y)
% Remove trailing buffer padding. Only contiguous trailing zeros are
% stripped; mid-signal zeros (valid zero crossings) are preserved. The
% leading onset is always kept intact.
lastNZ = find(y ~= 0, 1, 'last');
if ~isempty(lastNZ)
    y = y(1:lastNZ);
end
end
