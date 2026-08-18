function build_figure_(obj)
% build_figure_(obj)
% Create the standalone monitor window: waveform and spectrum stacked on the
% left, the transfer curve spanning the right. Called only when the caller
% supplied no axes.
%
% Every transfer-family view shares that right-hand panel, one at a time --
% the plain-figure equivalent of the three-axes host form, and the reason
% show_calibration overlays the three lookup tables here rather than drawing
% one plot per stimulus. A host that wants them apart supplies its own axes;
% CalibrationGui gives each stimulus a tab.

obj.Figure_ = figure( ...
    Name='Calibration Live Monitor', ...
    NumberTitle='off', ...
    Color='w', ...
    Position=[100 100 1180 660]);
obj.OwnsFigure = true;

tl = tiledlayout(obj.Figure_, 2, 2, TileSpacing='compact', Padding='compact');

obj.AxSignal = nexttile(tl, 1);
obj.AxSpectrum = nexttile(tl, 3);
obj.AxTransfer = nexttile(tl, 2, [2 1]);
obj.AxBackground = obj.AxTransfer;
obj.AxLatency    = obj.AxTransfer;
obj.AxTone       = obj.AxTransfer;
obj.AxClick      = obj.AxTransfer;
obj.AxSweptSine  = obj.AxTransfer;
obj.AxFilterTest = obj.AxTransfer;

grid(obj.AxSignal, 'on');
grid(obj.AxSpectrum, 'on');
grid(obj.AxTransfer, 'on');
end
