function build_figure_(obj)
% build_figure_(obj)
% Create the standalone monitor window: waveform and spectrum stacked on the
% left, the transfer curve spanning the right. Called only when the caller
% supplied no axes.

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

grid(obj.AxSignal, 'on');
grid(obj.AxSpectrum, 'on');
grid(obj.AxTransfer, 'on');
end
