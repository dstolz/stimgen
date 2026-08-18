function render_transfer_(obj, d, panel)
% render_transfer_(obj, d, panel)
% One stimulus panel, filling in as its sweep runs.
%
% Every stimulus's sweep is measured the same way -- a level per abscissa,
% averaged over repeats -- so one renderer draws all three, and the panel it
% is asked for decides only which axes and which cached objects it owns
% (LiveMonitor.stage_panel maps a run stage to that panel). What separates
% the stimuli is what is worth showing ONCE the table is committed, and that
% belongs to show_lut_ and the detail renderers under it, not here.
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
%   - progress in the title, with the timing and level span in the subtitle.
%
% Parameters:
%   d     - stimgen.calibration.LiveUpdate payload
%   panel - the stimulus panel to draw on; see LiveMonitor.TransferPanels
arguments
    obj
    d (1,1) stimgen.calibration.LiveUpdate
    panel (1,1) string = "transfer"
end

ax = obj.panel_axes_(panel);
if ~isgraphics(ax)
    return
end
k = @(name) char(panel + "_" + name);
T = d.Table;

xd    = T.x .* d.XFactor;
valid = isfinite(T.spl_db) & isfinite(xd);
if ~any(valid)
    valid = false(size(xd));
end

if obj.ShowVoltage
    yyaxis(ax, 'left');
end
% show_background may have left this axis on a manual ylim sized to the
% noise floor; reset it so a run's own data sets the scale instead of
% clipping against whatever was shown here last.
ax.YLimMode = 'auto';

render_ribbon_(obj, ax, k, xd, T, valid);

hMeas = obj.gobj_(k('meas'), @() line(ax, NaN, NaN, LineStyle='-', ...
    Color=[0.10 0.25 0.60], LineWidth=1, DisplayName='measured'));
set(hMeas, XData=xd(valid), YData=T.spl_db(valid));

render_pending_rug_(obj, ax, k, xd, valid, T);
render_current_(obj, ax, k, xd, T, d);
render_normative_(obj, ax, k, xd, d);

ylabel(ax, 'level (dB SPL)');
if obj.LogX
    set(ax, XScale='log');
else
    set(ax, XScale='linear');
end
if numel(xd) > 1 && all(isfinite(xd([1 end])))
    xlim(ax, [min(xd) * 0.93, max(xd) * 1.07]);
end

% The click sweep runs against duration, where a weighting has nothing to
% say; the payload's own axis label is what distinguishes it, since this
% renderer also draws the filter test, whose x is frequency.
if contains(d.XLabel, 'frequency', IgnoreCase=true)
    obj.render_weighting_(panel, xd(valid), T.spl_db(valid));
else
    obj.render_weighting_(panel, [], []);
end

if obj.ShowVoltage
    render_voltage_(obj, ax, k, xd, T, valid, d);
    yyaxis(ax, 'left');
end

grid(ax, 'on');
xlabel(ax, stimgen.calibration.LiveMonitor.frequency_ticks_(ax, char(d.XLabel)));
[head, sub] = transfer_caption_(d, T, valid);
stimgen.calibration.LiveMonitor.caption_(ax, head, sub);

hLeg = obj.gobj_(k('legend'), @() legend(ax, Location='southwest', ...
    AutoUpdate='off', FontSize=8));
hLeg.Visible = 'on';
end

% ------------------------------------------------------------------------ %
function render_ribbon_(obj, ax, k, xd, T, valid)
% +/-1 SD across repeats, as a filled band. Drawn first so it sits under the
% curve; dropped entirely on a single-pass run, where it would be a flat zero
% band implying a precision that was never measured.
sd = [];
if isfield(T, 'sd_db')
    sd = T.sd_db;
end
band = valid & isfinite(sd) & sd > 0;
if nnz(band) < 2
    obj.drop_(k('sd'));
    return
end

xb = xd(band);
hi = T.spl_db(band) + sd(band);
lo = T.spl_db(band) - sd(band);
h = obj.gobj_(k('sd'), @() patch(ax, XData=NaN, YData=NaN, ...
    FaceColor=[0.10 0.25 0.60], FaceAlpha=0.15, EdgeColor='none', ...
    HandleVisibility='off'));
set(h, XData=[xb, fliplr(xb)], YData=[hi, fliplr(lo)]);
end

% ------------------------------------------------------------------------ %
function render_pending_rug_(obj, ax, k, xd, valid, T)
% Tick marks along the bottom at every x not yet measured.
pending = ~valid & isfinite(xd);
if ~any(pending) || ~any(valid)
    obj.drop_(k('pending'));
    return
end
base = min(T.spl_db(valid)) - 3;
h = obj.gobj_(k('pending'), @() line(ax, NaN, NaN, LineStyle='none', ...
    Marker='|', MarkerSize=4, Color=[0.65 0.65 0.68], DisplayName='pending'));
set(h, XData=xd(pending), YData=repmat(base, 1, nnz(pending)));
end

% ------------------------------------------------------------------------ %
function render_current_(obj, ax, k, xd, T, d)
% Ring the point currently being measured.
i = d.Index;
if i < 1 || i > numel(xd) || ~isfinite(T.spl_db(i))
    obj.drop_(k('cur'));
    return
end
h = obj.gobj_(k('cur'), @() line(ax, NaN, NaN, LineStyle='none', ...
    Marker='o', MarkerSize=10, Color=[0.85 0.35 0.05], LineWidth=1.5, ...
    HandleVisibility='off'));
set(h, XData=xd(i), YData=T.spl_db(i));
end

% ------------------------------------------------------------------------ %
function render_normative_(obj, ax, k, xd, d)
% The target level the voltage LUT is solved for.
v = d.Context.NormativeValue;
if ~isfinite(v) || ~any(isfinite(xd))
    obj.drop_(k('norm'));
    return
end
h = obj.gobj_(k('norm'), @() line(ax, NaN, NaN, LineStyle=':', ...
    Color=[0.35 0.35 0.35], LineWidth=0.75, DisplayName='normative level'));
set(h, XData=[min(xd) * 0.9, max(xd) * 1.1], YData=[v v]);
end

% ------------------------------------------------------------------------ %
function render_voltage_(obj, ax, k, xd, T, valid, d)
% Right axis: drive voltage needed for NormativeValue, against the output
% ceiling. Log-scaled because the requirement spans decades across a speaker's
% roll-off, which is exactly where it matters.
yyaxis(ax, 'right');
ax.YAxis(2).Visible = 'on';   % show_background hides it; a run owns it again

vAll = T.voltage;
show = valid & isfinite(vAll) & vAll > 0;
h = obj.gobj_(k('volt'), @() line(ax, NaN, NaN, LineStyle='-', ...
    Color=[0.20 0.55 0.25], LineWidth=0.75, ...
    DisplayName='drive V for normative'));
set(h, XData=xd(show), YData=vAll(show));

maxV = d.Context.MaxOutputV;
if isfinite(maxV) && maxV > 0 && any(isfinite(xd))
    hMax = obj.gobj_(k('vmax'), @() line(ax, NaN, NaN, LineStyle='--', ...
        Color=[0.80 0.10 0.10], LineWidth=0.75, HandleVisibility='off'));
    set(hMax, XData=[min(xd) * 0.9, max(xd) * 1.1], YData=[maxV maxV]);

    over = show & vAll > maxV;
    hOver = obj.gobj_(k('vover'), @() line(ax, NaN, NaN, LineStyle='none', ...
        Marker='x', MarkerSize=8, Color=[0.80 0.10 0.10], LineWidth=1.25, ...
        DisplayName='unreachable'));
    set(hOver, XData=xd(over), YData=vAll(over));
else
    obj.drop_(k('vmax'));
    obj.drop_(k('vover'));
end

if any(show)
    lo = min([vAll(show), maxV]) * 0.5;
    hi = max([vAll(show), maxV]) * 2;
    set(ax, YScale='log');
    ylim(ax, [max(lo, eps) max(hi, max(lo, eps) * 10)]);
    ax.YAxis(2).Exponent = 0;
end
ylabel(ax, 'drive (V)');
ax.YAxis(2).Color = [0.20 0.55 0.25];
end

% ------------------------------------------------------------------------ %
function [head, sub] = transfer_caption_(d, T, valid)
% Title: what is running and how far along. Subtitle: the timing and the span
% the curve has covered so far -- the numbers, in the smaller type that keeps
% them inside the panel.
stage = stimgen.calibration.LiveMonitor.stage_name_(d.Stage);

head = stage;
if d.Total > 0
    head = sprintf('%s  %d/%d', head, max(d.Index, 0), d.Total);
end
if d.RepeatTotal > 1
    head = sprintf('%s  ·  pass %d/%d', head, max(d.Repeat, 0), d.RepeatTotal);
end

if d.Phase == "done"
    timing = sprintf('complete in %s', ...
        stimgen.calibration.LiveMonitor.clock_(d.Elapsed));
elseif isfinite(d.Progress) && d.Progress > 0.02
    remaining = d.Elapsed * (1 - d.Progress) / d.Progress;
    timing = sprintf('%s elapsed, ~%s left', ...
        stimgen.calibration.LiveMonitor.clock_(d.Elapsed), ...
        stimgen.calibration.LiveMonitor.clock_(remaining));
else
    timing = sprintf('%s elapsed', ...
        stimgen.calibration.LiveMonitor.clock_(d.Elapsed));
end

if nnz(valid) >= 2
    lvl = T.spl_db(valid);
    span = sprintf('%.1f–%.1f dB SPL (%.1f dB span)', ...
        min(lvl), max(lvl), max(lvl) - min(lvl));
else
    span = 'measuring...';
end

sub = sprintf('%s  ·  %s', timing, span);
end
