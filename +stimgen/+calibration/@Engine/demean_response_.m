function y = demean_response_(obj, y)
% y = demean_response_(obj, y)
% Remove the DC offset from one acquired record, when DemeanResponse is set.
% A pass-through otherwise, so every acquisition site can call it
% unconditionally.
%
% Always applied after trim_response_, never before: the trim finds the
% buffer padding by looking for trailing zeros, which demeaning would turn
% into a nonzero constant.
%
% The offset it removed is kept in LastDcRemoved_ (NaN when it removed
% nothing), so the waveform panel can state that the option acted on this
% record rather than leaving the user to judge it by eye.
obj.LastDcRemoved_ = nan;
if ~obj.DemeanResponse || isempty(y)
    return
end
dc = mean(y);
obj.LastDcRemoved_ = dc;
y = y - dc;
stimgen.util.vprintf(3, 'Demeaned response: removed %.4g V DC from %d samples', ...
    dc, numel(y));
end
