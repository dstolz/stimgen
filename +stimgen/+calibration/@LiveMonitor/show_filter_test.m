function show_filter_test(obj, eng)
% show_filter_test(obj, eng)
% Draw the equalization filter test an engine has recorded, on the panel the
% test owns.
%
% The off-run counterpart to the live sweep render_transfer_ leaves on this
% panel, and the reason the panel exists. A filter test measures one thing
% twice -- the rig's response to a chirp, and the same rig's response to that
% chirp through the filter -- and the verdict is the COMPARISON, which no
% single live curve can carry: the run draws the unfiltered sweep, then draws
% the filtered one over it, and what the operator is left with is the second
% of two measurements whose difference was the point.
%
% Two axes, where the host gave a detail panel:
%   - levels in dB SPL, both conditions, which is where an equalizer that
%     bought its flatness by throwing output away shows up. The filtered
%     chirp is renormalized to peak before it is played, as apply_calibration
%     does, so the offset between the curves is that renormalization rather
%     than a gain error;
%   - underneath, each condition's deviation from its own band mean, which is
%     the flatness the test is judged on, with the tolerance drawn across it
%     as the +/- half-ripple band a passing response fits inside.
%
% Nothing here is live: the comparison exists only once both conditions have
% been measured, so this fills in when the run ends and is redrawn from
% CalibrationData.filterTest afterwards -- including for a test loaded from a
% .esgc, which is otherwise readable only through describe().
%
% Parameters:
%   eng - stimgen.calibration.Engine
arguments
    obj
    eng (1,1) stimgen.calibration.Engine
end

ax = obj.panel_axes_("filter_test");
if ~isgraphics(ax)
    return
end

r = [];
C = eng.CalibrationData;
if isstruct(C) && isfield(C, 'filterTest') && ~isempty(C.filterTest)
    r = C.filterTest;
end

% A host that gave this view no panel of its own is drawing it over a
% stimulus panel. Blanking that to report a filter test nobody has run would
% take a lookup table down with it, so a shared panel is left alone until
% there is something to put on it.
shared = isequal(ax, obj.AxTone) || isequal(ax, obj.AxClick) || ...
    isequal(ax, obj.AxSweptSine);
if isempty(r) && shared
    return
end

obj.clear_for_("filter_test");

% Both conditions, in the order they are read: the rig as it is, then the rig
% through the filter.
specs = { ...
    'unfiltered', 'speaker alone',  [0.75 0.30 0.10], '--'; ...
    'filtered',   'through filter', [0.10 0.25 0.60], '-'};

draw_levels_(obj, ax, eng, r, specs);
draw_flatness_(obj, r, specs);
end

% ------------------------------------------------------------------------ %
function draw_levels_(obj, ax, eng, r, specs)
% The two response curves in dB SPL, on the panel's main axes.
k = @(name) char("filter_test_" + name);

yyaxis(ax, 'left');
% A live sweep on this panel may have left a manual ylim or a right-hand
% drive-voltage axis behind; neither belongs to this view.
ax.YLimMode = 'auto';
ylabel(ax, 'level (dB SPL)');
grid(ax, 'on');
hide_voltage_(ax);

if isempty(r)
    % Ticks left alone and the label left in hertz: there is no curve to
    % place a frequency grid around, and an empty axis relabelled in kHz
    % reads as a measurement of something rather than as the placeholder it
    % is.
    obj.render_weighting_("filter_test", [], []);
    xlabel(ax, 'frequency (Hz)');
    stimgen.calibration.LiveMonitor.caption_(ax, 'Filter test  (not run)');
    return
end

f = double(r.frequency(:).');
for i = 1:size(specs, 1)
    y = double(r.(specs{i,1}).spl_db(:).');
    ok = isfinite(f) & isfinite(y);
    h = obj.gobj_(k("ft_" + specs{i,1}), @() line(ax, NaN, NaN, ...
        LineStyle=specs{i,4}, Color=specs{i,3}, LineWidth=1.25, ...
        DisplayName=specs{i,2}));
    set(h, XData=f(ok), YData=y(ok));
end

apply_frequency_axis_(obj, ax, f);

% The unfiltered curve anchors any weighting overlay: it is the rig as it
% is, which is what a weighting is read against.
obj.render_weighting_("filter_test", f, double(r.unfiltered.spl_db(:).'));

% After the limits, which the tick grid is placed within.
xlabel(ax, stimgen.calibration.LiveMonitor.frequency_ticks_(ax, 'frequency (Hz)'));

if r.passed
    head = 'Filter test  (passed)';
    color = [0.10 0.45 0.20];
else
    head = 'Filter test  (failed)';
    color = [0.70 0.10 0.10];
end
stimgen.calibration.LiveMonitor.caption_(ax, head, level_subtitle_(eng, r), color);

hLeg = obj.gobj_(k('ft_legend'), @() legend(ax, Location='southwest', ...
    AutoUpdate='off', FontSize=8));
hLeg.Visible = 'on';
end

% ------------------------------------------------------------------------ %
function draw_flatness_(obj, r, specs)
% Deviation from each condition's own band mean, with the pass criterion
% across it. Read here rather than off the level panel above: the two
% conditions sit at different absolute levels, and two shapes an offset apart
% cannot be compared by eye.
ax = obj.detail_axes_("filter_test", 1);
if isempty(ax)
    return
end
k = @(name) char("filter_test_" + name);

grid(ax, 'on');
ylabel(ax, 'deviation (dB)');

if isempty(r)
    for key = ["ft_dev_unfiltered", "ft_dev_filtered", "ft_tol", "ft_ref", ...
            "ft_det_legend"]
        obj.drop_(k(key));
    end
    xlabel(ax, 'frequency (Hz)');
    stimgen.calibration.LiveMonitor.caption_(ax, ...
        'Flatness before & after  (not run)');
    return
end

f = double(r.frequency(:).');
span = [min(f) * 0.9, max(f) * 1.1];

% The tolerance band and the zero line first, so the curves read over them.
% Half the ripple tolerance either side of flat: the criterion is a
% peak-to-peak span, and a response that stays inside this band has one no
% wider than it.
tol = tolerance_db_(r) / 2;
hTol = obj.gobj_(k('ft_tol'), @() patch(ax, XData=NaN, YData=NaN, ...
    FaceColor=[0.20 0.55 0.25], FaceAlpha=0.10, EdgeColor='none', ...
    HandleVisibility='off'));
set(hTol, XData=[span, fliplr(span)], YData=[tol tol -tol -tol]);

hRef = obj.gobj_(k('ft_ref'), @() line(ax, NaN, NaN, LineStyle=':', ...
    Color=[0.60 0.60 0.60], LineWidth=0.75, HandleVisibility='off'));
set(hRef, XData=span, YData=[0 0]);

for i = 1:size(specs, 1)
    y = double(r.(specs{i,1}).deviation_db(:).');
    ok = isfinite(f) & isfinite(y);
    h = obj.gobj_(k("ft_dev_" + specs{i,1}), @() line(ax, NaN, NaN, ...
        LineStyle=specs{i,4}, Color=specs{i,3}, LineWidth=1, ...
        DisplayName=specs{i,2}));
    set(h, XData=f(ok), YData=y(ok));
end

apply_frequency_axis_(obj, ax, f);
xlabel(ax, stimgen.calibration.LiveMonitor.frequency_ticks_(ax, 'frequency (Hz)'));

stimgen.calibration.LiveMonitor.caption_(ax, 'Flatness before & after', ...
    sprintf('ripple %.1f \x2192 %.1f dB   SD %.1f \x2192 %.1f dB   shaded: %.1f dB tolerance', ...
    r.unfiltered.ripple_db, r.filtered.ripple_db, ...
    r.unfiltered.flatness_std_db, r.filtered.flatness_std_db, ...
    tolerance_db_(r)));

hLeg = obj.gobj_(k('ft_det_legend'), @() legend(ax, Location='best', ...
    AutoUpdate='off', FontSize=8, NumColumns=2));
hLeg.Visible = 'on';
end

% ------------------------------------------------------------------------ %
function apply_frequency_axis_(obj, ax, f)
% Scale and limits, the same on both axes so one reads against the other.
if obj.LogX
    set(ax, XScale='log');
else
    set(ax, XScale='linear');
end
if numel(f) > 1 && all(isfinite([min(f) max(f)]))
    xlim(ax, [min(f) * 0.93, max(f) * 1.07]);
end
end

% ------------------------------------------------------------------------ %
function hide_voltage_(ax)
% Retire the right-hand drive-voltage axis a live sweep leaves on this panel.
% This view has no voltage to put there, and an empty scale beside the curves
% says one was measured and was zero.
if numel(ax.YAxis) < 2
    return
end
yyaxis(ax, 'right');
ylabel(ax, '');
ax.YAxis(2).Visible = 'off';
yyaxis(ax, 'left');
end

% ------------------------------------------------------------------------ %
function v = tolerance_db_(r)
% The pass criterion the test was run under. Defaulted rather than assumed
% present: it is the one number here that a record written before it existed
% would not carry, and its absence must not take the panel down.
v = 6;
if isfield(r, 'ripple_tolerance_db') && isscalar(r.ripple_tolerance_db) && ...
        isfinite(r.ripple_tolerance_db)
    v = double(r.ripple_tolerance_db);
end
end

% ------------------------------------------------------------------------ %
function sub = level_subtitle_(eng, r)
% What the test bought, what it covered, and what it was run under -- then
% when. The date is the TEST's, not the calibration's: a filter may be tested
% long after the table it was cut from was measured.
parts = {sprintf('ripple %.1f \x2192 %.1f dB (tolerance %.1f dB)', ...
    r.unfiltered.ripple_db, r.filtered.ripple_db, tolerance_db_(r))};

if isfield(r, 'band') && numel(r.band) == 2 && all(isfinite(r.band))
    parts{end+1} = sprintf('%g\x2013%g Hz', r.band(1), r.band(2));
end
if isfield(r, 'repeat_count') && isfield(r, 'duration')
    parts{end+1} = sprintf('%d \x00d7 %.3g s @ %.3g V', ...
        r.repeat_count, r.duration, r.excitation_voltage);
end

stamp = '';
if isfield(r, 'testedOn') && isdatetime(r.testedOn) && ...
        isscalar(r.testedOn) && ~isnat(r.testedOn)
    stamp = sprintf('tested %s', ...
        char(datetime(r.testedOn, Format='dd-MMM-yyyy HH:mm')));
end
if isempty(stamp)
    stamp = stimgen.calibration.LiveMonitor.calibration_stamp_(eng);
end

sub = {strjoin(parts, sprintf('  \x00b7  ')), stamp};
end
