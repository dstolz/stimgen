function draw_quality_panel_(obj, ax, panel, x, m, xLabelText, titleText)
% draw_quality_panel_(obj, ax, panel, x, m, xLabelText, titleText)
% The distortion-and-SNR detail axes under a tone or click panel.
%
% Both stimuli measure the same four figures per point and read them the same
% way, so one renderer draws both and only the abscissa and the captions
% differ. A trace whose metric the table does not carry -- the per-harmonic
% figures a click sweep cannot produce, or anything missing from a table
% written before the metric existed -- is dropped rather than drawn flat at
% zero, which would read as a measurement of no distortion.
%
% Parameters:
%   ax          - the detail axes
%   panel       - the stimulus panel it belongs to; scopes the cache keys
%   x           - abscissa in the units xLabelText names, or [] for none
%   m           - the table's metrics struct, or an empty struct
%   xLabelText  - axis caption, in the same Hz/us convention frequency_ticks_
%                 rewrites
%   titleText   - panel title
arguments
    obj
    ax
    panel (1,1) string
    x (1,:) double
    m
    xLabelText (1,:) char
    titleText (1,:) char
end

if ~all(isgraphics(ax))
    return
end

% The four traces, in the order they read: how much signal there was, then
% how much of what came back was not it.
specs = { ...
    'det1', 'snr_db', 'SNR',            [0.20 0.55 0.25], '-',  1.25; ...
    'det2', 'thd_db', 'THD',            [0.75 0.30 0.10], '-',  1; ...
    'det3', 'h2_db',  '2nd harmonic',   [0.55 0.20 0.60], '--', 0.75; ...
    'det4', 'h3_db',  '3rd harmonic',   [0.10 0.45 0.70], '--', 0.75};

k = @(name) char(panel + "_" + name);
grid(ax, 'on');
ylabel(ax, 'dB');

drawn = 0;
for i = 1:size(specs, 1)
    key = k(specs{i, 1});
    y = [];
    if isstruct(m) && isfield(m, specs{i, 2})
        y = double(m.(specs{i, 2})(:).');
    end
    if numel(y) ~= numel(x) || ~any(isfinite(y)) || isempty(x)
        obj.drop_(key);
        continue
    end
    ok = isfinite(x) & isfinite(y);
    h = obj.gobj_(key, @() line(ax, NaN, NaN, LineStyle=specs{i,5}, ...
        Color=specs{i,4}, LineWidth=specs{i,6}, Marker='.', MarkerSize=6, ...
        DisplayName=specs{i,3}));
    set(h, XData=x(ok), YData=y(ok));
    drawn = drawn + 1;
end

if drawn == 0
    obj.drop_(k('det_ref'));
    obj.drop_(k('det_legend'));
    xlabel(ax, xLabelText);
    stimgen.calibration.LiveMonitor.caption_(ax, ...
        sprintf('%s  (not measured)', titleText));
    return
end

% 0 dB is where a harmonic would equal the fundamental, and the line is what
% makes the distortion traces readable as the negative numbers they are
% without reading the tick labels.
hRef = obj.gobj_(k('det_ref'), @() line(ax, NaN, NaN, LineStyle=':', ...
    Color=[0.60 0.60 0.60], LineWidth=0.75, HandleVisibility='off'));
set(hRef, XData=[min(x) * 0.9, max(x) * 1.1], YData=[0 0]);

if obj.LogX
    set(ax, XScale='log');
else
    set(ax, XScale='linear');
end
if numel(x) > 1
    xlim(ax, [min(x) * 0.93, max(x) * 1.07]);
end
% After the limits, which the tick grid is placed within.
xlabel(ax, stimgen.calibration.LiveMonitor.frequency_ticks_(ax, xLabelText));

stimgen.calibration.LiveMonitor.caption_(ax, titleText, quality_subtitle_(m));

hLeg = obj.gobj_(k('det_legend'), @() legend(ax, Location='best', ...
    AutoUpdate='off', FontSize=8, NumColumns=2));
hLeg.Visible = 'on';
end

% ------------------------------------------------------------------------ %
function sub = quality_subtitle_(m)
% Medians rather than means: one bad point at a speaker's roll-off would
% drag a mean far enough to misrepresent the sweep, and it is the typical
% point this line is describing.
parts = {};
if isstruct(m) && isfield(m, 'snr_db')
    v = median(double(m.snr_db(:)), 'omitnan');
    if isfinite(v)
        parts{end+1} = sprintf('median SNR %.0f dB', v);
    end
end
if isstruct(m) && isfield(m, 'thd_db')
    v = median(double(m.thd_db(:)), 'omitnan');
    if isfinite(v)
        parts{end+1} = sprintf('median THD %.0f dB', v);
    end
end
if isstruct(m) && isfield(m, 'clipping_headroom') && ...
        isstruct(m.clipping_headroom) && ...
        isfield(m.clipping_headroom, 'responseHeadroomDb')
    v = min(double(m.clipping_headroom.responseHeadroomDb(:)));
    if isfinite(v)
        parts{end+1} = sprintf('input headroom %.0f dB', v);
    end
end

if isempty(parts)
    sub = '';
else
    sub = strjoin(parts, '  ·  ');
end
end
