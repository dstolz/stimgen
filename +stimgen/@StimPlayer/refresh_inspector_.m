function refresh_inspector_(obj)
% refresh_inspector_() - Push the current selection to the inspector.
% No-op when the inspector window is closed. Failures are logged
% rather than raised: an inspector problem must not break editing.

if isempty(obj.Inspector) || ~isvalid(obj.Inspector) || ~obj.Inspector.is_open()
    return
end
try
    obj.Inspector.refresh();
catch ME
    stimgen.util.vprintf(1, 1, ...
        'StimPlayer: stimulus inspector refresh failed: %s', ME.message);
end
end
