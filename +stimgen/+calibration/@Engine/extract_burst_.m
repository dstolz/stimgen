function [exBurst, rsBurst, rsSteady, steadySpan] = extract_burst_(obj, x, response, s, lag)
% [exBurst, rsBurst, rsSteady, steadySpan] = extract_burst_(obj, x, response, s, lag)
% Cut one scheduled burst out of an excitation/response pair.
%
% Returns the whole burst -- which is what headroom and clipping are judged
% over -- and its steady-state middle, which is what a level is measured from.
% Both are cut from the excitation and, shifted by the bulk acquisition delay,
% from the response, and both are clamped to their records: the trailing gap
% normally covers the shift, but a mis-estimated delay or a short return from
% the adapter must not index past the end.
%
% The ramps are excluded from the steady span so the level estimate is not
% pulled down by the gate, unless doing so would leave too little signal to
% estimate a level from, in which case the whole burst is used.
%
% Shared by calibrate_tones and test_tones so the sweep that builds the LUT
% and the test that checks it segment a recording exactly the same way -- a
% difference here would show up as a level error the LUT never had.
%
% Parameters:
%   x        - (1,:) double excitation record
%   response - (1,:) double response record
%   s        - (1,1) struct one element of a build_tone_sequence_ schedule
%   lag      - (1,1) double bulk acquisition delay in samples
%
% Returns:
%   exBurst    - excitation over the whole burst
%   rsBurst    - response over the whole burst
%   rsSteady   - response over the burst's steady-state middle
%   steadySpan - [first last] index of rsSteady within response
%
% See also: stimgen.calibration.Engine/build_tone_sequence_,
%           stimgen.calibration.Engine/align_response_

fs = obj.Fs;

% Steady-state middle, as offsets relative to the burst onset.
aRel = s.rampSamples;
bRel = s.nsamples - s.rampSamples;

minLen = max(32, ceil(4 * fs / s.frequency));
if bRel - aRel < minLen
    aRel = 0;
    bRel = s.nsamples;
end

[exBurst, rsBurst]     = slice_(x, response, s.onset, 0, s.nsamples, lag);
[~, rsSteady, steadySpan] = slice_(x, response, s.onset, aRel, bRel, lag);
end

% ------------------------------------------------------------------------ %
function [exSeg, rsSeg, rsSpan] = slice_(x, response, onset, aRel, bRel, lag)
% Cut the same half-open span out of the excitation and, shifted by the
% acquisition delay, out of the response. rsSpan is the clamped [first last]
% index of rsSeg within response, which the live update passes to the monitor
% so the analysed window can be drawn on the waveform. It is returned from
% here rather than recomputed by the caller so that the shift and the clamping
% have exactly one definition.
a = onset + aRel;
b = onset + bRel - 1;

exSeg  = x(max(a,1) : min(b, numel(x)));
rsSpan = [max(a + lag, 1), min(b + lag, numel(response))];
rsSeg  = response(rsSpan(1) : rsSpan(2));
end
