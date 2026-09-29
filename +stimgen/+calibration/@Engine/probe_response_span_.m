function span = probe_response_span_(~, regionEnd, lag, nResponse)
% span = probe_response_span_(obj, regionEnd, lag, nResponse)
% The samples of a tone record that belong to its embedded delay probe, as
% the [first last] pair ResponseProbeSpan holds.
%
% add_click_probe_ puts the probe region -- lead-in, click, and maxLagN of
% silence for its response to arrive and ring down in -- ahead of the
% train, ending at regionEnd in excitation samples. The first burst is
% played at regionEnd + 1 and arrives lag samples later, so everything in
% the response before regionEnd + lag + 1 is the probe's and nothing after
% it is. That is the bound used rather than regionEnd alone: the first lag
% samples after it are still probe silence, not burst.
%
% Parameters:
%   regionEnd - (1,1) double last excitation sample of the probe region,
%               from add_click_probe_
%   lag       - (1,1) double delay the record's windows are cut with, in
%               samples (the probe's own, or the fallback alignment's)
%   nResponse - (1,1) double length of the response record
%
% Returns:
%   span - (1,2) double [1 last]; [] when the arguments cannot place it
%
% See also: stimgen.calibration.Engine/add_click_probe_,
%           stimgen.calibration.LiveUpdate
if ~isfinite(regionEnd) || regionEnd < 1 || nResponse < 1
    span = [];
    return
end
if ~isfinite(lag)
    lag = 0;
end
span = [1, min(regionEnd + max(round(lag), 0), nResponse)];
end
