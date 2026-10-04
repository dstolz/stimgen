function build_footer_(obj, col)
% Pinned below the scrolling stack: during a run these are the only
% controls and readouts that matter, and none may scroll out of
% reach.
foot = uigridlayout(col, [3 2]);
foot.Layout.Row = 2;
foot.Layout.Column = 1;
foot.RowHeight = {30, 22, 24};
foot.ColumnWidth = {'1x', '1x'};
foot.Padding = [0 4 0 4];
foot.RowSpacing = 4;

obj.BtnStop = action_button_(foot, 1, 1, 'Stop', 'BtnStop', ...
    @(~,~) obj.on_stop_());
obj.BtnStop.BackgroundColor = [0.7 0.15 0.15];
obj.BtnStop.FontColor = [1 1 1];
obj.BtnStop.Enable = 'off';

obj.BtnReset = action_button_(foot, 1, 2, 'Reset Calibration', ...
    'BtnReset', @(~,~) obj.on_reset_calibration_());

% Measured by the click probe at the head of every tone
% acquisition, so it moves while a sweep runs -- and a wrong
% reading invalidates the levels the sweep is writing. That makes
% it something to watch during the run rather than a rig fact to
% look up afterwards, which is why the readout sits here with the
% status line while the button that measures it on demand sits in
% the Microphone section with the rest of the workflow.
obj.ConductionDelayLabel = readout_row_(foot, 2, 'Conduction Delay', ...
    'Not measured', stimgen.util.tooltip('CalibrationGui', 'ConductionDelay'));

obj.StatusLabel = uilabel(foot, Text='Ready.', HorizontalAlignment='left');
obj.StatusLabel.Layout.Row = 3;
obj.StatusLabel.Layout.Column = [1 2];
end
