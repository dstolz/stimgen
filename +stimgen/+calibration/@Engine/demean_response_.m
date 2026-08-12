function y = demean_response_(obj, y)
% y = demean_response_(obj, y)
% Remove the DC offset from one acquired record, when DemeanResponse is set.
% A pass-through otherwise, so every acquisition site can call it
% unconditionally.
%
% Always applied after trim_response_, never before: the trim finds the
% buffer padding by looking for trailing zeros, which demeaning would turn
% into a nonzero constant.
if ~obj.DemeanResponse || isempty(y)
    return
end
y = y - mean(y);
end
