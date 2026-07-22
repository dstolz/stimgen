function h = plot(obj, ax)
% h = plot(obj)
% h = plot(obj, ax)
% Plot current Signal vs Time.
% If a valid plot already exists, its data are updated instead of creating a new line.
%
% Parameters:
%   ax - Target axes handle (default: current axes or stored handle).
%
% Returns:
%   h - Line handle.

if nargin < 2 || isempty(ax)
    if ~isempty(obj.plotAxHandle) && isvalid(obj.plotAxHandle)
        ax = obj.plotAxHandle;
    else
        ax = gca;
    end
end

if isempty(obj.Signal)
    obj.call_update_signal_with_variant_cycle_(); % subclass implementation
end

tms = obj.Time * 1e3; % seconds -> milliseconds for display

if ~isempty(obj.plotLineHandle) && isvalid(obj.plotLineHandle) && ...
        isvalid(obj.plotAxHandle) && obj.plotAxHandle == ax
    set(obj.plotLineHandle,'XData',tms,'YData',obj.Signal);
    h = obj.plotLineHandle;
else
    h = plot(ax,tms,obj.Signal);
    obj.plotLineHandle = h;
    obj.plotAxHandle   = ax;
end
grid(ax,'on');
xlabel(ax,'time (ms)');
