function focus_sweep_panel_(obj, stage)
% Bring up the tab a run is about to fill in. Called by each
% measurement before it starts, so a run begun while another
% panel is on top is watched rather than happening off screen --
% the one cost of tabs, and the one place worth spending a tab
% switch on.
%
% Named by RUN STAGE rather than by tab, and resolved through the
% same map the monitor routes the live updates with: a list kept
% here could disagree with that one, and the failure would be an
% operator watching an empty panel while the curve fills in
% behind another tab. It is also why a lookup-table test names
% itself and lands on the panel of the table it verifies.
arguments
    obj
    stage (1,1) string
end
obj.set_transfer_view_( ...
    stimgen.calibration.LiveMonitor.stage_panel(stage));
end
