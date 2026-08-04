function [t, y] = envelope_decimate_(y, fs, maxPoints)
% [t, y] = envelope_decimate_(y, fs, maxPoints)
% Reduce a waveform to at most ~2*maxPoints display points by drawing the
% min/max envelope of each block instead of the samples themselves.
%
% A calibration record can be hundreds of thousands of samples; handing all of
% them to a line object costs more than the measurement did, and the renderer
% throws away the difference anyway. Taking every Nth sample instead would be
% cheaper still, but it aliases a burst's peak away and makes a clipped record
% look clean -- exactly the thing this panel exists to show.
%
% Parameters:
%   y         - (1,:) double waveform
%   fs        - (1,1) double sample rate (Hz)
%   maxPoints - (1,1) double target number of blocks
%
% Returns:
%   t - (1,:) double time in ms
%   y - (1,:) double envelope, two points per block

n = numel(y);
if n <= 2 * maxPoints
    t = (0:n-1) ./ fs .* 1e3;
    y = reshape(y, 1, []);
    return
end

blk = ceil(n / maxPoints);
m   = floor(n / blk);

Y  = reshape(y(1:m*blk), blk, m);
lo = min(Y, [], 1);
hi = max(Y, [], 1);
tb = ((0:m-1) .* blk) ./ fs .* 1e3;

tail = y(m*blk+1 : end);
if ~isempty(tail)
    lo(end+1) = min(tail);
    hi(end+1) = max(tail);
    tb(end+1) = (m * blk) / fs * 1e3;
end

t = reshape([tb; tb], 1, []);
y = reshape([lo; hi], 1, []);
end
