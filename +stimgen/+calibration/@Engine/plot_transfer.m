function plot_transfer(obj, ~, ~, reset)
% plot_transfer(obj)                  - draw the committed lookup tables
% plot_transfer(obj, type, tableData) - accepted, ignored (see below)
% plot_transfer(obj, '', [], true)    - clear the monitor's panels
%
% Deprecated. The engine no longer draws: it broadcasts LiveUpdate and
% stimgen.calibration.LiveMonitor renders. This entry point forwards to
% whatever monitors are attached -- creating one that owns its own window if
% none is -- and draws the committed LUTs.
%
% The type/tableData arguments existed to overlay a run's partial table. That
% is now carried by LiveUpdate.Table and pushed automatically during a run, so
% they are accepted for call compatibility and otherwise unused.
%
% See also: stimgen.calibration.LiveMonitor.show_calibration
if nargin < 4, reset = false; end

mons = obj.live_monitors_();
if isempty(mons)
    mons = {stimgen.calibration.LiveMonitor(obj)};
end
for k = 1:numel(mons)
    if reset
        mons{k}.reset();
    else
        mons{k}.show_calibration(obj);
    end
end
end
