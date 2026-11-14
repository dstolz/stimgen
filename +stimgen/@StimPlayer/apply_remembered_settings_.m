function apply_remembered_settings_(obj, stimObj)
% apply_remembered_settings_(stimObj) - Start a new stimulus from its type's last settings.
% Each property is applied on its own, so a value that no longer
% validates (a limit that has since changed, a property a newer
% version dropped) leaves that property at its default rather
% than costing the stimulus the rest.
%
% Regeneration is held while they are assigned (StimType.hold_updates)
% and the stimulus is generated once afterwards, and only if a value
% actually changed. Assigned live, every remembered property that
% differed from the class default synthesized the waveform again --
% against settings that were only partly applied.
stored = obj.get_remembered_settings_();
key = matlab.lang.makeValidName(class(stimObj));
if ~isfield(stored, key) || ~isstruct(stored.(key))
    return
end
S = stored.(key);
names = obj.remembered_setting_names_(stimObj);

changed = false;
was = stimObj.hold_updates(true);
release = onCleanup(@() stimObj.hold_updates(was));
for k = 1:numel(names)
    p = char(names(k));
    if ~isfield(S, p)
        continue
    end
    try
        if isequaln(stimObj.(p), S.(p))
            continue   % already at the remembered value: nothing to regenerate for
        end
        stimObj.(p) = S.(p);
        changed = true;
    catch ME
        stimgen.util.vprintf(3, 'StimPlayer: not applying remembered %s: %s', p, ME.message);
    end
end
clear release   % back to the state found; regeneration on property change resumes

if ~changed || was
    return   % nothing to regenerate, or an outer holder regenerates when it is done
end
try
    stimObj.update_signal();
catch ME
    stimgen.util.vprintf(1, 1, 'StimPlayer: %s could not be generated from its remembered settings: %s', ...
        class(stimObj), ME.message);
end
end
