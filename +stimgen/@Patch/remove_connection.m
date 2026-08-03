function remove_connection(obj, from, to, param)
% remove_connection(obj, from, to, param)
% Remove the connection routing `from` into `to`'s `param`.

g = obj.Graph;
if isempty(g.Connections)
    return
end

drop = string({g.Connections.From})  == string(from) & ...
       string({g.Connections.To})    == string(to)   & ...
       string({g.Connections.Param}) == string(param);

if ~any(drop)
    error('stimgen:Patch:UnknownConnection', ...
        'No connection from "%s" to "%s.%s".', string(from), string(to), string(param));
end

g.Connections(drop) = [];
obj.Graph = g;
end
