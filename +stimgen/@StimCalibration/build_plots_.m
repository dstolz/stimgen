function build_plots_(obj, parent)
% build_plots_(obj, parent)
% Create the visualization panel and hand its axes to a LiveMonitor.
%
% The layout mirrors LiveMonitor's own standalone window -- waveform and
% spectrum stacked on the left, transfer curve spanning the right -- so the
% embedded view and the detached one are the same picture. The monitor does all
% the drawing; this function only supplies somewhere to draw.
%
% Parameters:
%   parent - uigridlayout whose column 2 the panel occupies

panel = uipanel(parent, 'Title', 'Response');
panel.Layout.Row    = 1;
panel.Layout.Column = 2;
obj.handles.PlotPanel = panel;

g               = uigridlayout(panel, [2 2]);
g.RowHeight     = {'1x', '1x'};
g.ColumnWidth   = {'1x', '1x'};
g.Padding       = [2 2 2 2];
g.RowSpacing    = 8;
g.ColumnSpacing = 14;
obj.handles.PlotGrid = g;

axSignal = uiaxes(g);
axSignal.Layout.Row    = 1;
axSignal.Layout.Column = 1;

axSpectrum = uiaxes(g);
axSpectrum.Layout.Row    = 2;
axSpectrum.Layout.Column = 1;

axTransfer = uiaxes(g);
axTransfer.Layout.Row    = [1 2];
axTransfer.Layout.Column = 2;

for ax = [axSignal axSpectrum axTransfer]
    grid(ax, 'on');
    ax.FontSize = 10;
    ax.Box = 'on';
end

obj.handles.AxSignal   = axSignal;
obj.handles.AxSpectrum = axSpectrum;
obj.handles.AxTransfer = axTransfer;

obj.Monitor = stimgen.calibration.LiveMonitor(obj.Engine, ...
    Axes=[axSignal axSpectrum axTransfer]);
obj.Monitor.LogX = true;
end
