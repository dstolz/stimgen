function set_show_ghost_(obj, tf)
% Overlay of the previous spectrum. Only the response panels need
% redrawing -- the ghost is a spectrum-panel object, and the
% measurement behind the one on screen lives in the monitor's
% cache, which a redraw of any other panel now leaves alone.
obj.Monitor.ShowGhost = tf;
obj.sync_display_controls_();
obj.Monitor.show_engine_state(obj.Engine);
end
