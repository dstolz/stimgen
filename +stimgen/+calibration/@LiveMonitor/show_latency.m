function show_latency(obj, lat)
% show_latency(obj, lat)
% Draw a conduction-delay probe's diagnostics on the transfer panel, outside a
% run.
%
% The off-run counterpart to the "latency" stage of the live stream, and the
% same rendering: a standalone probe is worth looking at whether or not live
% plots happened to be on when it ran, which is exactly the case the live
% stream cannot cover.
%
% Parameters:
%   lat - diagnostics struct from Engine/measure_conduction_delay
arguments
    obj
    lat (1,1) struct
end

if ~isgraphics(obj.AxTransfer) || ~isfield(lat, 'lag_ms') || isempty(lat.lag_ms)
    return
end

obj.render_latency_(lat);
drawnow limitrate;
end
