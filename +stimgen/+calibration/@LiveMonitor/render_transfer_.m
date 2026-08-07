function render_transfer_(obj, d)
% render_transfer_(obj, d)
% Transfer panel: the calibration curve as it fills in.
%
% What it adds over a bare line through the measured points:
%   - a rug of ticks at every x still to be measured, so the shape of the
%     curve is read against how much of the sweep it actually covers;
%   - a +/-1 SD ribbon across repeats, which is the only on-screen evidence
%     that averaging is converging rather than chasing a drifting room;
%   - the point being measured, highlighted, so a stall is obvious;
%   - the drive voltage each point needs to hit NormativeValue on a right-hand
%     axis, with the hardware's output ceiling drawn across it. Points above
%     that line cannot be produced at the normative level, and finding that
%     out during the sweep rather than during an experiment is the whole
%     reason to watch a calibration run;
%   - progress and a time estimate in the title.

ax = obj.AxTransfer;
T  = d.Table;

xd    = T.x .* d.XFactor;
valid = isfinite(T.spl_db) & isfinite(xd);
if ~any(valid)
    valid = false(size(xd));
end

if obj.ShowVoltage
    yyaxis(ax, 'left');
end

render_ribbon_(obj, ax, xd, T, valid);

hMeas = obj.gobj_('xfer_meas', @() line(ax, NaN, NaN, LineStyle='-', ...
    Marker='o', MarkerSize=4, Color=[0.10 0.25 0.60], ...
    MarkerFaceColor=[0.10 0.25 0.60], LineWidth=1, DisplayName='measured'));
set(hMeas, XData=xd(valid), YData=T.spl_db(valid));

render_pending_rug_(obj, ax, xd, valid, T);
render_current_(obj, ax, xd, T, d);
render_normative_(obj, ax, xd, d);

ylabel(ax, 'level (dB SPL)');
if obj.LogX
    set(ax, XScale='log');
else
    set(ax, XScale='linear');
end
if numel(xd) > 1 && all(isfinite(xd([1 end])))
    xlim(ax, [min(xd) * 0.93, max(xd) * 1.07]);
end

% The click sweep runs this same panel against duration, where a weighting
% has nothing to say; the payload's own axis label is what distinguishes it.
if contains(d.XLabel, 'frequency', IgnoreCase=true)
    obj.render_weighting_(ax, xd(valid), T.spl_db(valid));
else
    obj.render_weighting_(ax, [], []);
end

if obj.ShowVoltage
    render_voltage_(obj, ax, xd, T, valid, d);
    yyaxis(ax, 'left');
end

grid(ax, 'on');
xlabel(ax, d.XLabel);
title(ax, transfer_title_(d, T, valid));

hLeg = obj.gobj_('xfer_legend', @() legend(ax, Location='southwest', ...
    AutoUpdate='off', FontSize=8));
hLeg.Visible = 'on';
end

% ------------------------------------------------------------------------ %
function render_ribbon_(obj, ax, xd, T, valid)
% +/-1 SD across repeats, as a filled band. Drawn first so it sits under the
% curve; dropped entirely on a single-pass run, where it would be a flat zero
% band implying a precision that was never measured.
sd = [];
if isfield(T, 'sd_db')
    sd = T.sd_db;
end
band = valid & isfinite(sd) & sd > 0;
if nnz(band) < 2
    obj.drop_('xfer_sd');
    return
end

xb = xd(band);
hi = T.spl_db(band) + sd(band);
lo = T.spl_db(band) - sd(band);
h = obj.gobj_('xfer_sd', @() patch(ax, XData=NaN, YData=NaN, ...
    FaceColor=[0.10 0.25 0.60], FaceAlpha=0.15, EdgeColor='none', ...
    HandleVisibility='off'));
set(h, XData=[xb, fliplr(xb)], YData=[hi, fliplr(lo)]);
end

% ------------------------------------------------------------------------ %
function render_pending_rug_(obj, ax, xd, valid, T)
% Tick marks along the bottom at every x not yet measured.
pending = ~valid & isfinite(xd);
if ~any(pending) || ~any(valid)
    obj.drop_('xfer_pending');
    return
end
base = min(T.spl_db(valid)) - 3;
h = obj.gobj_('xfer_pending', @() line(ax, NaN, NaN, LineStyle='none', ...
    Marker='|', MarkerSize=4, Color=[0.65 0.65 0.68], DisplayName='pending'));
set(h, XData=xd(pending), YData=repmat(base, 1, nnz(pending)));
end

% ------------------------------------------------------------------------ %
function render_current_(obj, ax, xd, T, d)
% Ring the point currently being measured.
i = d.Index;
if i < 1 || i > numel(xd) || ~isfinite(T.spl_db(i))
    obj.drop_('xfer_cur');
    return
end
h = obj.gobj_('xfer_cur', @() line(ax, NaN, NaN, LineStyle='none', ...
    Marker='o', MarkerSize=10, Color=[0.85 0.35 0.05], LineWidth=1.5, ...
    HandleVisibility='off'));
set(h, XData=xd(i), YData=T.spl_db(i));
end

% ------------------------------------------------------------------------ %
function render_normative_(obj, ax, xd, d)
% The target level the voltage LUT is solved for.
v = d.Context.NormativeValue;
if ~isfinite(v) || ~any(isfinite(xd))
    obj.drop_('xfer_norm');
    return
end
h = obj.gobj_('xfer_norm', @() line(ax, NaN, NaN, LineStyle=':', ...
    Color=[0.35 0.35 0.35], LineWidth=0.75, DisplayName='normative level'));
set(h, XData=[min(xd) * 0.9, max(xd) * 1.1], YData=[v v]);
end

% ------------------------------------------------------------------------ %
function render_voltage_(obj, ax, xd, T, valid, d)
% Right axis: drive voltage needed for NormativeValue, against the output
% ceiling. Log-scaled because the requirement spans decades across a speaker's
% roll-off, which is exactly where it matters.
yyaxis(ax, 'right');
ax.YAxis(2).Visible = 'on';   % show_background hides it; a run owns it again

vAll = T.voltage;
show = valid & isfinite(vAll) & vAll > 0;
h = obj.gobj_('xfer_volt', @() line(ax, NaN, NaN, LineStyle='-', ...
    Marker='.', MarkerSize=8, Color=[0.20 0.55 0.25], LineWidth=0.75, ...
    DisplayName='drive V for normative'));
set(h, XData=xd(show), YData=vAll(show));

maxV = d.Context.MaxOutputV;
if isfinite(maxV) && maxV > 0 && any(isfinite(xd))
    hMax = obj.gobj_('xfer_vmax', @() line(ax, NaN, NaN, LineStyle='--', ...
        Color=[0.80 0.10 0.10], LineWidth=0.75, HandleVisibility='off'));
    set(hMax, XData=[min(xd) * 0.9, max(xd) * 1.1], YData=[maxV maxV]);

    over = show & vAll > maxV;
    hOver = obj.gobj_('xfer_vover', @() line(ax, NaN, NaN, LineStyle='none', ...
        Marker='x', MarkerSize=8, Color=[0.80 0.10 0.10], LineWidth=1.25, ...
        DisplayName='unreachable'));
    set(hOver, XData=xd(over), YData=vAll(over));
else
    obj.drop_('xfer_vmax');
    obj.drop_('xfer_vover');
end

if any(show)
    lo = min([vAll(show), maxV]) * 0.5;
    hi = max([vAll(show), maxV]) * 2;
    set(ax, YScale='log');
    ylim(ax, [max(lo, eps) max(hi, max(lo, eps) * 10)]);
end
ylabel(ax, 'drive (V)');
ax.YAxis(2).Color = [0.20 0.55 0.25];
end

% ------------------------------------------------------------------------ %
function s = transfer_title_(d, T, valid)
% Two lines: what is running and how far along, then the span the curve has
% covered so far.
stage = stimgen.calibration.LiveMonitor.stage_name_(d.Stage);

head = stage;
if d.Total > 0
    head = sprintf('%s  %d/%d', head, max(d.Index, 0), d.Total);
end
if d.RepeatTotal > 1
    head = sprintf('%s  ·  pass %d/%d', head, max(d.Repeat, 0), d.RepeatTotal);
end

if d.Phase == "done"
    head = sprintf('%s  ·  complete in %s', head, ...
        stimgen.calibration.LiveMonitor.clock_(d.Elapsed));
elseif isfinite(d.Progress) && d.Progress > 0.02
    remaining = d.Elapsed * (1 - d.Progress) / d.Progress;
    head = sprintf('%s  ·  %s elapsed, ~%s left', head, ...
        stimgen.calibration.LiveMonitor.clock_(d.Elapsed), ...
        stimgen.calibration.LiveMonitor.clock_(remaining));
else
    head = sprintf('%s  ·  %s elapsed', head, ...
        stimgen.calibration.LiveMonitor.clock_(d.Elapsed));
end

if nnz(valid) >= 2
    lvl = T.spl_db(valid);
    tail = sprintf('%.1f–%.1f dB SPL (%.1f dB span)', ...
        min(lvl), max(lvl), max(lvl) - min(lvl));
else
    tail = 'measuring...';
end

s = {head, tail};
end
