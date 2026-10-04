function accept_dialog_(fig, specs, widgets, errLbl, check)
% OK: validate every field, then the whole set; on the first failure say why
% in the window and leave it open.
vals = struct();
raw  = struct();
for k = 1:numel(specs)
    sp = specs(k);
    r = widgets{k}.Value;
    raw.(sp.key) = r;
    try
        if isempty(sp.validate)
            v = r;
        else
            v = sp.validate(r);
        end
    catch ME
        errLbl.Text = sprintf('%s: %s', sp.label, ME.message);
        return
    end
    if sp.kind == "integer"
        v = round(v);
    end
    vals.(sp.key) = v;
end
if ~isempty(check)
    try
        check(vals);
    catch ME
        errLbl.Text = ME.message;
        return
    end
end
fig.UserData = struct('ok', true, 'vals', vals, 'raw', raw);
uiresume(fig);
end
