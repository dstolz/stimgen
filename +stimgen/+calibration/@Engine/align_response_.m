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
% The lag is the correlation's first arrival, not its largest peak. The
% response cannot precede the excitation, so the correlation at negative
% lags -- measured just before the excitation -- is what this correlation
% looks like when only noise is present; its largest peak sets the detection
% threshold. The delay is the first causal sample that rises above that
% threshold. Picking the maximum instead would follow the strongest return,
% which a speaker's ringing or a wall reflection can place well after the
% direct arrival -- overstating the delay, and with it the distance derived
% from it. Ringing and reflections are contiguous with the arrival they
% follow, so they sit inside the same run above the threshold and never move
% where that run began.
%
% Two corrections keep that rule honest:
%
%   - a run must clear the threshold by a margin somewhere along it to count
%     as an arrival. The threshold is the extreme of a noise population the
%     causal side samples just as heavily, so a lone sample grazing it is as
%     likely to be noise as signal, and taking it would report an arrival
%     that is entirely early;
%   - the crossing is then advanced by the estimator's own smearing. A
%     correlation starts to rise as soon as x's support first touches the
%     response, which is before the two align; x correlated with itself
%     shows exactly how far before, and that offset is added back. For a
%     click that is one sample less than its width, so the correction is
%     what separates the arrival's true onset from the toe of its lobe.
%
% When nothing rises above the threshold there is no detectable arrival; the
% peak lag is returned so the caller's validity checks can judge (and
% reject) it.
%
% The search is restricted to [0, maxLag] so a weak or noisy recording cannot
% lock onto the wrong burst. atBound reports that the chosen lag landed on the
% edge of that range, which usually means the true delay is larger than maxLag.
%
% Parameters:
%   x      - (1,:) double excitation record
%   y      - (1,:) double response record
%   maxLag - (1,1) double largest delay to consider, in samples
%
% Returns:
%   lag     - (1,1) double delay in samples (>= 0)
%   atBound - (1,1) logical true when the chosen lag sits at maxLag
%   curve   - struct with the searched correlation itself: lag_samples and
%             value (|correlation|, normalized to its own peak) over the full
%             [-maxLag, maxLag] span, and threshold, the pre-excitation peak
%             the arrival had to clear, on the same normalized scale. The
%             evidence behind the chosen lag, for a caller that wants to plot
%             or judge it -- a threshold the causal side barely clears is a
%             delay that should not be trusted even where the checks above it
%             pass. Empty arrays when there was nothing to search.

lag     = 0;
atBound = false;
curve   = struct('lag_samples', [], 'value', [], 'threshold', 0);

n = min(numel(x), numel(y));
if n < 2 || maxLag < 1
    return
end

xn = x(1:n);
[c, lags] = xcorr(y(1:n), xn, maxLag);
c = abs(c);

% Everything at negative lag arrived before the excitation played: noise by
% definition, and the correlation's own noise at that. Its largest peak is
% the level a genuine arrival has to rise above.
noiseCeil = max([c(lags < 0), 0]);

causal = lags >= 0;
cc = c(causal);
cl = lags(causal);

k = first_arrival_(cc, noiseCeil);
if isempty(k)
    % No causal run stands above the pre-excitation correlation: nothing
    % detectable arrived within the search. Fall back to the peak lag rather
    % than fabricate zero, and let the caller's checks reject it.
    [~, k] = max(cc);
else
    k = k + smearing_(xn, maxLag);
    k = min(k, numel(cl));
end
lag     = cl(k);
atBound = lag >= maxLag;

peak = max([c, eps]);
curve.lag_samples = lags(:).';
curve.value       = c(:).' ./ peak;
curve.threshold   = noiseCeil / peak;
end

% ------------------------------------------------------------------------ %
function k = first_arrival_(cc, ceiling)
% Index of the first sample of the first run above ceiling that is an
% arrival rather than a graze. A run has to reach twice the ceiling
% somewhere along it to qualify: the ceiling is the largest of a few
% thousand noise samples, so the causal side produces samples just past it
% on noise alone, and the first of those would date the arrival to wherever
% the noise happened to peak. A real arrival clears it by orders of
% magnitude, so the factor costs nothing to satisfy and rules that out.
% Empty when no run qualifies.
k = [];
above = cc > ceiling;
if ~any(above)
    return
end

% Run boundaries from the transitions of the mask, padded so a run touching
% either end is still bounded.
d      = diff([false, above, false]);
starts = find(d == 1);
stops  = find(d == -1) - 1;

for r = 1:numel(starts)
    if max(cc(starts(r):stops(r))) > 2 * ceiling
        k = starts(r);
        return
    end
end
end

% ------------------------------------------------------------------------ %
function s = smearing_(x, maxLag)
% How many samples before alignment this estimator's correlation already
% rises: the leading extent of x correlated with itself, taken as the
% contiguous run of its peak. Zero when x is a lone impulse; the click's
% width less one for a rectangular click, which is the case every conduction
% delay probe is; a fraction of a period for a tone, whose self-correlation
% dips to nothing every half cycle and so smears far less than its length.
%
% Exact while the probe is short against the response it excites -- the toe
% of the correlation is then a clean copy of x's own, and removing one
% removes the other. A probe long enough to ring against itself has no clean
% toe to remove: the response's oscillation cancels within the overlap, the
% correlation climbs late, and the correction overshoots by a fraction of
% the probe's length. Every probe in this package is 100 us for that reason
% (see measure_conduction_delay and add_click_probe_), which measures exact.
s = 0;
r = abs(xcorr(x, x, maxLag));
[pk, kPk] = max(r);
if ~isfinite(pk) || pk <= 0
    return
end

% Well below any real part of the main lobe -- a rectangular click's
% narrowest overlap is a whole fraction of its peak -- and well above the
% zeros an exactly-zero-padded excitation correlates to.
tol = 1e-6 * pk;
k   = kPk;
while k > 1 && r(k - 1) > tol
    k = k - 1;
end
s = kPk - k;
end
