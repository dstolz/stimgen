function apply_remembered_settings_(obj, stimObj)
% apply_remembered_settings_(stimObj) - Start a new stimulus from its type's last settings.
% Each property is applied on its own, so a value that no longer
% validates (a limit that has since changed, a property a newer
% version dropped) leaves that property at its default rather
% than costing the stimulus the rest.
stored = obj.get_remembered_settings_();
key = matlab.lang.makeValidName(class(stimObj));
if ~isfield(stored, key) || ~isstruct(stored.(key))
    return
end
S = stored.(key);
names = obj.remembered_setting_names_(stimObj);
for k = 1:numel(names)
    p = char(names(k));
    if ~isfield(S, p)
        continue
    end
    try
        stimObj.(p) = S.(p);
    catch ME
        stimgen.util.vprintf(3, 'StimPlayer: not applying remembered %s: %s', p, ME.message);
    end
end
end
