function resolve_params_(obj)
% resolve_params_() - Populate PARAMS from the host.
% Called at Run time. Silently skips missing parameters.
obj.PARAMS = struct;
if isempty(obj.Host)
    return
end
names = obj.RequiredParams_;
for k = 1:numel(names)
    P = obj.Host.findParameter(names{k});
    if ~isempty(P)
        obj.PARAMS.(names{k}) = P;
    end
end
end
