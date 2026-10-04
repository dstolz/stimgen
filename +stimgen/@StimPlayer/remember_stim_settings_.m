function remember_stim_settings_(obj, stimObj)
% remember_stim_settings_(stimObj) - Keep this stimulus's settings for its type.
% The whole set is snapshotted, not just the property edited:
% some properties change the meaning of others (Tone's
% WindowMethod sets the units of WindowDuration), so a value
% remembered alone can come back describing something else.
% Stored per type in the StimPlayer pref group, so it applies to
% the next Add Stim in this window and to later sessions alike.
% Remembering is a convenience and never interrupts an edit.
try
    key = matlab.lang.makeValidName(class(stimObj));
    S = struct();
    names = obj.remembered_setting_names_(stimObj);
    for k = 1:numel(names)
        v = stimObj.(names(k));
        % Plain values only: handles and objects do not survive
        % a pref round trip meaningfully.
        if isnumeric(v) || islogical(v) || ischar(v) || isstring(v)
            S.(names(k)) = v;
        end
    end
    stored = obj.get_remembered_settings_();
    stored.(key) = S;
    setpref('StimPlayer', 'StimSettings', stored);
catch ME
    stimgen.util.vprintf(3, 'StimPlayer: could not remember settings: %s', ME.message);
end
end
