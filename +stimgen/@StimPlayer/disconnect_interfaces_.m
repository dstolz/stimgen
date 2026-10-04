function disconnect_interfaces_(obj)
% disconnect_interfaces_() - Return hardware to Idle and clear parameter cache.

obj.PARAMS = struct();
obj.PreviewAdapter_ = [];  % its parameter handles die with the interfaces

if isempty(obj.Host) || obj.Host.connectionState() == "None"
    return
end

try
    obj.Host.setMode("Idle");
catch ME
    stimgen.util.vprintf(0, 1, 'StimPlayer: failed to return interface mode to Idle.');
    stimgen.util.vprintf(0, 1, ME);
end

obj.Host.release();
end
