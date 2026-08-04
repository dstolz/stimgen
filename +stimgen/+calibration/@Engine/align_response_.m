function [lag, atBound] = align_response_(~, x, y, maxLag)
% [lag, atBound] = align_response_(obj, x, y, maxLag)
% Bulk acquisition delay of response y relative to excitation x, in samples.
%
% Both adapters start playback and acquisition from the same trigger, so the
% offset is acoustic propagation plus converter latency: one positive lag
% shared by every burst in the train. Cross-correlating the two records
% recovers it without needing to know the transfer function, which is what
% lets a single recording be cut back into per-burst segments.
%
% The search is restricted to [0, maxLag] so a weak or noisy recording cannot
% lock onto the wrong burst. atBound reports that the peak landed on the edge
% of that range, which usually means the true delay is larger than maxLag.
%
% Parameters:
%   x      - (1,:) double excitation record
%   y      - (1,:) double response record
%   maxLag - (1,1) double largest delay to consider, in samples
%
% Returns:
%   lag     - (1,1) double delay in samples (>= 0)
%   atBound - (1,1) logical true when the peak sits at maxLag

lag     = 0;
atBound = false;

n = min(numel(x), numel(y));
if n < 2 || maxLag < 1
    return
end

[c, lags] = xcorr(y(1:n), x(1:n), maxLag);

causal = lags >= 0;
c      = abs(c(causal));
lags   = lags(causal);

[~, k]  = max(c);
lag     = lags(k);
atBound = lag >= maxLag;
end
