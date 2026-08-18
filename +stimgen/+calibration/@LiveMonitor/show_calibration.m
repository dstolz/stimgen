function show_calibration(obj, eng)
% show_calibration(obj, eng)
% Draw an engine's committed lookup tables: one panel per stimulus where the
% host gave each its own, otherwise every table overlaid on the one panel it
% gave. Either way this is the off-run counterpart to render_transfer_ and
% shares its conventions, so what a completed run leaves on screen looks like
% what the run was drawing a moment earlier.
%
% A panel per stimulus is the better view and the reason the split exists: a
% tone table and a click table have nothing in common but a level axis, and
% overlaying them means plotting hertz and microseconds against one x that is
% neither. It also frees each panel to carry what only its own stimulus
% measures -- the detail axes drawn by show_tone_detail_, show_click_detail_
% and show_swept_detail_ under it.
%
% The overlaid form is kept for a host with one sweep panel, which is the
% monitor's own window and the three-axes host form. There, click durations
% are plotted in microseconds on the same axis as frequency in hertz; the two
% are not commensurable and the legend says so.
%
% Parameters:
%   eng - stimgen.calibration.Engine
arguments
    obj
    eng (1,1) stimgen.calibration.Engine
end

if ~obj.sweeps_share_panel_()
    for p = stimgen.calibration.LiveMonitor.SweepPanels
        obj.show_lut_(eng, p);
    end
    obj.show_tone_detail_(eng);
    obj.show_click_detail_(eng);
    obj.show_swept_detail_(eng);
    return
end

ax = obj.AxTransfer;
if ~isgraphics(ax)
    return
end

% Only this panel's objects: the waveform and spectrum are a different
% record entirely, and where the host gave the background analysis and the
% delay probe panels of their own, those are three measurements that have
% no reason to vanish because the lookup tables were redrawn. It is also
% what frees a caller from having to redraw the response panels afterwards.
obj.clear_for_("transfer");

C = eng.CalibrationData;
if ~eng.IsCalibrated
    stimgen.calibration.LiveMonitor.caption_(ax, ...
        'Calibration transfer curves  (no data)');
    % Left in hertz, and the ticks left alone: there is no curve to place a
    % frequency grid around, and an empty axis relabelled in kHz reads as a
    % measurement of something rather than as the placeholder it is.
    xlabel(ax, 'frequency (Hz) / duration (\mus)');
    ylabel(ax, 'level (dB SPL)');
    grid(ax, 'on');
    return
end

% The unit in each name is the axis's, not the table's: all three are drawn
% against one x whose ticks are written in kHz, and a click duration read on
% that scale is milliseconds.
specs = { ...
    'tone',       'frequency', 1,    '-', [0.10 0.25 0.60], 'tone (kHz)'; ...
    'swept_sine', 'frequency', 1,    '-', [0.20 0.55 0.25], 'swept sine (kHz)'; ...
    'click',      'duration',  1e6,  '-', [0.75 0.30 0.10], 'click (ms)'};

yyaxis(ax, 'left');
% show_background leaves this axis on a manual ylim sized to the noise
% floor; without resetting it here, a calibration curve viewed afterward
% inherits that fixed range and clips against it instead of fitting its
% own data.
ax.YLimMode = 'auto';
allX = [];
allV = [];
freqX = [];   % the frequency-keyed LUTs only, for the weighting overlay
freqY = [];
for k = 1:size(specs, 1)
    key = specs{k, 1};
    lineKey = ['transfer_lut_' key];
    if ~isfield(C, key) || isempty(C.(key))
        obj.drop_(lineKey);
        obj.drop_([lineKey '_v']);
        continue
    end
    S = C.(key);
    x = S.(specs{k, 2})(:).' .* specs{k, 3};
    y = S.spl_db(:).';
    h = obj.gobj_(lineKey, @() line(ax, NaN, NaN, LineStyle='-', ...
        Color=specs{k,5}, LineWidth=1, DisplayName=specs{k,6}));
    set(h, XData=x, YData=y);
    allX = [allX, x];
    allV = [allV, S.voltage(:).'];
    if strcmp(specs{k, 2}, 'frequency')
        freqX = [freqX, x];
        freqY = [freqY, y];
    end
end

ylabel(ax, 'level (dB SPL)');
if obj.LogX
    set(ax, XScale='log');
else
    set(ax, XScale='linear');
end
if numel(allX) > 1
    xlim(ax, [min(allX) * 0.93, max(allX) * 1.07]);
end
% After the limits: the ticks are placed within them, so a caption applied
% earlier would carry the last view's grid.
xlabel(ax, stimgen.calibration.LiveMonitor.frequency_ticks_(ax, ...
    'frequency (Hz) / duration (\mus)'));

% Only the frequency-keyed tables anchor a weighting curve. The click LUT
% shares this axis but its x is a duration, and a weighting evaluated there
% would be a plot of nothing.
obj.render_weighting_("transfer", freqX, freqY);

if obj.ShowVoltage && ~isempty(allV)
    draw_voltage_(obj, ax, eng, C, specs, allX);
    yyaxis(ax, 'left');
end

grid(ax, 'on');
stimgen.calibration.LiveMonitor.caption_(ax, ...
    'Calibration transfer curves', ...
    stimgen.calibration.LiveMonitor.calibration_stamp_(eng));
hLeg = obj.gobj_('transfer_lut_legend', @() legend(ax, Location='southwest', ...
    AutoUpdate='off', FontSize=8));
hLeg.Visible = 'on';
end

% ------------------------------------------------------------------------ %
function draw_voltage_(obj, ax, eng, C, specs, allX)
% Right axis: required drive voltage per LUT, plus the output ceiling.
yyaxis(ax, 'right');
ax.YAxis(2).Visible = 'on';   % show_background hides it; this view owns it again
vals = [];
for k = 1:size(specs, 1)
    key = specs{k, 1};
    if ~isfield(C, key) || isempty(C.(key))
        continue
    end
    S = C.(key);
    x = S.(specs{k, 2})(:).' .* specs{k, 3};
    v = S.voltage(:).';
    ok = isfinite(v) & v > 0;
    h = obj.gobj_(['transfer_lut_' key '_v'], @() line(ax, NaN, NaN, ...
        LineStyle=':', Color=specs{k,5} * 0.6 + 0.4, LineWidth=0.75, ...
        HandleVisibility='off'));
    set(h, XData=x(ok), YData=v(ok));
    vals = [vals, v(ok)];
end

maxV = eng.MaxOutputVoltage;
if ~isempty(vals)
    hMax = obj.gobj_('transfer_lut_vmax', @() line(ax, NaN, NaN, LineStyle='--', ...
        Color=[0.80 0.10 0.10], LineWidth=0.75, HandleVisibility='off'));
    set(hMax, XData=[min(allX) * 0.9, max(allX) * 1.1], YData=[maxV maxV]);

    set(ax, YScale='log');
    lo = max(min([vals, maxV]) * 0.5, eps);
    ylim(ax, [lo, max(max([vals, maxV]) * 2, lo * 10)]);
    ax.YAxis(2).Exponent = 0;
end
ylabel(ax, 'drive (V)');
ax.YAxis(2).Color = [0.45 0.45 0.45];
end
