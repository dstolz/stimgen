function [lag, atBound, curve] = align_response_(~, x, y, maxLag)
% [lag, atBound] = align_response_(obj, x, y, maxLag)
% [lag, atBound, curve] = align_response_(obj, x, y, maxLag)
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
%   curve   - struct with the searched correlation itself: lag_samples and
%             value (|correlation|, normalized to its own peak). The evidence
%             behind the chosen lag, for a caller that wants to plot or judge
%             it -- a broad or double-peaked curve is a delay that should not
%             be trusted even where the checks above it pass. Empty arrays
%             when there was nothing to search.

lag     = 0;
atBound = false;
curve   = struct('lag_samples', [], 'value', []);

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

curve.lag_samples = lags(:).';
curve.value       = c(:).' ./ max(c(k), eps);
end
