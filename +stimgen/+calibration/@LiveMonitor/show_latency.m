function show_latency(obj, lat)
% show_latency(obj)     - draw the not-measured placeholder
% show_latency(obj, lat)
% Draw a conduction-delay probe's diagnostics, outside a run.
%
% The off-run counterpart to the "latency" stage of the live stream, and the
% same rendering: a standalone probe is worth looking at whether or not live
% plots happened to be on when it ran, which is exactly the case the live
% stream cannot cover.
%
% Called with nothing, or with a struct carrying no correlation, it draws the
% placeholder instead -- what a host with a panel per view needs before any
% probe has run, since that panel is on screen from the start.
%
% Parameters:
%   lat - diagnostics struct from Engine/measure_conduction_delay
arguments
    obj
    lat = []
end

if ~isgraphics(obj.AxLatency)
    return
end

obj.render_latency_(lat);
drawnow limitrate;
end
