function [y, xClick, schedule, regionEnd] = add_click_probe_(obj, seq, schedule, maxLagN)
% [y, xClick, schedule, regionEnd] = add_click_probe_(obj, seq, schedule, maxLagN)
% Prepend a conduction delay probe click to a tone train.
%
% The probe is embedded in the same excitation record as the bursts it
% will segment, which is the whole point: the delay is then measured from
% the very acquisition it corrects, so nothing rests on consecutive
% play_and_record calls sharing a latency. A run-start probe on separate
% records assumed exactly that, and real hardware broke the assumption --
% acquisition latency can differ with buffer size and record length.
%
% The click sits maxLagN of silence ahead of the train, so its response
% and ring have died away before the first burst whatever the delay, and
% the train's own leading gap then still absorbs the delay for burst 1
% exactly as build_tone_sequence_ laid it out.
%
% Parameters:
%   seq      - (1,:) double unit-amplitude train from build_tone_sequence_
%   schedule - (1,:) struct its burst schedule; onsets are shifted by the
%              probe length in the returned copy
%   maxLagN  - (1,1) double largest delay considered, in samples
%
% Returns:
%   y         - (1,:) double [probe, seq], still unit amplitude
%   xClick    - (1,:) double y-length mask, nonzero only at the click;
%               what click_latency_ correlates against
%   schedule  - the schedule with every onset/gapOnset shifted
%   regionEnd - last sample of the probe region (everything before the
%               first burst), for click_latency_'s validity statistics
%
% See also: stimgen.calibration.Engine/click_latency_,
%           stimgen.calibration.Engine/build_tone_sequence_

fs     = obj.Fs;
clickN = max(round(100e-6 * fs), 1);
padN   = round(0.005 * fs);

probe = zeros(1, padN + clickN + maxLagN);
probe(padN + (1:clickN)) = 1;

y = [probe, seq];

xClick = zeros(1, numel(y));
xClick(padN + (1:clickN)) = 1;

for k = 1:numel(schedule)
    schedule(k).onset    = schedule(k).onset + numel(probe);
    schedule(k).gapOnset = schedule(k).gapOnset + numel(probe);
end

regionEnd = schedule(1).onset - 1;
end
