function render_signal_(obj, d)
% render_signal_(obj, d)
% Waveform panel: the recorded response over time, the excitation behind it as
% a scaled ghost, the span the measurement was actually computed over, and the
% converter's clipping limits when the record comes near them.
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
    obj.drop_('sig_resp');
    obj.drop_('sig_clip');
    title(ax, 'Response  (no data)');
    return
end

% Created before the traces so it stays behind them without a uistack call,
% which UIAxes does not reliably support. That only holds for opaque
% objects: UIAxes renders alpha-blended patches in a separate compositing
% pass that lands on top of fully-opaque lines no matter the creation or
% Children order, so this is drawn as a flat opaque tint (pre-blended
% against a white background) rather than a translucent overlay.
hSpan = obj.gobj_('sig_span', @() patch(ax, XData=NaN, YData=NaN, ...
    FaceColor=[0.90 0.93 0.98], FaceAlpha=1, EdgeColor='none', ...
    HandleVisibility='off'));

[t, yv] = stimgen.calibration.LiveMonitor.envelope_decimate_(y, fs, obj.MaxPoints);

x = d.Excitation;
if numel(x) == numel(y) && any(x)
    % Scaled to the response so both fit one axis; the shape, not the level,
    % is what shows whether the record lines up with what was played.
    [tx, xv] = stimgen.calibration.LiveMonitor.envelope_decimate_(x, fs, obj.MaxPoints);
    xv = xv .* (max(abs(yv)) / max(abs(xv)));
    hExc = obj.gobj_('sig_exc', @() line(ax, NaN, NaN, ...
        Color=[0.78 0.78 0.82], LineWidth=0.5, DisplayName='excitation (scaled)'));
    set(hExc, XData=tx, YData=xv);
else
    obj.drop_('sig_exc');
end

hResp = obj.gobj_('sig_resp', @() line(ax, NaN, NaN, ...
    Color=[0.10 0.25 0.60], LineWidth=0.75, DisplayName='response'));
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

[tSpan, ySpan] = span_patch_(d, fs, yl);
set(hSpan, XData=tSpan, YData=ySpan);

% Forced every frame rather than trusted to creation order: this axis is
% shared across a whole session, and a reference or background measurement
% run earlier creates sig_resp with no excitation data at all. The first
% time a real excitation ghost exists to draw -- once an actual calibration
% run starts -- sig_exc is created fresh at that point, after sig_resp
% already exists, which would otherwise leave the ghost sitting in front of
% the response it is meant to sit behind.
frontToBack = gobjects(0);
for key = ["sig_clip", "sig_resp", "sig_exc", "sig_span"]
    if obj.has_(key)
        frontToBack(end+1) = obj.H_.(key); %#ok<AGROW>
    end
end
restack_(ax, frontToBack);

ylim(ax, [-yl yl]);
xlim(ax, [t(1) max(t(end), t(1) + eps)]);
grid(ax, 'on');
xlabel(ax, 'time (ms)');
ylabel(ax, 'volts');

dcTxt = dc_text_(d.Metrics, peak);

if d.Metrics.clipping
    title(ax, sprintf('Response  \\bfCLIPPING\\rm  |  peak %.3f V, RMS %.3f V%s', ...
        peak, rms_, dcTxt), Color=[0.75 0 0]);
else
    headroomDb = 20 * log10(max(fsv, eps) / max(peak, eps));
    title(ax, sprintf('Response  |  peak %.3f V (%.1f dB headroom), RMS %.3f V%s', ...
        peak, headroomDb, rms_, dcTxt), Color=[0 0 0]);
end
end

% ------------------------------------------------------------------------ %
function s = dc_text_(m, peak)
% Title clause for the record's DC offset. Two different things are worth
% saying, and only one of them at a time:
%
%   removed  - the demean option acted on this record. Stated whenever it
%              did, however small the offset, because the question it answers
%              is "did the setting take effect", not "is the offset large".
%   present  - the record still carries an offset, and it is big enough to
%              matter (1% of peak). This is the reading that tells you the
%              option is worth turning on.
if isfield(m, 'dc_removed_v') && isfinite(m.dc_removed_v)
    s = sprintf(', DC removed %s', volt_text_(m.dc_removed_v));
elseif isfield(m, 'dc_v') && isfinite(m.dc_v) && abs(m.dc_v) > 0.01 * max(peak, eps)
    s = sprintf(', DC %s', volt_text_(m.dc_v));
else
    s = '';
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
