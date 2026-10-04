function stored = get_remembered_settings_(~)
% get_remembered_settings_() - Every type's remembered settings, keyed by class.
stored = struct();
try
    if ispref('StimPlayer', 'StimSettings')
        s = getpref('StimPlayer', 'StimSettings');
        if isstruct(s) && isscalar(s)
            stored = s;
        end
    end
catch
    % A pref from another version, or an unreadable one, is the
    % same as none.
end
end
