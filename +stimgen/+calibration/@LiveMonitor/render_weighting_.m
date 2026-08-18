function render_weighting_(obj, panel, f, lvl)
% render_weighting_(obj, panel, f, lvl)
% Overlay the standard weighting curves named by obj.Weightings onto one
% panel's level-versus-frequency axis, and remove the ones no longer named.
%
% A weighting is a relative curve -- 0 dB at 1 kHz by definition -- so it has
% no meaning on an absolute dB SPL axis until it is given a level to sit at.
% Each curve is offset to pass through the measured level at 1 kHz, so the
% vertical distance between curve and measurement is what the overlay is for:
% how much of the response the ear discards. When 1 kHz falls outside the
% measured span, the nearest measured frequency anchors it instead, and the
% legend carries the offset either way so the reference is never implicit.
%
% Drawn only across the span of the reference data and clipped to its level
% range, because A-weighting reaches -50 dB by 20 Hz and an unclipped curve
% would rescale the axis until every measured curve on the panel was flat.
%
% Parameters:
%   panel - which view is asking ("transfer" | "background"); its axes must
%           already have the left y-axis active. The cache key carries the
%           panel, so the same overlay drawn on two views that own separate
%           axes is two objects rather than one fought over.
%   f     - reference frequencies in Hz; need not be sorted
%   lvl   - reference levels in dB SPL, same size as f

types = stimgen.calibration.LiveMonitor.WeightingTypes;
want  = obj.Weightings;
ax    = obj.panel_axes_(panel);

f   = double(f(:)).';
lvl = double(lvl(:)).';
ok  = isfinite(f) & isfinite(lvl) & f > 0;
f   = f(ok);
lvl = lvl(ok);
[f, iu] = unique(f);   % sorted and de-duplicated, as interp1 requires
lvl = lvl(iu);

if isempty(want) || numel(f) < 2
    for k = 1:numel(types)
        obj.drop_(key_(panel, types(k)));
    end
    return
end

fAnchor = min(max(1000, f(1)), f(end));
anchor  = interp1(f, lvl, fAnchor);

pad = max(3, 0.1 * (max(lvl) - min(lvl)));
yLo = min(lvl) - pad;
yHi = max(lvl) + pad;

fGrid = logspace(log10(f(1)), log10(f(end)), 256);

for k = 1:numel(types)
    t = types(k);
    if ~any(want == t)
        obj.drop_(key_(panel, t));
        continue
    end

    offset = anchor - stimgen.util.weighting_db(fAnchor, t);
    y = stimgen.util.weighting_db(fGrid, t) + offset;
    y(y < yLo | y > yHi) = NaN;   % clipped in the data, not by the axis limits

    name = sprintf('%s-weighting (%+.0f dB)', t, offset);
    h = obj.gobj_(key_(panel, t), @() line(ax, NaN, NaN, LineStyle='-.', ...
        Color=color_(t), LineWidth=1, DisplayName=name));
    set(h, XData=fGrid, YData=y, DisplayName=name);
end
end

% ------------------------------------------------------------------------ %
function k = key_(panel, type)
% Cache key for one panel's copy of one weighting curve.
% LiveMonitor.set.Weightings and panel_keys_ build the same names to drop
% them when the selection changes or the panel is cleared.
k = char("wt_" + panel + "_" + type);
end

% ------------------------------------------------------------------------ %
function c = color_(type)
% Distinct from the measurement colors in use on this panel (blue tone,
% green swept sine and drive voltage, orange click, red ceiling), so an
% overlay never reads as data.
switch type
    case "A", c = [0.55 0.20 0.60];
    case "B", c = [0.85 0.55 0.10];
    case "C", c = [0.10 0.60 0.70];
    case "D", c = [0.60 0.35 0.20];
    otherwise, c = [0.45 0.45 0.45];
end
end
