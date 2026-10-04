function build_display_section_(obj, g)
% Toggles that change only what is drawn. The rest of the drawing
% options are checkable items on the View menu.
obj.ShowLivePlotsCheck = check_row_(g, 1, 'Show Engine Live Plots', ...
    stimgen.util.tooltip('CalibrationGui', 'ShowLivePlots'));
obj.TransferLogXCheck = check_row_(g, 2, 'Transfer Plot Log X-Axis', ...
    stimgen.util.tooltip('CalibrationGui', 'TransferLogX'), ...
    @(src,~) obj.set_transfer_log_x_(src.Value));
obj.TransferLogXCheck.Value = true;
end
