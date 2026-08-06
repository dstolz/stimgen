function show_background(obj, eng)
% show_background(obj, eng)
% Draw an engine's stored background analysis on the transfer panel: the
% band levels the noise floor decomposes into, the A-weighted version of the
% same, the broadband level across it, and the tonal components picked out of
% it.
%
% This is where a background capture is read. The waveform and spectrum panels
% show the record it came from, but a single record's spectrum is a noisy thing
% to judge a floor by; the band levels are the averaged, comparable form, and
% the only form that survives into the saved file once the raw record is gone.
%
% Shares the transfer axes with show_calibration, which draws the lookup tables
% there instead. Whichever ran last owns the panel -- CalibrationGui's View menu
% is how a user switches between them.
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

% The LUT view leaves a right-hand drive-voltage axis behind. Nothing here has
% a voltage, so it is hidden rather than left showing an empty scale; the LUT
% view turns it back on when it draws.
if numel(ax.YAxis) > 1
    yyaxis(ax, 'right');
    ylabel(ax, '');
    ax.YAxis(2).Visible = 'off';
    yyaxis(ax, 'left');
end

xlabel(ax, 'frequency (Hz)');
ylabel(ax, 'level (dB SPL)');
grid(ax, 'on');

B = background_data_(eng);
if isempty(B)
    title(ax, 'Background noise  (not measured)');
    return
end

lvls = draw_curves_(obj, ax, B);
draw_broadband_(obj, ax, B);
lvls = [lvls, draw_peaks_(obj, ax, B, lvls)];

if obj.LogX
    set(ax, XScale='log');
else
    set(ax, XScale='linear');
end
set_limits_(ax, B, lvls);

title(ax, background_title_(B));
hLeg = obj.gobj_('bg_legend', @() legend(ax, Location='southwest', ...
    AutoUpdate='off', FontSize=8));
hLeg.Visible = 'on';

drawnow limitrate;
end

% ------------------------------------------------------------------------ %
function B = background_data_(eng)
% The stored background record, or [] when none has been captured.
B = [];
C = eng.CalibrationData;
if isstruct(C) && isfield(C, 'background') && ~isempty(C.background)
    B = C.background;
end
end

% ------------------------------------------------------------------------ %
function lvls = draw_curves_(obj, ax, B)
% The fine spectrum behind, the analysis bands on top, and the A-weighted
% bands alongside them. All three are on one axis because the question they
% answer together -- how much of this noise is where the ear is -- is the
% distance between the last two.
lvls = [];

if isfield(B, 'spectrum') && ~isempty(B.spectrum.frequency)
    h = obj.gobj_('bg_spectrum', @() line(ax, NaN, NaN, ...
        Color=[0.72 0.72 0.76], LineWidth=0.5, DisplayName='1/12 octave'));
    set(h, XData=B.spectrum.frequency, YData=B.spectrum.level_db);
    lvls = [lvls, B.spectrum.level_db];
end

if isempty(B.bands.frequency)
    obj.drop_('bg_bands');
    obj.drop_('bg_bands_a');
    return
end

label = sprintf('1/%d octave', B.bands.fraction);
h = obj.gobj_('bg_bands', @() line(ax, NaN, NaN, LineStyle='-', Marker='o', ...
    MarkerSize=4, Color=[0.10 0.25 0.60], MarkerFaceColor=[0.10 0.25 0.60], ...
    LineWidth=1, DisplayName=label));
set(h, XData=B.bands.frequency, YData=B.bands.level_db, DisplayName=label);
lvls = [lvls, B.bands.level_db];

hA = obj.gobj_('bg_bands_a', @() line(ax, NaN, NaN, LineStyle='--', ...
    Marker='none', Color=[0.20 0.55 0.25], LineWidth=0.75, ...
    DisplayName='A-weighted'));
set(hA, XData=B.bands.frequency, YData=B.bands.level_dba);

% A-weighting runs to -50 dB at the low end and would set the y-scale to
% something no measurement occupies, so it is drawn but not scaled to.
end

% ------------------------------------------------------------------------ %
function draw_broadband_(obj, ax, B)
% The single number across the bands it was integrated from.
if ~isfinite(B.spl_db) || isempty(B.bands.frequency)
    obj.drop_('bg_broadband');
    return
end
x = [min(B.bands.frequency) * 0.9, max(B.bands.frequency) * 1.1];
h = obj.gobj_('bg_broadband', @() line(ax, NaN, NaN, LineStyle=':', ...
    Color=[0.35 0.35 0.35], LineWidth=0.75, DisplayName='broadband'));
set(h, XData=x, YData=[B.spl_db B.spl_db]);
end

% ------------------------------------------------------------------------ %
function lvls = draw_peaks_(obj, ax, B, bandLvls)
% Tonal components, marked and labelled. One text object per peak, cached by
% slot so a quieter capture releases the labels the last one used.
MAX_LABELS = 8;
lvls = [];

if ~isfield(B, 'peaks') || isempty(B.peaks.frequency)
    obj.drop_('bg_peaks');
    for k = 1:MAX_LABELS
        obj.drop_(sprintf('bg_pk%d', k));
    end
    return
end

h = obj.gobj_('bg_peaks', @() line(ax, NaN, NaN, LineStyle='none', ...
    Marker='x', MarkerSize=8, Color=[0.80 0.10 0.10], LineWidth=1.25, ...
    DisplayName='tonal'));
set(h, XData=B.peaks.frequency, YData=B.peaks.level_db);
lvls = B.peaks.level_db;

% Labels are only readable while there are few of them; past that the marker
% alone says where, and the report says which.
n = numel(B.peaks.frequency);
if n > MAX_LABELS
    n = 0;
end
pad = 0.03 * max(range_or_(bandLvls, 20), 1);
for k = 1:n
    key = sprintf('bg_pk%d', k);
    ht = obj.gobj_(key, @() text(ax, NaN, NaN, '', Color=[0.80 0.10 0.10], ...
        FontSize=8, HorizontalAlignment='center', VerticalAlignment='bottom', ...
        Clipping='on'));
    set(ht, Position=[B.peaks.frequency(k), B.peaks.level_db(k) + pad, 0], ...
        String=sprintf('%.0f Hz', B.peaks.frequency(k)));
end
for k = n+1 : MAX_LABELS
    obj.drop_(sprintf('bg_pk%d', k));
end
end

% ------------------------------------------------------------------------ %
function set_limits_(ax, B, lvls)
% Scaled to the curves that carry the measurement, so a quiet floor is not
% flattened against the axis by the A-weighted tail below it.
lvls = lvls(isfinite(lvls));
if isempty(lvls)
    return
end
lo = floor((min([lvls, B.spl_db]) - 4) / 10) * 10;
hi = ceil((max([lvls, B.spl_db]) + 6) / 10) * 10;
ylim(ax, [lo, max(hi, lo + 30)]);

if ~isempty(B.bands.frequency) && numel(B.bands.frequency) > 1
    xlim(ax, [min(B.bands.frequency) * 0.93, max(B.bands.frequency) * 1.07]);
end
end

% ------------------------------------------------------------------------ %
function r = range_or_(v, fallback)
% Span of v, or fallback when there is nothing to take a span of.
v = v(isfinite(v));
if numel(v) < 2
    r = fallback;
    return
end
r = max(v) - min(v);
end

% ------------------------------------------------------------------------ %
function s = background_title_(B)
% Two lines: what the floor is, then what it is made of.
head = sprintf('Background noise  |  %.1f dB SPL  ·  %.1f dB(A)', B.spl_db, B.spl_dba);
if isfinite(B.duration_s) && B.repeat_count > 0
    head = sprintf('%s  ·  %g s x %d', head, round(B.duration_s, 2), B.repeat_count);
end
if ~B.stable
    head = sprintf('%s  ·  \\bf%.1f dB spread\\rm', head, B.range_db);
end

parts = {};
if isfinite(B.worst_band.frequency)
    parts{end+1} = sprintf('loudest band %.0f Hz at %.1f dB SPL', ...
        B.worst_band.frequency, B.worst_band.level_db);
end
if isfield(B, 'mains') && isfinite(B.mains.frequency)
    parts{end+1} = sprintf('%g Hz mains x%d at %.1f dB SPL', ...
        B.mains.frequency, B.mains.n_harmonics, B.mains.level_db);
elseif isfield(B, 'peaks') && ~isempty(B.peaks.frequency)
    parts{end+1} = sprintf('%d tonal component(s)', numel(B.peaks.frequency));
end
parts{end+1} = sprintf('%.0f dB below the %g dB SPL normative level', ...
    B.headroom_to_normative_db, B.normative_value_db);

s = {head, strjoin(parts, '  |  ')};
end
