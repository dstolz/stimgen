function render_signal_(obj, d)
% render_signal_(obj, d)
% Waveform panel: the recorded response over time, the excitation behind it as
% a shaded area on its own voltage axis, the span the measurement was actually
% computed over, and the converter's clipping limits when the record comes near
% them.
%
% The two waveforms are volts on both sides of the rig and nowhere near the
% same size -- a drive of a volt or two returns millivolts at the microphone --
% so the excitation carries the right-hand axis and is read in the volts it was
% actually played at. Scaling it into the response's axis, as this panel once
% did, drew the shape but made the level unreadable, and the drive voltage is
% half of what a headroom or clipping question is about.
%
% The span shading is the point of this panel. A level that looks wrong is
% almost always a segmentation problem -- a burst measured over its ramp, or a
% response pushed past the analysis window by acquisition delay -- and that is
% only visible when the measured span is drawn on the waveform itself.
%
% Every object is created with line()/patch(), which add to the axes without
% clearing them, so this panel can share axes with a host GUI's own plots.

ax = obj.AxSignal;
y  = d.Response;
fs = d.Fs;

if isempty(y) || fs <= 0
    obj.drop_('sig_span');
    obj.drop_('sig_exc');
    obj.drop_('sig_exc_fill');
    obj.drop_('sig_resp');
    obj.drop_('sig_clip');
    hide_excitation_axis_(ax);
    stimgen.calibration.LiveMonitor.caption_(ax, 'Response  (no data)');
    return
end

% Everything below draws on the response's own axis unless it says otherwise.
if numel(ax.YAxis) > 1
    yyaxis(ax, 'left');
end

% Created before the traces so it stays behind them without a uistack call,
% which UIAxes does not reliably support. That only holds for opaque
% objects: UIAxes renders alpha-blended patches in a separate compositing
% pass that lands on top of fully-opaque lines no matter the creation or
% Children order, so this is drawn as a flat opaque tint (pre-blended
% against a white background) rather than a translucent overlay.
hSpan = obj.gobj_('sig_span', @() patch(ax, XData=NaN, YData=NaN, ...
    FaceColor=[0.85 0.90 0.99], FaceAlpha=1, EdgeColor='none', ...
    HandleVisibility='off'));

[t, yv] = obj.waveform_xy_(y, fs);

hResp = obj.gobj_('sig_resp', @() line(ax, NaN, NaN, ...
    Color=[0.10 0.25 0.60], Marker='none', LineWidth=0.75, DisplayName='response'));
set(hResp, XData=t, YData=yv);

peak = max(abs(y));
rms_ = sqrt(mean(y.^2));
yl   = max(peak * 1.15, eps);

% Clipping limits are only worth the ink when the record is within ~12 dB of
% them; drawn otherwise they flatten the waveform against the axis.
fsv = d.Metrics.full_scale_v;
if isfinite(fsv) && fsv > 0 && peak > fsv / 4
    yl = max(yl, fsv * 1.05);
    hClip = obj.gobj_('sig_clip', @() line(ax, NaN, NaN, LineStyle='--', ...
        Color=[0.80 0.10 0.10], LineWidth=0.75, HandleVisibility='off'));
    set(hClip, XData=[t(1) t(end) NaN t(1) t(end)], ...
               YData=[fsv fsv NaN -fsv -fsv]);
else
    obj.drop_('sig_clip');
end

% After yl: the excitation is drawn into the response's axis and read off the
% right-hand ruler, which is only a second scale over the same span.
x = d.Excitation;
if numel(x) == numel(y) && any(x)
    render_excitation_(obj, ax, x, fs, yl);
else
    obj.drop_('sig_exc');
    obj.drop_('sig_exc_fill');
    hide_excitation_axis_(ax);
end

[tSpan, ySpan] = span_patch_(d, fs, yl);
set(hSpan, XData=tSpan, YData=ySpan);

% Forced every frame rather than trusted to creation order: this axis is
% shared across a whole session, and a reference or background measurement
% run earlier creates sig_resp with no excitation data at all. The first
% time a real excitation trace exists to draw -- once an actual calibration
% run starts -- sig_exc is created fresh at that point, after sig_resp
% already exists, which would otherwise leave it sitting in front of the
% response it is meant to sit behind.
%
% The span tint goes over the excitation's shading and under its outline:
% both are opaque (see above), so whichever is drawn last is the only one
% seen where they overlap -- and inside a burst they always overlap. The
% outline is what carries the excitation's shape, the shading only makes it
% read as the drive rather than as a second response, so the outline is the
% one that has to survive.
frontToBack = gobjects(0);
for key = ["sig_clip", "sig_resp", "sig_exc", "sig_span", "sig_exc_fill"]
    if obj.has_(key)
        frontToBack(end+1) = obj.H_.(key); %#ok<AGROW>
    end
end
restack_(ax, frontToBack);

ylim(ax, [-yl yl]);
xlim(ax, [t(1) max(t(end), t(1) + eps)]);
grid(ax, 'on');
xlabel(ax, 'time (ms)');
ylabel(ax, 'response (V)');

% The title states only what the panel is (and the one red word that must
% not be missed); the numbers live in the subtitle, whose smaller type is
% what keeps a metrics-laden caption inside the panel.
dcTxt = dc_text_(d.Metrics, peak);

if d.Metrics.clipping
    stimgen.calibration.LiveMonitor.caption_(ax, 'Response  \bfCLIPPING\rm', ...
        sprintf('peak %.3f V  ·  RMS %.3f V%s', peak, rms_, dcTxt), [0.75 0 0]);
else
    headroomDb = 20 * log10(max(fsv, eps) / max(peak, eps));
    stimgen.calibration.LiveMonitor.caption_(ax, 'Response', ...
        sprintf('peak %.3f V (%.1f dB headroom)  ·  RMS %.3f V%s', ...
        peak, headroomDb, rms_, dcTxt));
end
end

% ------------------------------------------------------------------------ %
function render_excitation_(obj, ax, x, fs, yl)
% What was played, as a shaded area under its own outline, read off a
% right-hand ruler carrying the volts it was actually played at.
%
% The drive and the response are volts on both sides of the rig and nowhere
% near the same size, so one pair of limits cannot serve both. The trace is
% drawn into the response's axis, scaled to fill it, and the right ruler is
% set to the range that scaling implies -- so the shape is legible whatever
% the ratio, and the number beside it is the drive voltage rather than a
% dimensionless "scaled" curve.
%
% Drawn into the left axis, not onto the right one, for a mechanical reason:
% with two y-axes ax.Children exposes only the active side, and the stacking
% this panel depends on -- shading behind the span tint, outline in front of
% it, response in front of everything -- cannot be expressed across sides.
%
% Shaded rather than left as a bare line because the two traces are otherwise
% the same kind of mark, and the one that was commanded reads differently
% from the one that came back. The area also makes a gated burst's envelope
% legible at a glance, which is what the eye checks the response's
% segmentation against.
[tx, xv] = obj.waveform_xy_(x, fs);

xPeak = max(abs(xv));
xl    = max(xPeak * 1.15, eps);
k     = yl / xl;                     % volts of drive per volt of axis

% Both kept light: at a full record's zoom the envelope is a dense
% oscillation that fills its own outline, so a mid-grey trace here would
% weigh more on the panel than the response it is background for.
hFill = obj.gobj_('sig_exc_fill', @() patch(ax, XData=NaN, YData=NaN, ...
    FaceColor=[0.92 0.92 0.94], FaceAlpha=1, EdgeColor='none', ...
    HandleVisibility='off'));
set(hFill, XData=[tx, fliplr(tx)], YData=[xv .* k, zeros(1, numel(tx))]);

hExc = obj.gobj_('sig_exc', @() line(ax, NaN, NaN, ...
    Color=[0.80 0.80 0.85], LineWidth=0.5, DisplayName='excitation'));
set(hExc, XData=tx, YData=xv .* k);

% The ruler, and only the ruler: nothing is drawn on this side. Its limits
% are the left axis's divided by the same k, so a point of the trace read
% against it gives the volt it was played at.
yyaxis(ax, 'right');
ax.YAxis(2).Visible = 'on';
ylim(ax, [-xl xl]);
ylabel(ax, 'excitation (V)');
ax.YAxis(2).Color = [0.55 0.55 0.60];
yyaxis(ax, 'left');
end

% ------------------------------------------------------------------------ %
function hide_excitation_axis_(ax)
% Retire the right-hand axis for the measurements that play nothing -- the
% reference and the background. The axis outlives the traces on it, so
% deleting those alone would leave an empty scale labelled in volts that
% nothing on screen is drawn against.
if ~isgraphics(ax) || numel(ax.YAxis) < 2
    return
end
yyaxis(ax, 'right');
ylabel(ax, '');
ax.YAxis(2).Visible = 'off';
yyaxis(ax, 'left');
end

% ------------------------------------------------------------------------ %
function s = dc_text_(m, peak)
% Subtitle clause for the record's baseline. Two different things are worth
% saying, and only one of them at a time:
%
%   coupled  - the AC coupling option acted on this record. Stated whenever
%              it did, however small the offset it took off, because the
%              question it answers is "did the setting take effect", not "is
%              the offset large". The corner is named because it is the part
%              that can be set wrong, and a record too short to filter says
%              so by reporting the DC alone.
%   present  - the record still carries an offset, and it is big enough to
%              matter (1% of peak). This is the reading that tells you the
%              option is worth turning on.
if isfield(m, 'ac_coupled_hz') && isfinite(m.ac_coupled_hz)
    s = sprintf('  ·  AC coupled %s', hz_text_(m.ac_coupled_hz));
    if isfield(m, 'dc_removed_v') && isfinite(m.dc_removed_v)
        s = sprintf('%s (DC %s removed)', s, volt_text_(m.dc_removed_v));
    end
elseif isfield(m, 'dc_removed_v') && isfinite(m.dc_removed_v)
    s = sprintf('  ·  DC removed %s (record too short to filter)', ...
        volt_text_(m.dc_removed_v));
elseif isfield(m, 'dc_v') && isfinite(m.dc_v) && abs(m.dc_v) > 0.01 * max(peak, eps)
    s = sprintf('  ·  DC %s', volt_text_(m.dc_v));
else
    s = '';
end
end

% ------------------------------------------------------------------------ %
function s = hz_text_(f)
% Corner frequency without trailing zeros on the whole numbers it usually is.
if f >= 1000
    s = sprintf('%.3g kHz', f / 1e3);
else
    s = sprintf('%.4g Hz', f);
end
end

% ------------------------------------------------------------------------ %
function s = volt_text_(v)
% Volts in the unit that reads without leading zeros at this scale.
if abs(v) < 0.1
    s = sprintf('%.2f mV', v * 1e3);
else
    s = sprintf('%.3f V', v);
end
end

% ------------------------------------------------------------------------ %
function restack_(ax, frontToBack)
% restack_(ax, frontToBack)
% Force ax.Children into the given front-to-back order (frontToBack(1) ends
% up on top). ax.Children lists the most recently created/modified object
% first, so setting it directly is the reliable substitute for creation
% order here -- uistack does not work reliably on UIAxes, which is exactly
% why this panel tried to lean on creation order in the first place.
frontToBack = frontToBack(isgraphics(frontToBack));
if isempty(frontToBack)
    return
end
kids = ax.Children;
rest = kids(~ismember(kids, frontToBack));
ax.Children = [frontToBack(:); rest(:)];
end

% ------------------------------------------------------------------------ %
function [tSpan, ySpan] = span_patch_(d, fs, yl)
% Patch vertices spanning the analysed samples. All-NaN, which draws nothing,
% when the whole record was measured.
if numel(d.Span) ~= 2 || any(~isfinite(d.Span))
    tSpan = NaN(1, 4);
    ySpan = NaN(1, 4);
    return
end
a = (d.Span(1) - 1) / fs * 1e3;
b = (d.Span(2) - 1) / fs * 1e3;
tSpan = [a b b a];
ySpan = [-yl -yl yl yl];
end
