function y = filter_aligned(Hd, x, grpDelay)
% y = stimgen.util.filter_aligned(Hd, x)
% y = stimgen.util.filter_aligned(Hd, x, grpDelay)
% Filter x, undo the filter's group delay, and return a signal the same
% length as x and aligned with it sample for sample.
%
% filter() emits its output delayed by the filter's group delay and stops at
% numel(x), so filtering a stimulus in place both shifts it later in time and
% cuts off as much of its tail - for a 257-tap equalizer at 97.6 kHz that is
% 1.3 ms of onset shift and a truncated offset ramp. Appending grpDelay zeros
% supplies the samples the tail needs, and dropping the first grpDelay output
% samples removes the delay. Leading zeros are not needed: filter() starts
% from zero initial conditions, which is what prepending zeros would express.
%
% Parameters:
%   Hd       - digitalFilter, or any first argument filter() accepts
%   x        - (1,:) double signal
%   grpDelay - (1,1) double delay in samples. Defaults to the mean group
%              delay of Hd, which is exact for a linear-phase FIR. Callers
%              holding a stored value (CalibrationData.filterGrpDelay) should
%              pass it rather than pay for grpdelay() on every stimulus.
%
% Returns:
%   y - (1,:) double, same length as x
%
% Example:
%   C  = stim.Calibration.CalibrationData;
%   y  = stimgen.util.filter_aligned(C.filter, stim.Signal, C.filterGrpDelay);
%
% See also: stimgen.calibration.Engine/design_filter

arguments
    Hd
    x        (1,:) double
    grpDelay (1,1) double {mustBeNonnegative, mustBeFinite} = round(mean(grpdelay(Hd)))
end

gd = round(grpDelay);

if gd == 0 || isempty(x)
    y = filter(Hd, x);
    return
end

yPadded = filter(Hd, [x zeros(1, gd)]);
y = yPadded(gd+1 : gd+numel(x));
end
