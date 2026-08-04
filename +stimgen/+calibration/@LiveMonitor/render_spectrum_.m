function render_spectrum_(obj, d)
% render_spectrum_(obj, d)
% Spectrum panel, in dB SPL rather than raw power so it reads on the same
% scale as the calibration itself.
%
% Adds three things the old fixed-limit power plot could not show:
%   - the previous measurement as a grey ghost, which turns run-to-run drift
%     and a flaky connection into something visible rather than inferred;
%   - markers at the fundamental and its 2nd and 3rd harmonics, so distortion
%     is located, not just summarized as a THD number;
%   - a noise-floor line, and y-limits derived from the data instead of a
%     hardcoded [-20 120] that hid everything on a quiet or hot channel.
%
% Only the analysed span is transformed when one is given: that is the signal
% the LUT point was actually computed from, and including the ramps and gaps
% around it would smear the very peak being measured.

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
    obj.drop_('spec_ghost');
    obj.drop_('spec_current');
    obj.drop_('spec_floor');
    obj.drop_('spec_marks');
    delete_texts_(obj);
    title(ax, 'Spectrum  (no data)');
    return
end

[f, lvl] = stimgen.calibration.LiveMonitor.spectrum_db_spl_( ...
    y, fs, d.Context.ReferenceLevel, d.Context.MicSensitivity, obj.SpectrumBins);

if obj.ShowGhost && ~isempty(obj.PrevSpectrum_{1})
    hGhost = obj.gobj_('spec_ghost', @() line(ax, NaN, NaN, ...
        Color=[0.72 0.72 0.76], LineWidth=0.5, DisplayName='previous'));
    set(hGhost, XData=obj.PrevSpectrum_{1}, YData=obj.PrevSpectrum_{2});
end
obj.PrevSpectrum_ = {f, lvl};

hCur = obj.gobj_('spec_current', @() line(ax, NaN, NaN, ...
    Color=[0.65 0.12 0.12], LineWidth=0.75, DisplayName='response'));
set(hCur, XData=f, YData=lvl);

% Taken from the displayed curve rather than from the metrics struct, so the
% line always sits where the eye reads the floor to be.
floorDb = median(lvl, 'omitnan');
topDb   = max(lvl, [], 'omitnan');

hFloor = obj.gobj_('spec_floor', @() line(ax, NaN, NaN, LineStyle=':', ...
    Color=[0.35 0.35 0.35], LineWidth=0.75, HandleVisibility='off'));
set(hFloor, XData=[f(1) f(end)], YData=[floorDb floorDb]);

lo = floor((min(floorDb, topDb - 30) - 6) / 10) * 10;
hi = ceil((topDb + 8) / 10) * 10;
ylim(ax, [lo max(hi, lo + 30)]);
xlim(ax, [max(f(1), 20) fs / 2]);
set(ax, XScale='log');

render_markers_(obj, ax, d, f, lvl, lo, hi);

grid(ax, 'on');
xlabel(ax, 'frequency (Hz)');
ylabel(ax, 'level (dB SPL)');
title(ax, spectrum_title_(d, floorDb));
end

% ------------------------------------------------------------------------ %
function render_markers_(obj, ax, d, f, lvl, lo, hi)
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

% One text object per marker, cached by slot so a run with fewer markers
% releases the leftovers instead of stacking labels on top of each other.
for k = 1:numel(marks)
    key = sprintf('spec_txt%d', k);
    h = obj.gobj_(key, @() text(ax, NaN, NaN, '', ...
        Color=[0.20 0.45 0.85], FontSize=8, ...
        HorizontalAlignment='center', VerticalAlignment='bottom', ...
        Clipping='on'));
    lvlAt = level_at_(f, lvl, marks(k));
    set(h, Position=[marks(k), min(lvlAt + 2, hi - 2), 0], ...
        String=sprintf('%s %.0f', labels(k), lvlAt));
end
for k = numel(marks)+1 : 8
    obj.drop_(sprintf('spec_txt%d', k));
end
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
function s = spectrum_title_(d, floorDb)
% Summarize the measurement in the title: the level the LUT will record, plus
% whichever of SNR/THD the stage actually estimated.
parts = {'Spectrum'};
if isfinite(d.Metrics.spl_db)
    parts{end+1} = sprintf('%.1f dB SPL', d.Metrics.spl_db);
end
if isfinite(d.Metrics.snr_db)
    parts{end+1} = sprintf('SNR %.0f dB', d.Metrics.snr_db);
end
if isfinite(d.Metrics.thd_db)
    parts{end+1} = sprintf('THD %.0f dB', d.Metrics.thd_db);
end
parts{end+1} = sprintf('floor %.0f dB SPL', floorDb);
s = strjoin(parts, '  |  ');
end
