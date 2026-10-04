function [calObj, source] = capture_calibration_(obj, stimObj)
% [calObj, source] = capture_calibration_(stimObj) - The scale a capture is read on.
% The stimulus's own calibration first -- it is the one that set
% the level being checked -- then the one loaded into the player.
% Only a calibration with measured tables counts: an empty one
% (the default every stimulus is born with) carries the 1 V/Pa
% placeholder sensitivity, and reading a recording through that
% would print numbers that look like dB SPL and are not.
%
% Returns:
%   calObj - stimgen.StimCalibration, or [] when there is none
%   source - (1,1) string, the file it came from, "embedded" for
%            one carried in the bank, "" when there is none
calObj = [];
source = "";
candidates = {stimObj.Calibration, obj.Calibration};
for k = 1:numel(candidates)
    C = candidates{k};
    if isa(C, 'stimgen.StimCalibration') && isscalar(C) && isvalid(C) ...
            && C.Engine.IsCalibrated
        calObj = C;
        break
    end
end
if isempty(calObj)
    return
end
fromPlayer = isa(obj.Calibration, 'stimgen.StimCalibration') ...
    && isscalar(obj.Calibration) && calObj == obj.Calibration;
if fromPlayer && strlength(obj.CalibrationFile) > 0
    source = obj.CalibrationFile;
else
    source = "embedded";
end
end
