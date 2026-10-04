function load_capture_settings_(obj)
% load_capture_settings_() - Restore the capture timing last chosen.
% Round-trip latency is a property of the rig, so the lead-in and
% tail that suit one are kept between sessions. Each value is
% applied on its own: one that no longer validates leaves that
% setting at its default rather than costing the rest.
try
    if ~ispref('StimPlayer', 'CaptureSettings')
        return
    end
    s = getpref('StimPlayer', 'CaptureSettings');
catch
    return
end
if ~isstruct(s) || ~isscalar(s)
    return
end
map = {'PreDelay', 'CapturePreDelay'; 'PostDelay', 'CapturePostDelay'; ...
       'Repeats', 'CaptureRepeats'};
for k = 1:size(map, 1)
    if isfield(s, map{k, 1})
        try
            obj.(map{k, 2}) = s.(map{k, 1});
        catch ME
            stimgen.util.vprintf(3, 'StimPlayer: not restoring %s: %s', ...
                map{k, 2}, ME.message);
        end
    end
end
end
