function show_swept_detail_(obj, eng)
% show_swept_detail_(obj, eng)
% The two detail axes under the swept sine panel: how flat and how linear in
% phase the rig is across frequency, and the impulse response the sweep
% deconvolved.
%
% A swept sine is the only calibration here that measures the rig rather than
% a list of points. Deconvolving the recorded sweep against the excitation
% yields a continuous transfer function and, from it, an impulse response --
% so what the lookup table shows (a level per frequency) is a thin summary of
% what was actually measured. Everything on these two panels comes free with
% the sweep and, until now, only existed in the saved file:
%
%   - magnitude deviation from the mean, on the fine deconvolved grid rather
%     than the table's points. This is what "flat" means and where a rig's
%     ripple actually lives -- a resonance narrower than the table's spacing
%     does not appear in the table at all;
%   - group delay on the same axis, because a rig can be flat and still smear
%     a transient, and the two are read together or not at all;
%   - the impulse response, with its arrival and first reflection marked. In
%     a small enclosure the first reflection is usually the largest thing
%     wrong with the acoustics, and it is visible here and nowhere else.
%
% Nothing here is live: the deconvolution happens when the sweep is
% committed, not per measurement.
%
% Parameters:
%   eng - stimgen.calibration.Engine
arguments
    obj
    eng (1,1) stimgen.calibration.Engine
end

m = stimgen.calibration.LiveMonitor.lut_metrics_(eng, "swept_sine");
draw_response_(obj, m);
draw_impulse_(obj, m);
end

% ------------------------------------------------------------------------ %
function draw_response_(obj, m)
% Magnitude deviation and group delay against frequency, on two y-axes.
%
% Two scales here rather than the one the tone detail panel uses, because
% these are decibels and milliseconds: there is no shared unit to put them
% on, and the comparison being made is of SHAPE -- where the ripple is
% against where the delay moves -- which two axes serve.
ax = obj.detail_axes_("swept_sine", 1);
if isempty(ax)
    return
end
k = @(name) char("swept_sine_" + name);

f = [];
if isstruct(m) && isfield(m, 'frequency_response_hz')
    f = double(m.frequency_response_hz(:)).';
end
dev = field_(m, 'magnitude_deviation_db', numel(f));
gd  = field_(m, 'group_delay_seconds', numel(f));

grid(ax, 'on');
if isempty(f) || (isempty(dev) && isempty(gd))
    obj.drop_(k('dev'));
    obj.drop_(k('gd'));
    obj.drop_(k('gd_bulk'));
    obj.drop_(k('gd_legend'));
    xlabel(ax, 'frequency (Hz)');
    ylabel(ax, 'deviation (dB)');
    stimgen.calibration.LiveMonitor.caption_(ax, ...
        'Response flatness & group delay  (not measured)');
    return
end

yyaxis(ax, 'left');
ax.YLimMode = 'auto';
if isempty(dev)
    obj.drop_(k('dev'));
else
    h = obj.gobj_(k('dev'), @() line(ax, NaN, NaN, LineStyle='-', ...
        Color=[0.20 0.55 0.25], LineWidth=1, DisplayName='magnitude deviation'));
    set(h, XData=f, YData=dev);
end
ylabel(ax, 'deviation (dB)');

yyaxis(ax, 'right');
ax.YAxis(2).Visible = 'on';
ax.YLimMode = 'auto';
set(ax, YScale='linear');
if isempty(gd)
    obj.drop_(k('gd'));
    obj.drop_(k('gd_bulk'));
else
    h = obj.gobj_(k('gd'), @() line(ax, NaN, NaN, LineStyle='-', ...
        Color=[0.55 0.20 0.60], LineWidth=0.9, DisplayName='group delay'));
    set(h, XData=f, YData=gd .* 1e3);

    % The bulk delay is the rig's flight time, the same at every frequency;
    % drawn so the curve above it reads as the DISPERSION it is rather than
    % as a delay that has to be mentally offset.
    bulk = scalar_(m, 'bulk_delay_s');
    if isfinite(bulk)
        hB = obj.gobj_(k('gd_bulk'), @() line(ax, NaN, NaN, LineStyle=':', ...
            Color=[0.55 0.20 0.60] * 0.6 + 0.4, LineWidth=0.75, ...
            HandleVisibility='off'));
        set(hB, XData=[min(f) * 0.9, max(f) * 1.1], YData=[bulk bulk] .* 1e3);
    else
        obj.drop_(k('gd_bulk'));
    end
end
ylabel(ax, 'group delay (ms)');
ax.YAxis(2).Color = [0.55 0.20 0.60];
yyaxis(ax, 'left');

if obj.LogX
    set(ax, XScale='log');
else
    set(ax, XScale='linear');
end
xlim(ax, [min(f) * 0.93, max(f) * 1.07]);
xlabel(ax, stimgen.calibration.LiveMonitor.frequency_ticks_(ax, 'frequency (Hz)'));

stimgen.calibration.LiveMonitor.caption_(ax, ...
    'Response flatness & group delay', response_subtitle_(m));
hLeg = obj.gobj_(k('gd_legend'), @() legend(ax, Location='best', ...
    AutoUpdate='off', FontSize=8));
hLeg.Visible = 'on';
end

% ------------------------------------------------------------------------ %
function draw_impulse_(obj, m)
% The deconvolved impulse response, with what was picked out of it marked.
ax = obj.detail_axes_("swept_sine", 2);
if isempty(ax)
    return
end
k = @(name) char("swept_sine_" + name);

h = [];
t = [];
if isstruct(m) && isfield(m, 'impulse_response') && isfield(m, 'impulse_response_time_s')
    h = double(m.impulse_response(:)).';
    t = double(m.impulse_response_time_s(:)).' .* 1e3;
end

grid(ax, 'on');
ylabel(ax, 'amplitude (norm.)');
if numel(h) < 2 || numel(t) ~= numel(h)
    obj.drop_(k('ir'));
    obj.drop_(k('ir_arr'));
    obj.drop_(k('ir_refl'));
    obj.drop_(k('ir_legend'));
    xlabel(ax, 'time (ms)');
    stimgen.calibration.LiveMonitor.caption_(ax, ...
        'Impulse response  (not measured)');
    return
end

% Normalized to its own peak: the absolute scale is the excitation's and
% says nothing, while the ratio of the reflections to the direct sound --
% which is what this panel is read for -- is what normalizing preserves.
pk = max(abs(h));
if pk > 0
    h = h ./ pk;
end

hIr = obj.gobj_(k('ir'), @() line(ax, NaN, NaN, LineStyle='-', ...
    Color=[0.20 0.55 0.25], LineWidth=0.75, DisplayName='impulse response'));
set(hIr, XData=t, YData=h);

% Linear x, unlike every other panel here: an impulse response is read in
% time from its arrival, and the reflections that matter are the first few
% milliseconds after it. LogX belongs to the frequency panels.
set(ax, XScale='linear');
xlim(ax, [min(t), decay_limit_(t, h)]);
ylim(ax, [-1.1, 1.1]);
xlabel(ax, 'time (ms)');

draw_marker_(obj, ax, k('ir_arr'), scalar_(m, 'arrival_delay_s') * 1e3, ...
    [0.10 0.25 0.60], 'arrival');
draw_marker_(obj, ax, k('ir_refl'), first_reflection_ms_(m), ...
    [0.80 0.10 0.10], 'first reflection');

stimgen.calibration.LiveMonitor.caption_(ax, 'Impulse response', ...
    impulse_subtitle_(m));
hLeg = obj.gobj_(k('ir_legend'), @() legend(ax, Location='northeast', ...
    AutoUpdate='off', FontSize=8));
hLeg.Visible = 'on';
end

% ------------------------------------------------------------------------ %
function tMax = decay_limit_(t, h)
% Where to stop the time axis: the point the response has decayed 60 dB
% below its peak, with a little after it.
%
% The stored record runs to 1.5x RT60 so the decay analysis has a tail to
% fit, which for a damped enclosure is hundreds of milliseconds of noise
% floor after two milliseconds of signal. Drawn end to end, the direct
% sound and the reflections next to it are a single vertical line at the
% left edge -- the panel would be showing everything and revealing nothing.
% The tail is not discarded, only left off screen: the reverberation times
% it was kept for are in the subtitle, and zooming reaches the rest.
DECAY_DB = 60;
MIN_SPAN_MS = 2;

tMax = max(t);
env = abs(h);
pk = max(env);
if ~(pk > 0)
    return
end

last = find(env > pk * 10^(-DECAY_DB / 20), 1, 'last');
if isempty(last)
    return
end

% Padded by a quarter of what is shown, so the last thing above the floor
% is inside the panel rather than against its edge.
span = max(t(last) - min(t), MIN_SPAN_MS);
tMax = min(max(t), min(t) + span * 1.25);
end

% ------------------------------------------------------------------------ %
function draw_marker_(obj, ax, key, tMs, color, name)
% A vertical line at one time of interest, or nothing when it was not found.
if ~isfinite(tMs)
    obj.drop_(key);
    return
end
h = obj.gobj_(key, @() line(ax, NaN, NaN, LineStyle='--', Color=color, ...
    LineWidth=0.75, DisplayName=name));
set(h, XData=[tMs tMs], YData=[-1.1 1.1]);
end

% ------------------------------------------------------------------------ %
function v = first_reflection_ms_(m)
% Time of the first reflection after the direct sound, relative to the
% impulse response's own zero -- the reflection struct measures it from the
% direct arrival, which is where that zero already is.
v = nan;
if isstruct(m) && isfield(m, 'reflections') && isstruct(m.reflections) && ...
        isfield(m.reflections, 'first_delay_ms')
    v = double(m.reflections.first_delay_ms);
end
end

% ------------------------------------------------------------------------ %
function sub = response_subtitle_(m)
parts = {};
v = scalar_(m, 'magnitude_ripple_db');
if isfinite(v)
    parts{end+1} = sprintf('%.1f dB ripple', v);
end
v = scalar_(m, 'flatness_std_db');
if isfinite(v)
    parts{end+1} = sprintf('%.1f dB sd', v);
end
v = scalar_(m, 'group_delay_variation_s');
if isfinite(v)
    parts{end+1} = sprintf('%.2f ms delay variation', v * 1e3);
end
sub = join_(parts);
end

% ------------------------------------------------------------------------ %
function sub = impulse_subtitle_(m)
parts = {};
v = scalar_(m, 'rt60_s');
if isfinite(v)
    parts{end+1} = sprintf('RT60 %.0f ms', v * 1e3);
end
v = scalar_(m, 'c50_db');
if isfinite(v)
    parts{end+1} = sprintf('C50 %.1f dB', v);
end
v = scalar_(m, 'drr_db');
if isfinite(v)
    parts{end+1} = sprintf('DRR %.1f dB', v);
end
if isstruct(m) && isfield(m, 'record_truncated') && m.record_truncated
    % The decay never reached the noise floor, so every reverberation time
    % above is a lower bound. Said on the panel, not only in the log the
    % sweep wrote, because this is where those numbers get read.
    parts{end+1} = 'decay truncated: times are lower bounds';
end
sub = join_(parts);
end

% ------------------------------------------------------------------------ %
function s = join_(parts)
if isempty(parts)
    s = '';
else
    s = strjoin(parts, '  ·  ');
end
end

% ------------------------------------------------------------------------ %
function v = scalar_(m, name)
% One scalar metric, or NaN when the table predates it.
v = nan;
if isstruct(m) && isfield(m, name) && isscalar(m.(name)) && isnumeric(m.(name))
    v = double(m.(name));
end
end

% ------------------------------------------------------------------------ %
function v = field_(m, name, n)
% One vector metric as a row, or empty when it is absent or does not match
% the frequency grid it has to be drawn against.
v = [];
if ~isstruct(m) || ~isfield(m, name)
    return
end
c = double(m.(name)(:)).';
if numel(c) == n && any(isfinite(c))
    v = c;
end
end
