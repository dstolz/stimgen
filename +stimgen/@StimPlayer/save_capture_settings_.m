function save_capture_settings_(obj)
% save_capture_settings_() - Remember the capture timing for the next session.
% Written only when the user changes it in the settings dialog,
% never from the property setters, so a script driving the player
% does not rewrite somebody's preferences.
try
    setpref('StimPlayer', 'CaptureSettings', struct( ...
        'PreDelay',  obj.CapturePreDelay, ...
        'PostDelay', obj.CapturePostDelay, ...
        'Repeats',   obj.CaptureRepeats));
catch ME
    stimgen.util.vprintf(1, 1, 'StimPlayer: could not save capture settings: %s', ME.message);
end
end
