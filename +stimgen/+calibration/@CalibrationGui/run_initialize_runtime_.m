function run_initialize_runtime_(obj, protocolPath)
arguments
    obj
    protocolPath (1,:) char = ''
end
obj.assert_host_();

if isempty(protocolPath)
    [fn, pn] = uigetfile( ...
        {'*.eprot;*.prot;*.json', 'Protocol files (*.eprot, *.prot, *.json)'}, ...
        'Load Protocol For Calibration');
    if isequal(fn, 0)
        obj.set_status_('Runtime initialization cancelled.', false);
        return
    end
    protocolPath = fullfile(pn, fn);
elseif ~isfile(protocolPath)
    obj.remove_recent_protocol_(protocolPath);
    obj.set_status_(sprintf('Recent protocol not found: %s', protocolPath), true);
    return
end

obj.Host.loadProtocol(protocolPath);
obj.Host.connect();
obj.Host.setMode("Preview");

obj.set_adapter(obj.Host.calibrationAdapter());
obj.add_recent_protocol_(protocolPath);
[~, fn, ext] = fileparts(protocolPath);
obj.set_status_(sprintf('Runtime initialized from protocol: %s%s', fn, ext), false);
end
