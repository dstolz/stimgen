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
% The title carries the reading (red when unreliable); the subtitle carries
% the air path the delay implies, at the speed of sound for the configured
% ambient temperature, and the evidence the verdict was judged on.
%
% Parameters:
%   lat - diagnostics struct from Engine/click_latency_ (the LiveUpdate
%         payload's Latency), or [] for the not-measured placeholder

ax = obj.AxLatency;
if ~isgraphics(ax)
    return
end

% Sharing one axes with the transfer curve, whatever was on it -- a live
% sweep, the static LUTs, a background analysis -- goes, or its lines would
% be read against a lag axis they have nothing to do with. On a panel of its
% own only this view's own leftovers go.
obj.clear_for_("latency");

if isempty(lat) || ~isfield(lat, 'lag_ms') || isempty(lat.lag_ms)
    % A panel of its own is on screen before any probe has run, so it has to
    % say that rather than sit blank and read as a broken plot.
    hide_probe_axis_(ax);
    set(ax, XScale='linear', YScale='linear');
    grid(ax, 'on');
    xlabel(ax, 'delay after click onset (ms)');
    ylabel(ax, 'correlation (norm.)');
    stimgen.calibration.LiveMonitor.caption_(ax, ...
        'Conduction delay  (not measured)');
    return
end

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
[head, sub, headColor] = latency_caption_(lat);
stimgen.calibration.LiveMonitor.caption_(ax, head, sub, headColor);

% Placed automatically, unlike the fixed corners the other panels use: where
% this one is empty depends on where the arrival landed, and the arrival can
% be anywhere from a tenth of the way across to most of it. A probe draws
% this panel once, so the search costs nothing that a sweep would notice.
hLeg = obj.gobj_('lat_legend', @() legend(ax, Location='best', ...
    AutoUpdate='off', FontSize=8));
hLeg.Visible = 'on';
end

% ------------------------------------------------------------------------ %
function hide_probe_axis_(ax)
% Retire the right-hand probe-response axis for the placeholder. The axis
% outlives the traces on it, so clearing those alone would leave an empty
% scale labelled in volts with nothing drawn against it.
if ~isgraphics(ax) || numel(ax.YAxis) < 2
    return
end
yyaxis(ax, 'right');
ylabel(ax, '');
ax.YAxis(2).Visible = 'off';
yyaxis(ax, 'left');
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
% floor its peak had to clear. Drawn under the same DecimateWaveforms policy
% as the waveform panel, so the two records read alike.
if isempty(lat.probe_v) || ~isfinite(lat.fs) || lat.fs <= 0
    obj.drop_('lat_probe');
    obj.drop_('lat_floor');
    return
end

yyaxis(ax, 'right');
ax.YAxis(2).Visible = 'on';
set(ax, YScale='linear');

[t, v] = obj.waveform_xy_(lat.probe_v, lat.fs, lat.probe_lag0_ms);

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

% To the left, a fixed fraction of what is shown to the right -- never the
% probe region's own start, which begins a whole search bound before the
% click and on a short delay would take most of the panel to show noise.
% It is still bounded by that start, since there is no record to its left.
lo = max(-0.15 * hi, lat.probe_lag0_ms);
lims = [lo, hi * 1.05];
end

% ------------------------------------------------------------------------ %
function [head, sub, headColor] = latency_caption_(lat)
% Title: the reading, or the verdict when there is none -- red, so an
% unreliable probe cannot be mistaken for a measurement. Subtitle: what the
% reading means in metres, then the evidence it was judged on; an invalid
% one carries its diagnosis there instead, and the curve below is read as a
% diagnosis rather than as a result.
if lat.valid
    head = sprintf('Conduction delay  %.3f ms', lat.delay_ms);
    headColor = [0 0 0];
    % Temperature in °F to match the setting it came from, which the
    % CalibrationGui takes in Fahrenheit; the payload carries Celsius,
    % the unit the Engine works in.
    line1 = sprintf('~%.2f m of air at %.1f m/s (%.1f °F)', ...
        lat.path_m, lat.speed_of_sound_ms, lat.temperature_c * 9/5 + 32);
elseif lat.at_bound
    head = 'Conduction delay  \bfUNRELIABLE\rm';
    headColor = [0.75 0 0];
    line1 = sprintf('correlation peaked on the %.1f ms search bound', lat.bound_ms);
else
    head = 'Conduction delay  \bfUNRELIABLE\rm';
    headColor = [0.75 0 0];
    line1 = 'see the response and its detection floor';
end

line2 = sprintf('peak %s over %s noise  ·  searched 0–%.1f ms', ...
    volts_(lat.peak_v), volts_(lat.noise_v), lat.bound_ms);

sub = {line1, line2};
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
