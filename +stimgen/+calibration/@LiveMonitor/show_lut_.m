function show_lut_(obj, eng, panel)
% show_lut_(obj, eng, panel)
% One committed lookup table on the panel belonging to its stimulus.
%
% The off-run counterpart to render_transfer_, one stimulus at a time. What
% it draws is the same shape a sweep leaves on screen -- levels against the
% abscissa the table is keyed on, the drive voltage each point needs for the
% normative level on the right-hand axis, and the output ceiling across it --
% but scaled to one table rather than three, so a click table gets an axis in
% milliseconds instead of sharing one with hertz, and each panel's limits are
% its own measurement's.
%
% The subtitle carries what only this stimulus measured: the conduction delay
% a tone sweep resolved per acquisition, the ripple a swept sine deconvolved,
% the level span a click series covered.
%
% Parameters:
%   eng   - stimgen.calibration.Engine
%   panel - "tone" | "click" | "swept_sine"
arguments
    obj
    eng (1,1) stimgen.calibration.Engine
    panel (1,1) string {mustBeMember(panel, ["tone", "click", "swept_sine"])}
end

ax = obj.panel_axes_(panel);
if ~isgraphics(ax)
    return
end
k = @(name) char(panel + "_" + name);

obj.clear_for_(panel);

spec = panel_spec_(panel);

S = [];
C = eng.CalibrationData;
if isstruct(C) && isfield(C, spec.field) && ~isempty(C.(spec.field))
    S = C.(spec.field);
end

yyaxis(ax, 'left');
ax.YLimMode = 'auto';
ylabel(ax, 'level (dB SPL)');
grid(ax, 'on');

if isempty(S)
    % Ticks left alone and the label left in its measured unit: there is no
    % curve to place a grid around, and an empty axis relabelled in kHz
    % reads as a measurement of something rather than as the placeholder it
    % is. The right-hand voltage axis goes with it -- an empty scale beside
    % an empty panel says a voltage was measured and was zero.
    if numel(ax.YAxis) > 1
        yyaxis(ax, 'right');
        ylabel(ax, '');
        ax.YAxis(2).Visible = 'off';
        yyaxis(ax, 'left');
    end
    xlabel(ax, spec.xlabel);
    stimgen.calibration.LiveMonitor.caption_(ax, ...
        sprintf('%s calibration  (not measured)', spec.name));
    return
end

x = S.(spec.xfield)(:).' .* spec.xscale;
y = S.spl_db(:).';
ok = isfinite(x) & isfinite(y);

hLut = obj.gobj_(k('lut_' + spec.field), @() line(ax, NaN, NaN, LineStyle='-', ...
    Marker='.', MarkerSize=8, Color=spec.color, LineWidth=1.25, ...
    DisplayName=spec.trace));
set(hLut, XData=x(ok), YData=y(ok));

draw_normative_(obj, ax, k, eng, x(ok));

if obj.LogX
    set(ax, XScale='log');
else
    set(ax, XScale='linear');
end
if nnz(ok) > 1
    xlim(ax, [min(x(ok)) * 0.93, max(x(ok)) * 1.07]);
end

% A weighting is a curve against frequency; on the click panel's duration
% axis it would be a plot of nothing, and the empty call is what removes one
% left over from a panel that was showing frequencies.
if spec.isFrequency
    obj.render_weighting_(panel, x(ok), y(ok));
else
    obj.render_weighting_(panel, [], []);
end

% After the limits, which the tick grid is placed within.
xlabel(ax, stimgen.calibration.LiveMonitor.frequency_ticks_(ax, spec.xlabel));

if obj.ShowVoltage
    draw_voltage_(obj, ax, k, eng, S, x, ok);
    yyaxis(ax, 'left');
end

stimgen.calibration.LiveMonitor.caption_(ax, ...
    sprintf('%s calibration', spec.name), lut_subtitle_(eng, S, spec, x(ok), y(ok)));
hLeg = obj.gobj_(k('lut_legend'), @() legend(ax, Location='southwest', ...
    AutoUpdate='off', FontSize=8));
hLeg.Visible = 'on';
end

% ------------------------------------------------------------------------ %
function spec = panel_spec_(panel)
% Everything that differs between the three tables: the CalibrationData
% field, the column its abscissa lives in, and how that abscissa is read.
% The x scale factors match the live sweeps' XFactor, so a committed table
% is drawn on the same axis the run that made it was drawn on.
switch panel
    case "click"
        spec = struct('field', "click", 'xfield', "duration", 'xscale', 1e6, ...
            'xlabel', 'click duration (\mus)', 'isFrequency', false, ...
            'name', 'Click', 'trace', 'click LUT', 'color', [0.75 0.30 0.10]);
    case "swept_sine"
        spec = struct('field', "swept_sine", 'xfield', "frequency", 'xscale', 1, ...
            'xlabel', 'frequency (Hz)', 'isFrequency', true, ...
            'name', 'Swept sine', 'trace', 'swept sine LUT', 'color', [0.20 0.55 0.25]);
    otherwise
        spec = struct('field', "tone", 'xfield', "frequency", 'xscale', 1, ...
            'xlabel', 'frequency (Hz)', 'isFrequency', true, ...
            'name', 'Tone', 'trace', 'tone LUT', 'color', [0.10 0.25 0.60]);
end
end

% ------------------------------------------------------------------------ %
function draw_normative_(obj, ax, k, eng, x)
% The level the voltage column was solved for, which is what makes the
% level curve's distance from it readable as headroom rather than as a
% number needing the settings panel to interpret.
v = eng.NormativeValue;
if ~isfinite(v) || isempty(x)
    obj.drop_(k('norm'));
    return
end
h = obj.gobj_(k('norm'), @() line(ax, NaN, NaN, LineStyle=':', ...
    Color=[0.35 0.35 0.35], LineWidth=0.75, DisplayName='normative level'));
set(h, XData=[min(x) * 0.9, max(x) * 1.1], YData=[v v]);
end

% ------------------------------------------------------------------------ %
function draw_voltage_(obj, ax, k, eng, S, x, ok)
% Right axis: the drive each point needs for the normative level, against
% the hardware ceiling. Log-scaled, because across a speaker's roll-off the
% requirement spans decades -- which is where the ceiling starts to matter.
yyaxis(ax, 'right');
ax.YAxis(2).Visible = 'on';

v = S.voltage(:).';
show = ok & isfinite(v) & v > 0;
h = obj.gobj_(k('volt'), @() line(ax, NaN, NaN, LineStyle=':', ...
    Color=[0.45 0.45 0.45], LineWidth=0.9, ...
    DisplayName='drive V for normative'));
set(h, XData=x(show), YData=v(show));

maxV = eng.MaxOutputVoltage;
if ~any(show)
    obj.drop_(k('vmax'));
    obj.drop_(k('vover'));
    ylabel(ax, 'drive (V)');
    return
end

hMax = obj.gobj_(k('vmax'), @() line(ax, NaN, NaN, LineStyle='--', ...
    Color=[0.80 0.10 0.10], LineWidth=0.75, HandleVisibility='off'));
set(hMax, XData=[min(x(show)) * 0.9, max(x(show)) * 1.1], YData=[maxV maxV]);

% Points the rig cannot produce at the normative level. Marked here as well
% as during the run: a table is loaded from a file far more often than it is
% measured, and the file records the same fact.
over = show & v > maxV;
hOver = obj.gobj_(k('vover'), @() line(ax, NaN, NaN, LineStyle='none', ...
    Marker='x', MarkerSize=8, Color=[0.80 0.10 0.10], LineWidth=1.25, ...
    DisplayName='unreachable'));
set(hOver, XData=x(over), YData=v(over));

set(ax, YScale='log');
lo = max(min([v(show), maxV]) * 0.5, eps);
ylim(ax, [lo, max(max([v(show), maxV]) * 2, lo * 10)]);
ax.YAxis(2).Exponent = 0;
ylabel(ax, 'drive (V)');
ax.YAxis(2).Color = [0.45 0.45 0.45];
end

% ------------------------------------------------------------------------ %
function sub = lut_subtitle_(eng, S, spec, x, y)
% Two lines: what the table covers, then what only this stimulus measured.
% Both stay in the smaller subtitle type, which is what keeps a caption
% inside its panel when three of them are on tabs of the same width.
if isempty(y)
    sub = stimgen.calibration.LiveMonitor.calibration_stamp_(eng);
    return
end

if spec.isFrequency
    span = sprintf('%d points, %.3g–%.3g kHz', numel(x), min(x)/1e3, max(x)/1e3);
else
    span = sprintf('%d durations, %.3g–%.3g ms', numel(x), min(x)/1e3, max(x)/1e3);
end
span = sprintf('%s  ·  %.1f–%.1f dB SPL', span, min(y), max(y));

detail = stimgen.calibration.LiveMonitor.calibration_stamp_(eng);
switch spec.field
    case "tone"
        % The delay the embedded probe resolved, and how much it moved
        % between acquisitions -- the spread is the whole reason the probe
        % rides in the record it corrects.
        if isfield(S, 'conduction_delay_s') && isfinite(S.conduction_delay_s)
            detail = sprintf('%s  ·  conduction delay %.2f ms', ...
                detail, S.conduction_delay_s * 1e3);
            if isfield(S, 'conduction_delay_sd_s') && isfinite(S.conduction_delay_sd_s)
                detail = sprintf('%s ± %.2f', detail, S.conduction_delay_sd_s * 1e3);
            end
        end
    case "swept_sine"
        m = metrics_(S);
        if isfield(m, 'magnitude_ripple_db') && isfinite(m.magnitude_ripple_db)
            detail = sprintf('%s  ·  %.1f dB ripple', detail, m.magnitude_ripple_db);
        end
        if isfield(m, 'rt60_s') && isfinite(m.rt60_s)
            detail = sprintf('%s  ·  RT60 %.0f ms', detail, m.rt60_s * 1e3);
        end
    otherwise
        m = metrics_(S);
        if isfield(m, 'snr_db')
            snr = median(m.snr_db(:), 'omitnan');
            if isfinite(snr)
                detail = sprintf('%s  ·  median SNR %.0f dB', detail, snr);
            end
        end
end

sub = {span, detail};
end

% ------------------------------------------------------------------------ %
function m = metrics_(S)
% The metrics struct a table carries, or an empty struct for one written
% before it did. Every reader here asks isfield, so an old table degrades to
% a caption without the extra figure rather than to an error.
m = struct();
if isfield(S, 'metrics') && isstruct(S.metrics)
    m = S.metrics;
end
end
