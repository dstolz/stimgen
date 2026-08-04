function d = decay_times_(~, h, fs, noisePower)
% d = decay_times_(obj, h, fs, noisePower)
% Reverberation times from one already-truncated impulse response segment.
%
% Builds the Schroeder energy decay curve, EDC(t) = 10*log10(int_t^T h^2 dt),
% then fits straight lines to the standard level ranges and extrapolates each
% to a full 60 dB decay. Backward integration is used rather than a direct fit
% to the squared response because the integral is the ensemble average of the
% decay, which removes the interference ripple that makes a raw h^2 fit
% unrepeatable.
%
% Chu's correction subtracts the mean noise power from h^2 before integrating.
% Without it the tail of the EDC bends upward and every fitted slope is too
% shallow, i.e. every reverberation time too long.
%
% Parameters:
%   h          - (:,1) double impulse response from onset to the noise crossing
%   fs         - (1,1) double sample rate in Hz
%   noisePower - (1,1) double mean squared noise amplitude, NaN to skip Chu
%
% Returns:
%   d - struct with fields
%       edc_db, edc_time_s  decimated decay curve for storage/plotting
%       edt_s, t20_s, t30_s decay times extrapolated to 60 dB
%       edt_r2, t20_r2, t30_r2  regression quality of each fit
%       rt60_s, rt60_source best available estimate and where it came from
%       nonlinearity_pct    ISO 3382 curvature, 100*(T30/T20 - 1)
%       usable_range_db     decay range the curve actually spans

EDC_STORE_POINTS = 2048;   % decimation target; the curve is for plotting

d = struct('edc_db', [], 'edc_time_s', [], ...
           'edt_s', nan, 't20_s', nan, 't30_s', nan, ...
           'edt_r2', nan, 't20_r2', nan, 't30_r2', nan, ...
           'rt60_s', nan, 'rt60_source', "none", ...
           'nonlinearity_pct', nan, 'usable_range_db', nan);

h = h(:);
n = numel(h);
if n < 16 || fs <= 0
    return
end

e = h .^ 2;
if isfinite(noisePower) && noisePower > 0
    e = e - noisePower;
end
e = max(e, 0);

% Schroeder backward integration, normalized so the curve starts at 0 dB.
edc = flipud(cumsum(flipud(e)));
total = edc(1);
if ~(total > 0)
    return
end
edcDb = 10 * log10(max(edc / total, eps));
t = (0:n-1)' / fs;

d.usable_range_db = -edcDb(find(edcDb > -Inf, 1, 'last'));

[d.edt_s, d.edt_r2] = fit_decay_(t, edcDb,  0, -10);
[d.t20_s, d.t20_r2] = fit_decay_(t, edcDb, -5, -25);
[d.t30_s, d.t30_r2] = fit_decay_(t, edcDb, -5, -35);

% Prefer the widest fit that succeeded: a wider level range averages over more
% of the decay and is less sensitive to early reflections.
if isfinite(d.t30_s)
    d.rt60_s = d.t30_s;  d.rt60_source = "T30";
elseif isfinite(d.t20_s)
    d.rt60_s = d.t20_s;  d.rt60_source = "T20";
elseif isfinite(d.edt_s)
    d.rt60_s = d.edt_s;  d.rt60_source = "EDT";
end

if isfinite(d.t20_s) && isfinite(d.t30_s) && d.t20_s > 0
    d.nonlinearity_pct = 100 * (d.t30_s / d.t20_s - 1);
end

step = max(ceil(n / EDC_STORE_POINTS), 1);
d.edc_db = edcDb(1:step:end);
d.edc_time_s = t(1:step:end);
end


function [rt, r2] = fit_decay_(t, edcDb, upperDb, lowerDb)
% Least-squares slope over one level range, extrapolated to a full 60 dB.
rt = nan;
r2 = nan;

iStart = find(edcDb <= upperDb, 1, 'first');
iStop  = find(edcDb <= lowerDb, 1, 'first');
if isempty(iStart) || isempty(iStop) || iStop - iStart < 8
    return   % decay never reaches this range, or does so too fast to fit
end

tt = t(iStart:iStop);
yy = edcDb(iStart:iStop);
p = polyfit(tt, yy, 1);
if p(1) >= 0
    return
end

rt = -60 / p(1);   % fitted slope in dB/s -> time for a 60 dB decay
resid = yy - polyval(p, tt);
ssTot = sum((yy - mean(yy)) .^ 2);
if ssTot > 0
    r2 = 1 - sum(resid .^ 2) / ssTot;
end
end
