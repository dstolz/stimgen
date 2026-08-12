function y = ac_couple_response_(obj, y)
% y = ac_couple_response_(obj, y)
% AC-couple one acquired record, when AcCoupleResponse is set. A pass-through
% otherwise, so every acquisition site can call it unconditionally.
%
% AC coupling here is a zero-phase second-order Butterworth high-pass at
% AcCoupleFrequency. It blocks the input stage's DC offset and, unlike
% subtracting a mean, the slow baseline drift underneath it -- wander over a
% record averages to nearly nothing, so a mean subtraction leaves it in place,
% yet it still inflates the RMS and pulls the cross-correlation that segments a
% burst train.
%
% Zero phase is not optional. Every level is cut from a window placed by
% correlation against the excitation, and the conduction-delay probe reads a
% click's arrival sample directly; a causal high-pass would shift the response
% out from under both.
%
% The mean is removed before filtering rather than left for the filter to take
% off. filtfilt pads only a few filter orders of signal, far shorter than a
% 20 Hz high-pass's ~8 ms settling time, so a record that starts on a large DC
% step would ring for tens of ms at each end -- over exactly the head of the
% record where the delay-probe click sits.
%
% Always applied after trim_response_, never before: the trim finds the buffer
% padding by looking for trailing zeros, which removing any offset would turn
% into a nonzero constant.
%
% What it did is kept in LastDcRemoved_ and LastAcCoupleHz_ (NaN when it did
% nothing), so the waveform panel can state that the option acted on this
% record rather than leaving the user to judge it by eye.
obj.LastDcRemoved_  = nan;
obj.LastAcCoupleHz_ = nan;
if ~obj.AcCoupleResponse || isempty(y)
    return
end

fc = obj.AcCoupleFrequency;

% Empty when there is no filter to be had for this rate and corner -- see
% ac_couple_filter_, which reports why. The record passes through untouched
% rather than half-conditioned by the mean subtraction alone.
d = obj.ac_couple_filter_(obj.Fs, fc);
if isempty(d)
    return
end

dc = mean(y);
y  = y - dc;

% filtfilt needs more than three filter orders of signal. A record shorter
% than that keeps the mean removal alone, which is what AC coupling reduces to
% when there is no room to filter.
if numel(y) <= 3 * filtord(d)
    obj.LastDcRemoved_ = dc;
    stimgen.util.vprintf(2, ...
        'AC coupling: %d-sample record is too short for the %.4g Hz filter; removed %.4g V DC only', ...
        numel(y), fc, dc);
    return
end

y = filtfilt(d, y);
obj.LastDcRemoved_  = dc;
obj.LastAcCoupleHz_ = fc;
stimgen.util.vprintf(3, ...
    'AC coupled response: %.4g Hz high-pass, removed %.4g V DC from %d samples', ...
    fc, dc, numel(y));
end
