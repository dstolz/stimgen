function y = zero_phase_bandpass_(~, x, filt)
% y = zero_phase_bandpass_(obj, x, filt)
% Zero-phase IIR bandpass filtering, padded to the filter's own settling
% time rather than filtfilt's default.
%
% filtfilt seeds its forward/backward initial conditions from a short
% reflection of the input's own edge samples (about 3x the filter order),
% which assumes the edge already looks like settled in-band content. A
% regularized swept-sine deconvolution instead starts with broadband
% regularization noise -- not silence, not a settled tone -- so that
% reflection is a poor continuation. A high-Q section (pole radius near 1,
% as any narrow octave-band or wide-ratio calibration filter has) then rings
% far longer than filtfilt's default pad before settling, and the leftover
% transient lands in the visible output: a spurious onset that can dwarf the
% real impulse response by several times.
%
% Zero-padding by an amount tied to the slowest pole's own decay, then
% discarding the pad after filtering, removes the dependence on what the
% real edge content looks like -- at the cost of two extra runs of a filter
% already applied twice, which is negligible next to everything else a
% calibration run does.
%
% Parameters:
%   x    - (:,1) double signal to filter
%   filt - digitalFilter, IIR bandpass from designfilt('bandpassiir', ...)
%
% Returns:
%   y - (:,1) double zero-phase filtered signal, same length as x

TARGET_ATTEN_DB = 100;   % pad long enough for the slowest pole to fall this far
MIN_PAD_SAMPLES = 32;    % floor for a well-damped filter, so padding is never skipped

x = x(:);

sos = filt.Coefficients;
poleRadius = 0;
for i = 1:size(sos, 1)
    poleRadius = max(poleRadius, max(abs(roots(sos(i, 4:6)))));
end

if poleRadius > 0 && poleRadius < 1
    padLen = ceil(log(10 ^ (-TARGET_ATTEN_DB / 20)) / log(poleRadius));
else
    padLen = MIN_PAD_SAMPLES;
end
padLen = max(padLen, MIN_PAD_SAMPLES);

% filtfilt needs more samples than its own pad; if x is too short to give the
% slowest pole room to settle, padding-and-trimming can't be done safely, so
% fall back to a plain filtfilt rather than fabricate an inadequate pad.
maxPad = floor((numel(x) - 1) / 2);
if padLen > maxPad
    stimgen.util.vprintf(2, ...
        'zero_phase_bandpass_: signal too short for a %d-sample settling pad (have %d); using filtfilt default.', ...
        padLen, maxPad);
    y = filtfilt(filt, x);
    return
end

xp = [zeros(padLen, 1); x; zeros(padLen, 1)];
yp = filtfilt(filt, xp);
y = yp(padLen + 1 : padLen + numel(x));
end
