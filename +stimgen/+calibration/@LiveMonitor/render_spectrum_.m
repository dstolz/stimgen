function render_spectrum_(obj, d)
% render_spectrum_(obj, d)
% Spectrum panel, drawn in whichever of the SpectrumUnits the caller selected.
% The default, dB SPL, reads on the same scale as the calibration itself.
%
% Adds four things the old fixed-limit power plot could not show:
%   - the previous measurement as a grey ghost, which turns run-to-run drift
%     and a flaky connection into something visible rather than inferred;
%   - markers at the fundamental and its 2nd and 3rd harmonics, so distortion
%     is located, not just summarized as a THD number;
%   - a noise-floor line, and y-limits derived from the data instead of a
%     hardcoded [-20 120] that hid everything on a quiet or hot channel;
%   - electrical, per-Hz and peak-relative units alongside dB SPL, so the same
%     record answers whether the input stage is clipping, how the floor
%     compares across analysis windows, and what the shape is on a rig whose
%     reference has not been measured yet.
%
% Only the analysed span is transformed when one is given: that is the signal
% the LUT point was actually computed from, and including the ramps and gaps
% around it would smear the very peak being measured.
%
% The measurement is kept in volts and converted at draw time, so the ghost
% follows a unit change instead of being left behind on the old scale.

ax = obj.AxSpectrum;
fs = d.Fs;
y  = d.Response;

if numel(d.Span) == 2 && all(isfinite(d.Span))
    a = max(round(d.Span(1)), 1);
    b = min(round(d.Span(2)), numel(y));
    if b - a > 32
        y = y(a:b);
    end
end

if isempty(y) || fs <= 0
    clear_spectrum_(obj);
    stimgen.calibration.LiveMonitor.caption_(ax, 'Spectrum  (no data)');
    return
end

% The payload's own analysis settings, not the engine's current ones: a
% record is drawn the way it was measured, so a setting changed after a run
% does not silently restate what that run found.
[f, vrms, noiseBw] = stimgen.calibration.LiveMonitor.spectrum_vrms_( ...
    y, fs, obj.SpectrumBins, ...
    stimgen.calibration.SpectralOptions.fromStruct(d.Context));
if isempty(f)
    clear_spectrum_(obj);
    stimgen.calibration.LiveMonitor.caption_(ax, 'Spectrum  (no data)');
    return
end

convert = @(v) stimgen.calibration.LiveMonitor.convert_spectrum_(v, ...
    obj.SpectrumUnits, d.Context.ReferenceLevel, d.Context.MicSensitivity, noiseBw);
[lvl, info] = convert(vrms);

% The ghost advances only when the record itself is new. Redrawing the same
% record -- which is what a unit change does -- would otherwise promote it to
% its own ghost and lay a grey copy over the trace it is meant to be compared
% against, so the record on screen is held separately from the one behind it.
fingerprint = [numel(y), y(1), y(round(end/2)), y(end)];
if ~isequal(fingerprint, obj.LastRecord_)
    obj.PrevSpectrum_ = obj.CurrSpectrum_;
    obj.CurrSpectrum_ = {f, vrms};
    obj.LastRecord_ = fingerprint;
end

if obj.ShowGhost && ~isempty(obj.PrevSpectrum_{1})
    hGhost = obj.gobj_('spec_ghost', @() line(ax, NaN, NaN, ...
        Color=[0.72 0.72 0.76], LineWidth=0.5, DisplayName='previous'));
    set(hGhost, XData=obj.PrevSpectrum_{1}, YData=convert(obj.PrevSpectrum_{2}));
end

hCur = obj.gobj_('spec_current', @() line(ax, NaN, NaN, ...
    Color=[0.65 0.12 0.12], LineWidth=0.75, DisplayName='response'));
set(hCur, XData=f, YData=lvl);

% Taken from the displayed curve rather than from the metrics struct, so the
% line always sits where the eye reads the floor to be.
floorVal = median(lvl, 'omitnan');
topVal   = max(lvl, [], 'omitnan');

hFloor = obj.gobj_('spec_floor', @() line(ax, NaN, NaN, LineStyle=':', ...
    Color=[0.35 0.35 0.35], LineWidth=0.75, HandleVisibility='off'));
set(hFloor, XData=[f(1) f(end)], YData=[floorVal floorVal]);

% A spectrum spans tens of dB whatever it is measured in, so the linear units
% get a log y-axis: on a linear one the noise floor lies on the axis and only
% the fundamental is visible, which is not what someone reading volts is after.
% The scale is set before the limits -- a dB view's negative limits are not
% assignable while the axis is still logarithmic from the last unit.
[lo, hi] = y_limits_(floorVal, topVal, info.IsDb);
if info.IsDb
    set(ax, YScale='linear');
else
    set(ax, YScale='log');
end
ylim(ax, [lo hi]);
xlim(ax, [max(f(1), 20) fs / 2]);
set(ax, XScale='log');

render_markers_(obj, ax, d, f, lvl, lo, hi, info);

grid(ax, 'on');
xlabel(ax, stimgen.calibration.LiveMonitor.frequency_ticks_(ax, 'frequency (Hz)'));
ylabel(ax, info.Label);
stimgen.calibration.LiveMonitor.caption_(ax, 'Spectrum', ...
    spectrum_subtitle_(d, floorVal, info));
end

% ------------------------------------------------------------------------ %
function [lo, hi] = y_limits_(floorVal, topVal, isDb)
% Decade-rounded limits around the measurement on a dB scale. A linear unit is
% drawn on a log axis instead, so its limits are a decade below the floor and
% half again above the peak -- the same span the dB view shows, with headroom
% for the marker labels.
if isDb
    if ~isfinite(topVal)
        lo = 0;
        hi = 1;
        return
    end
    if ~isfinite(floorVal)
        floorVal = topVal - 30;
    end
    lo = floor((min(floorVal, topVal - 30) - 6) / 10) * 10;
    hi = ceil((topVal + 8) / 10) * 10;
    hi = max(hi, lo + 30);
    return
end

if ~isfinite(topVal) || topVal <= 0
    lo = eps;
    hi = 1;
    return
end
if ~isfinite(floorVal) || floorVal <= 0
    floorVal = topVal / 1e3;
end
lo = min(floorVal / 10, topVal / 10);
hi = topVal * 1.5;
end

% ------------------------------------------------------------------------ %
function render_markers_(obj, ax, d, f, lvl, lo, hi, info)
% Vertical rules with labels at the fundamental and its harmonics. One line
% object carries all of them, separated by NaN, so the count of graphics
% objects does not grow with the number of markers.
marks = d.Markers(isfinite(d.Markers) & d.Markers > 0 & d.Markers < d.Fs / 2);
if isempty(marks)
    obj.drop_('spec_marks');
    delete_texts_(obj);
    return
end

xd = [marks; marks; NaN(1, numel(marks))];
yd = repmat([lo; hi; NaN], 1, numel(marks));
hM = obj.gobj_('spec_marks', @() line(ax, NaN, NaN, LineStyle='--', ...
    Color=[0.20 0.45 0.85], LineWidth=0.75, HandleVisibility='off'));
set(hM, XData=xd(:).', YData=yd(:).');

labels = d.MarkerLabels;
if numel(labels) < numel(marks)
    labels = [labels, repmat("", 1, numel(marks) - numel(labels))];
end

% The label sits a fixed fraction of the visible height above its peak, which
% on a log axis is a ratio and on a linear one an offset -- otherwise a dB
% label's clearance would be a decade once the axis is drawn in volts.
if info.IsDb
    place = @(v) min(v + 0.03 * (hi - lo), hi - 0.03 * (hi - lo));
else
    grow = (hi / lo) ^ 0.03;
    place = @(v) min(v * grow, hi / grow);
end

% One text object per marker, cached by slot so a run with fewer markers
% releases the leftovers instead of stacking labels on top of each other.
for k = 1:numel(marks)
    key = sprintf('spec_txt%d', k);
    h = obj.gobj_(key, @() text(ax, NaN, NaN, '', ...
        Color=[0.20 0.45 0.85], FontSize=8, ...
        HorizontalAlignment='center', VerticalAlignment='bottom', ...
        Clipping='on'));
    lvlAt = level_at_(f, lvl, marks(k));
    set(h, Position=[marks(k), place(lvlAt), 0], ...
        String=sprintf('%s %s', labels(k), sprintf(info.Format, lvlAt)));
end
for k = numel(marks)+1 : 8
    obj.drop_(sprintf('spec_txt%d', k));
end
end

% ------------------------------------------------------------------------ %
function clear_spectrum_(obj)
% Release every object this panel owns, for the cases with nothing to draw.
obj.drop_('spec_ghost');
obj.drop_('spec_current');
obj.drop_('spec_floor');
obj.drop_('spec_marks');
delete_texts_(obj);
end

% ------------------------------------------------------------------------ %
function delete_texts_(obj)
% Release every cached marker label.
for k = 1:8
    obj.drop_(sprintf('spec_txt%d', k));
end
end

% ------------------------------------------------------------------------ %
function v = level_at_(f, lvl, freq)
% Displayed level nearest freq. The curve is peak-held onto a log grid, so
% the nearest bin already carries the peak of the band around it.
[~, i] = min(abs(f - freq));
v = lvl(i);
end

% ------------------------------------------------------------------------ %
function s = spectrum_subtitle_(d, floorVal, info)
% Summarize the measurement in the subtitle: the level the LUT will record,
% plus whichever of SNR/THD the stage actually estimated. Those three are dB
% SPL and dB ratios whatever the axis is showing; only the floor follows the
% units.
parts = {};
if isfinite(d.Metrics.spl_db)
    parts{end+1} = sprintf('%.1f dB SPL', d.Metrics.spl_db);
end
if isfinite(d.Metrics.snr_db)
    parts{end+1} = sprintf('SNR %.0f dB', d.Metrics.snr_db);
end
if isfinite(d.Metrics.thd_db)
    parts{end+1} = sprintf('THD %.0f dB', d.Metrics.thd_db);
end
parts{end+1} = sprintf('floor %s %s', sprintf(info.Format, floorVal), info.Suffix);
s = strjoin(parts, '  ·  ');
end
