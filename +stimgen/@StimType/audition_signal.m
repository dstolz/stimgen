function [y, t] = audition_signal(obj)
% [y, t] = audition_signal(obj)
% The waveform Play auditions.
%
% Signal as it is for a stimulus with no background. With one, the stimulus
% embedded in AuditionPad seconds of it on either side (embedded_signal), so
% what is heard is the stimulus as a presenter that plays the background
% would make it sound -- a gap or an AM epoch is inaudible as anything but a
% burst otherwise. The outer edges are ramped over AuditionRamp seconds so
% the preview itself does not click; those ramps are the preview's, not part
% of the stimulus.
%
% Returns:
%   y - (1,:) double
%   t - (1,:) double time in seconds, 0 at the stimulus onset
%
% See also: embedded_signal, play

AuditionPad  = 0.25;   % seconds of background before and after
AuditionRamp = 0.02;   % seconds, each outer edge

if isempty(obj.Signal)
    obj.call_update_signal_with_variant_cycle_();
end

if ~obj.supports_background_() || obj.Background == "None"
    y = double(obj.Signal);
    t = obj.Time;
    return
end

[y, t] = obj.embedded_signal(AuditionPad, AuditionPad);

nr = min(round(AuditionRamp * double(obj.Fs)), floor(numel(y) / 2));
if nr > 0
    r = sin(pi/2 .* (0:nr-1) ./ nr) .^ 2;
    y(1:nr)         = y(1:nr) .* r;
    y(end-nr+1:end) = y(end-nr+1:end) .* fliplr(r);
end
end
