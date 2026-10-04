function set_checked_(h, tf)
% Check state of a menu item that may not have been built yet. Guarded rather
% than ordered, so sync_display_controls_ can run at any point in the build.
if ~isempty(h) && all(isgraphics(h))
    h.Checked = matlab.lang.OnOffSwitchState(tf);
end
end
