function build_ui_(obj)
obj.Figure = uifigure( ...
    Name='Stim Calibration', ...
    Position=[120 60 1360 820], ...
    CloseRequestFcn=@(src,~) obj.on_close_(src), ...
    DeleteFcn=@(~,~) obj.on_figure_deleted_());

obj.Grid = uigridlayout(obj.Figure, [1 2]);
obj.Grid.ColumnWidth = {380, '1x'};
obj.Grid.RowHeight = {'1x'};

obj.build_menu_();
obj.build_toolbar_();
obj.build_controls_panel_();
obj.build_plots_panel_();

% Last, because it writes to all three of them and the monitor
% holding the state it writes is created by the last call above.
obj.sync_display_controls_();
end
