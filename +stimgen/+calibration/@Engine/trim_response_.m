function y = trim_response_(obj, y, trimOnset)
% y = trim_response_(obj, y)
% y = trim_response_(obj, y, trimOnset)
% Remove trailing buffer padding and, by default, trim the leading onset
% window (acoustic propagation delay plus transducer/mic onset transient).
% Only contiguous trailing zeros are stripped; mid-signal zeros
% (valid zero crossings) are preserved.
%
% Parameters:
%   trimOnset - (1,1) logical, keep the leading onset window when false
%               (default true). Swept-sine deconvolution needs the intact
%               record: the onset carries the start of the sweep, so
%               discarding it biases the low-frequency end of the measured
%               transfer function.
if nargin < 3, trimOnset = true; end

lastNZ = find(y ~= 0, 1, 'last');
if ~isempty(lastNZ)
    y = y(1:lastNZ);
end

if ~trimOnset
    return
end

% Clip leading OnsetIgnoreDuration ms so RMS/peak/spectral measurements
% are not skewed by propagation delay or onset transient ringing.
trimSamps = round(obj.OnsetIgnoreDuration * 1e-3 * obj.Fs);
if numel(y) > trimSamps
    y = y(trimSamps + 1 : end);
end
end
