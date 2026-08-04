function loc = locate_impulse_(~, h, fs, searchLast)
% loc = locate_impulse_(obj, h, fs, searchLast)
% Locate the direct arrival and the usable extent of a circular impulse
% response, and estimate where its decay disappears into the noise floor.
%
% Truncating the decay at the noise floor is not cosmetic: Schroeder
% integration over a record that has already reached the noise floor
% accumulates a constant noise power that flattens the tail of the decay curve
% and biases reverberation time upward without limit as the record lengthens.
% The crossing point is found with the Lundeby iteration (Lundeby et al. 1995).
%
% Parameters:
%   h          - (:,1) double circular impulse response
%   fs         - (1,1) double sample rate in Hz
%   searchLast - (1,1) double last index belonging to the linear response;
%                everything beyond it is harmonic-product wrap-around
%
% Returns:
%   loc - struct with fields
%         peak_index        index of the direct-sound peak
%         onset_index       ISO 3382 start: last point 20 dB below the peak
%         truncation_index  where the decay meets the noise floor
%         window_last       last usable index (truncation, clamped to search)
%         noise_power       mean squared amplitude of the noise floor
%         inr_db            impulse-to-noise ratio, peak block over noise
%         decay_range_db    usable decay range below the direct sound
%         truncated         true when the record ends before the decay does

ENVELOPE_MS  = 0.2;   % smoothing for onset detection; shorter than any reflection,
                      % and short enough that the centred average does not pull
                      % the detected onset appreciably ahead of the true arrival
ONSET_DROP_DB = 20;   % ISO 3382-1 impulse response start criterion
BLOCK_MS     = 10;    % Lundeby block length
MIN_BLOCKS   = 20;
LUNDEBY_ITER = 5;

loc = struct('peak_index', nan, 'onset_index', nan, 'truncation_index', nan, ...
             'window_last', nan, 'noise_power', nan, 'inr_db', nan, ...
             'decay_range_db', nan, 'truncated', false);

h = h(:);
if isempty(h) || fs <= 0
    return
end
searchLast = min(max(round(searchLast), 2), numel(h));
seg = h(1:searchLast);

[pk, peakIdx] = max(abs(seg));
if ~(pk > 0)
    return
end

% Onset from a smoothed energy envelope. Raw |h| swings back through zero every
% half cycle, so a threshold applied to it lands on a zero crossing next to the
% peak rather than on the rise into it.
envWin = max(round(ENVELOPE_MS * 1e-3 * fs), 3);
env = sqrt(movmean(seg .^ 2, envWin));
thresh = env(peakIdx) * 10 ^ (-ONSET_DROP_DB / 20);
onsetIdx = find(env(1:peakIdx) < thresh, 1, 'last');
if isempty(onsetIdx)
    onsetIdx = 1;
else
    onsetIdx = min(onsetIdx + 1, peakIdx);
end

% --- Lundeby: block-average energy, then iterate the fit/crossing pair ---
tail = seg(onsetIdx:end);
nTail = numel(tail);
blockLen = max(round(BLOCK_MS * 1e-3 * fs), 1);
if floor(nTail / blockLen) < MIN_BLOCKS
    blockLen = max(floor(nTail / MIN_BLOCKS), 1);
end
nBlocks = floor(nTail / blockLen);
if nBlocks < 4
    loc.peak_index = peakIdx;
    loc.onset_index = onsetIdx;
    loc.truncation_index = searchLast;
    loc.window_last = searchLast;
    loc.truncated = true;
    return
end

blocks = reshape(tail(1:nBlocks*blockLen), blockLen, nBlocks);
blockPow = mean(blocks .^ 2, 1)';
blockIdx = ((0:nBlocks-1)' + 0.5) * blockLen;   % block centre, samples from onset
blockDb = 10 * log10(max(blockPow, eps));

% Seed the noise estimate from the last 10% of the record.
noiseStart = max(round(0.9 * nBlocks), 1);
noisePow = mean(blockPow(noiseStart:end));
crossIdx = blockIdx(end);

for iter = 1:LUNDEBY_ITER
    noiseDb = 10 * log10(max(noisePow, eps));

    % Fit the decay over the range that is still at least 10 dB clear of the
    % noise; below that the block levels are noise, not decay.
    fitSel = blockDb > noiseDb + 10 & blockIdx <= crossIdx;
    if nnz(fitSel) < 3
        fitSel = blockDb > noiseDb + 5;
    end
    if nnz(fitSel) < 3
        break
    end
    p = polyfit(blockIdx(fitSel), blockDb(fitSel), 1);
    if p(1) >= 0
        break   % no decay to speak of; leave the previous crossing in place
    end

    newCross = (noiseDb - p(2)) / p(1);
    if ~isfinite(newCross)
        break
    end
    crossIdx = min(max(newCross, blockIdx(1)), blockIdx(end));

    % Re-estimate noise from what is safely past the crossing, leaving a
    % margin equal to one decay decade so the estimate is not contaminated.
    margin = crossIdx + abs(10 / p(1));
    noiseSel = blockIdx > margin;
    if nnz(noiseSel) < 3
        noiseSel = blockIdx > blockIdx(max(round(0.9 * nBlocks), 1));
    end
    if nnz(noiseSel) >= 3
        newNoise = mean(blockPow(noiseSel));
        if abs(10*log10(max(newNoise,eps)) - noiseDb) < 0.1 && iter > 1
            noisePow = newNoise;
            break
        end
        noisePow = newNoise;
    end
end

truncIdx = min(onsetIdx + round(crossIdx), searchLast);
loc.peak_index       = peakIdx;
loc.onset_index      = onsetIdx;
loc.truncation_index = max(truncIdx, onsetIdx + blockLen);
loc.window_last      = min(loc.truncation_index, searchLast);
loc.noise_power      = noisePow;
loc.inr_db           = 10 * log10(max(max(blockPow), eps) / max(noisePow, eps));
loc.decay_range_db   = loc.inr_db;
loc.truncated        = loc.window_last >= searchLast - blockLen;
end
