function build_plots_panel_(obj)
% Create every axes and hand them to a LiveMonitor, which does
% all the drawing -- live during a run, static between runs.
%
% The waveform and the spectrum are always on screen: they are the
% record being acquired right now, and watching a run means
% watching them. Below them, a tab per measurement -- one for each
% stimulus that can be calibrated, then the background noise
% analysis and the conduction delay probe. These used to be one
% panel every view took turns on, which meant measuring a
% background threw away the sweep that was on screen and a delay
% probe threw away both. A panel each keeps them all, and the tab
% strip both selects a view and says which one is up, which is
% what made the toolbar buttons and View-menu items that used to
% do that redundant.
%
% A tab per STIMULUS rather than one holding the tables together,
% because the three are not one measurement drawn three times. A
% tone table is levels against frequency, a click table levels
% against duration -- an axis the other cannot be read on -- and
% a swept sine measures a continuous transfer function of which
% its table is only a summary. So each stimulus gets a plot of
% its own kind and, underneath, what only that stimulus produces:
% per-point distortion and SNR for the two point-by-point sweeps,
% and for the swept sine the deconvolved flatness, group delay
% and impulse response.
panel = uipanel(obj.Grid, Title='Visualization');
panel.Layout.Row = 1;
panel.Layout.Column = 2;

g = uigridlayout(panel, [2 2]);
% The tabs take the larger share: two of the stimulus panels
% stack two plots and the third stacks three, against one plot
% each in the row above.
g.RowHeight = {'1x', '1.4x'};
g.ColumnWidth = {'1x', '1x'};

obj.AxTime = uiaxes(g);
obj.AxTime.Layout.Row = 1;
obj.AxTime.Layout.Column = 1;
grid(obj.AxTime, 'on');

obj.AxSpectrum = uiaxes(g);
obj.AxSpectrum.Layout.Row = 1;
obj.AxSpectrum.Layout.Column = 2;
grid(obj.AxSpectrum, 'on');

obj.PlotTabs = uitabgroup(g, ...
    SelectionChangedFcn=@(~,evt) obj.on_plot_tab_changed_(evt));
obj.PlotTabs.Layout.Row = 2;
obj.PlotTabs.Layout.Column = [1 2];

obj.build_tone_tab_();
obj.build_click_tab_();
obj.build_swept_tab_();
obj.build_filter_test_tab_();

[obj.BackgroundTab, obj.AxBackground] = obj.add_plot_tab_('Background Noise', ...
    'TabBackground');
[obj.LatencyTab, obj.AxLatency] = obj.add_plot_tab_('Conduction Delay', ...
    'TabLatency');

% The struct form: a panel per stimulus, with the detail axes
% under each. By name rather than as an array, because which
% handle is which stops being obvious past about five of them.
obj.Monitor = stimgen.calibration.LiveMonitor(obj.Engine, ...
    Axes=struct( ...
        'signal',        obj.AxTime, ...
        'spectrum',      obj.AxSpectrum, ...
        'tone',          obj.AxTone, ...
        'tone_detail',   obj.AxToneDetail, ...
        'click',         obj.AxClick, ...
        'click_detail',  obj.AxClickDetail, ...
        'swept_sine',    obj.AxSwept, ...
        'swept_detail',  obj.AxSweptDetail, ...
        'swept_impulse', obj.AxSweptImpulse, ...
        'filter_test',   obj.AxFilterTest, ...
        'filter_detail', obj.AxFilterDetail, ...
        'background',    obj.AxBackground, ...
        'latency',       obj.AxLatency));
obj.Monitor.LogX = obj.TransferLogXCheck.Value;
obj.sync_spectrum_units_menu_();
end
