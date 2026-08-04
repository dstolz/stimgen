function show_calibration(obj, eng)
% show_calibration(obj, eng)
% Draw an engine's committed lookup tables on the transfer panel: every LUT it
% holds, overlaid, with the drive voltage each one needs for NormativeValue on
% the right-hand axis and the output ceiling across it.
%
% This is the off-run counterpart to render_transfer_ and shares its axes and
% its conventions, so what a completed run leaves on screen looks like what the
% run was drawing a moment earlier.
%
% Click durations are plotted in microseconds on the same axis as frequency in
% hertz. The two are not commensurable and the legend says so; sharing one axis
% is what lets a single panel serve all three LUTs.
%
% Parameters:
%   eng - stimgen.calibration.Engine
arguments
    obj
    eng (1,1) stimgen.calibration.Engine
end

ax = obj.AxTransfer;
if ~isgraphics(ax)
    return
end

obj.reset();

C = eng.CalibrationData;
if ~eng.IsCalibrated
    title(ax, 'Calibration transfer curves  (no data)');
    xlabel(ax, 'frequency (Hz) / duration (\mus)');
    ylabel(ax, 'level (dB SPL)');
    grid(ax, 'on');
    return
end

specs = { ...
    'tone',       'frequency', 1,    'o-', [0.10 0.25 0.60], 'tone (Hz)'; ...
    'swept_sine', 'frequency', 1,    '^-', [0.20 0.55 0.25], 'swept sine (Hz)'; ...
    'click',      'duration',  1e6,  's-', [0.75 0.30 0.10], 'click (\mus)'};

yyaxis(ax, 'left');
allX = [];
allV = [];
for k = 1:size(specs, 1)
    key = specs{k, 1};
    lineKey = ['static_' key];
    if ~isfield(C, key) || isempty(C.(key))
        obj.drop_(lineKey);
        obj.drop_([lineKey '_v']);
        continue
    end
    S = C.(key);
    x = S.(specs{k, 2})(:).' .* specs{k, 3};
    h = obj.gobj_(lineKey, @() line(ax, NaN, NaN, LineStyle='-', Marker=specs{k,4}(1), ...
        MarkerSize=4, Color=specs{k,5}, MarkerFaceColor=specs{k,5}, ...
        LineWidth=1, DisplayName=specs{k,6}));
    set(h, XData=x, YData=S.spl_db(:).');
    allX = [allX, x];
    allV = [allV, S.voltage(:).'];
end

ylabel(ax, 'level (dB SPL)');
xlabel(ax, 'frequency (Hz) / duration (\mus)');
if obj.LogX
    set(ax, XScale='log');
else
    set(ax, XScale='linear');
end
if numel(allX) > 1
    xlim(ax, [min(allX) * 0.93, max(allX) * 1.07]);
end

if obj.ShowVoltage && ~isempty(allV)
    draw_voltage_(obj, ax, eng, C, specs, allX);
    yyaxis(ax, 'left');
end

grid(ax, 'on');
title(ax, sprintf('Calibration transfer curves  |  %s', stamp_(eng)));
hLeg = obj.gobj_('static_legend', @() legend(ax, Location='southwest', ...
    AutoUpdate='off', FontSize=8));
hLeg.Visible = 'on';
end

% ------------------------------------------------------------------------ %
function draw_voltage_(obj, ax, eng, C, specs, allX)
% Right axis: required drive voltage per LUT, plus the output ceiling.
yyaxis(ax, 'right');
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
    h = obj.gobj_(['static_' key '_v'], @() line(ax, NaN, NaN, LineStyle=':', ...
        Marker='.', MarkerSize=6, Color=specs{k,5} * 0.6 + 0.4, ...
        LineWidth=0.75, HandleVisibility='off'));
    set(h, XData=x(ok), YData=v(ok));
    vals = [vals, v(ok)];
end

maxV = eng.MaxOutputVoltage;
if ~isempty(vals)
    hMax = obj.gobj_('static_vmax', @() line(ax, NaN, NaN, LineStyle='--', ...
        Color=[0.80 0.10 0.10], LineWidth=0.75, HandleVisibility='off'));
    set(hMax, XData=[min(allX) * 0.9, max(allX) * 1.1], YData=[maxV maxV]);

    set(ax, YScale='log');
    lo = max(min([vals, maxV]) * 0.5, eps);
    ylim(ax, [lo, max(max([vals, maxV]) * 2, lo * 10)]);
end
ylabel(ax, 'drive (V)');
ax.YAxis(2).Color = [0.45 0.45 0.45];
end

% ------------------------------------------------------------------------ %
function s = stamp_(eng)
% Age of the calibration, so a stale file is obvious on screen.
t = eng.CalibrationTimestamp;
if isnat(t)
    s = 'timestamp unknown';
    return
end
s = char(datetime(t, Format='dd-MMM-yyyy HH:mm'));
end
