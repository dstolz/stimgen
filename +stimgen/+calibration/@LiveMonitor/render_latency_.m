function render_latency_(obj, lat)
% render_latency_(obj, lat)
% Conduction-delay panel: the correlation the delay was chosen from, over the
% record it was measured against.
%
% The waveform panel shows that a click came back; it cannot show why one lag
% was picked over another, and that is the whole content of this measurement.
% Drawn here:
%   - the click/response correlation across every lag searched, normalized to
%     its own peak. A single narrow spike is a delay worth trusting; a broad
%     hump or a second comparable peak is a room, a resonance, or an aliased
%     click train, and the reading should be repeated before it is used;
%   - the probe-region response on the same lag axis, so the arrival the
%     correlation is pointing at is visible as a waveform rather than
%     inferred. Both share the axis because it is anchored to the click
%     onset: lag 0 is the moment the click was played;
%   - the detection floor (10x the region's robust noise) the response peak
%     had to clear, on the response's own axis;
%   - the chosen delay and the search bound as vertical rules. A correlation
%     still climbing at the bound is the signature of a delay larger than the
%     search, which is the one failure the operator can act on.
%
% The title carries the air path the delay implies, at the speed of sound for
% the configured ambient temperature.
%
% Parameters:
%   lat - diagnostics struct from Engine/click_latency_ (the LiveUpdate
%         payload's Latency)

ax = obj.AxTransfer;
if ~isgraphics(ax)
    return
end

% This panel and the transfer curve share one axes. Whatever was on it --
% a live sweep, the static LUTs, a background analysis -- goes, or its lines
% would be read against a lag axis they have nothing to do with.
clear_transfer_(obj);

yyaxis(ax, 'left');
ax.YLimMode = 'auto';
set(ax, XScale='linear', YScale='linear');

hCorr = obj.gobj_('lat_corr', @() line(ax, NaN, NaN, ...
    Color=[0.10 0.25 0.60], LineWidth=1, DisplayName='click correlation'));
set(hCorr, XData=lat.lag_ms, YData=lat.corr);

render_marks_(obj, ax, lat);

ylim(ax, [0 1.15]);
ylabel(ax, 'correlation (norm.)');
xlabel(ax, 'delay after click onset (ms)');
xlim(ax, x_limits_(lat));

render_probe_(obj, ax, lat);

grid(ax, 'on');
title(ax, title_(lat));

hLeg = obj.gobj_('lat_legend', @() legend(ax, Location='northeast', ...
    AutoUpdate='off', FontSize=8));
hLeg.Visible = 'on';
end

% ------------------------------------------------------------------------ %
function clear_transfer_(obj)
% Release every object the panel's other views own. Named rather than
% reset(), which would take the waveform and spectrum panels with it -- this
% runs mid-render, after those two have already drawn.
keys = {'xfer_meas', 'xfer_sd', 'xfer_pending', 'xfer_cur', 'xfer_norm', ...
        'xfer_volt', 'xfer_vmax', 'xfer_vover', 'xfer_legend', ...
        'static_tone', 'static_swept_sine', 'static_click', ...
        'static_tone_v', 'static_swept_sine_v', 'static_click_v', ...
        'static_vmax', 'static_legend', 'bg_legend'};
for k = 1:numel(keys)
    obj.drop_(keys{k});
end
for t = stimgen.calibration.LiveMonitor.WeightingTypes
    obj.drop_(char("wt_" + t));
end
end

% ------------------------------------------------------------------------ %
function render_marks_(obj, ax, lat)
% The chosen delay and the search bound, as vertical rules on the correlation
% axis. One line object each; the delay carries its own label because the
% number it marks is the measurement.
if isfinite(lat.delay_ms)
    h = obj.gobj_('lat_pick', @() line(ax, NaN, NaN, LineStyle='-', ...
        Color=[0.85 0.35 0.05], LineWidth=1, DisplayName='measured delay'));
    set(h, XData=[lat.delay_ms lat.delay_ms], YData=[0 1.15]);

    hT = obj.gobj_('lat_pick_txt', @() text(ax, NaN, NaN, '', ...
        Color=[0.85 0.35 0.05], FontSize=8, ...
        HorizontalAlignment='left', VerticalAlignment='top', Clipping='on'));
    set(hT, Position=[lat.delay_ms, 1.12, 0], ...
        String=sprintf(' %.3f ms', lat.delay_ms));
else
    obj.drop_('lat_pick');
    obj.drop_('lat_pick_txt');
end

if isfinite(lat.bound_ms)
    h = obj.gobj_('lat_bound', @() line(ax, NaN, NaN, LineStyle='--', ...
        Color=[0.55 0.55 0.58], LineWidth=0.75, DisplayName='search bound'));
    set(h, XData=[lat.bound_ms lat.bound_ms], YData=[0 1.15]);
else
    obj.drop_('lat_bound');
end
end

% ------------------------------------------------------------------------ %
function render_probe_(obj, ax, lat)
% Right axis: the probe-region record in volts, on the same lag axis, with the
% floor its peak had to clear. Drawn as a min/max envelope like the waveform
% panel, so a long record costs the same as a short one.
if isempty(lat.probe_v) || ~isfinite(lat.fs) || lat.fs <= 0
    obj.drop_('lat_probe');
    obj.drop_('lat_floor');
    return
end

yyaxis(ax, 'right');
ax.YAxis(2).Visible = 'on';
set(ax, YScale='linear');

[t, v] = stimgen.calibration.LiveMonitor.envelope_decimate_( ...
    lat.probe_v, lat.fs, obj.MaxPoints);
t = t + lat.probe_lag0_ms;

h = obj.gobj_('lat_probe', @() line(ax, NaN, NaN, Color=[0.72 0.72 0.76], ...
    LineWidth=0.5, DisplayName='probe response'));
set(h, XData=t, YData=v);

% The peak-over-noise test the verdict used, drawn where the eye can apply
% it: a response that does not reach this line was rejected for it.
floorV = 10 * max(lat.noise_v, 0);
if isfinite(floorV) && floorV > 0
    hF = obj.gobj_('lat_floor', @() line(ax, NaN, NaN, LineStyle=':', ...
        Color=[0.80 0.10 0.10], LineWidth=0.75, DisplayName='detection floor'));
    set(hF, XData=[t(1) t(end) NaN t(1) t(end)], ...
            YData=[floorV floorV NaN -floorV -floorV]);
else
    obj.drop_('lat_floor');
end

yl = max([abs(v), floorV * 1.2, eps]);
ylim(ax, [-yl yl]);
ylabel(ax, 'response (V)');
ax.YAxis(2).Color = [0.45 0.45 0.45];
yyaxis(ax, 'left');
end

% ------------------------------------------------------------------------ %
function lims = x_limits_(lat)
% Anchored at 0 rather than at the record's start: the negative lags are what
% came back before the click was played, which is noise by definition and only
% worth enough room to see that it is flat.
%
% How far to the right depends on what the panel is being read for. A delay
% that was found is read around its own peak -- the bound is typically ten
% times it, and showing all of that squeezes the arrival and its ringing into
% the first tenth of the panel, where a second peak could not be told from the
% first. A delay that was not found is read against the bound instead, because
% "the correlation was still climbing when the search stopped" is the failure
% the operator can act on, and it is only visible with the bound in frame.
hi = lat.bound_ms;
if ~isfinite(hi) || hi <= 0
    hi = max([lat.lag_ms, 1]);
end
if lat.valid && isfinite(lat.delay_ms) && lat.delay_ms > 0
    hi = min(hi, max(4 * lat.delay_ms, 0.1 * hi));
end
lo = min(-0.05 * hi, lat.probe_lag0_ms / 4);
lims = [lo, hi * 1.05];
end

% ------------------------------------------------------------------------ %
function s = title_(lat)
% Two lines: the reading and what it means in metres, then the evidence it was
% judged on. An invalid measurement says so first -- the curve below it is
% then read as a diagnosis rather than as a result.
if lat.valid
    head = sprintf('Conduction delay  %.3f ms  ·  ~%.2f m of air at %.1f m/s (%.1f °C)', ...
        lat.delay_ms, lat.path_m, lat.speed_of_sound_ms, lat.temperature_c);
elseif lat.at_bound
    head = sprintf('Conduction delay  UNRELIABLE  ·  correlation peaked on the %.1f ms bound', ...
        lat.bound_ms);
else
    head = 'Conduction delay  UNRELIABLE  ·  see the response and its floor';
end

tail = sprintf('peak %s over %s noise  ·  searched 0–%.1f ms', ...
    volts_(lat.peak_v), volts_(lat.noise_v), lat.bound_ms);

s = {head, tail};
end

% ------------------------------------------------------------------------ %
function s = volts_(v)
% Volts in the unit that reads without leading zeros. The noise of a quiet
% probe region is tens of microvolts, which a fixed %.4f states as 0.0000 --
% and the whole verdict is a comparison against it.
if ~isfinite(v)
    s = '--';
elseif abs(v) < 1e-3
    s = sprintf('%.1f µV', v * 1e6);
elseif abs(v) < 0.1
    s = sprintf('%.2f mV', v * 1e3);
else
    s = sprintf('%.3f V', v);
end
end
