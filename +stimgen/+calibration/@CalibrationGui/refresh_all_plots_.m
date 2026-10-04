function refresh_all_plots_(obj)
% Redraw every panel from the Engine's current state, via the
% monitor: the response pair, the lookup tables, the background
% analysis, and the last delay probe. Each clears only its own
% objects now, so there is no ordering between them -- what used
% to matter here was that show_calibration reset the whole
% graphics cache and the response panels had to follow it.
%
% Which tab is on top is left alone. A load or a reset changes
% what the panels hold, not which measurement the operator was
% reading, and every panel is redrawn either way.
obj.Monitor.show_engine_state(obj.Engine);
obj.redraw_transfer_panels_();
obj.sync_display_controls_();
end
