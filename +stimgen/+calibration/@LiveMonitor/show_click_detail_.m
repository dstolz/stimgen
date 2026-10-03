function show_click_detail_(obj, eng)
% show_click_detail_(obj, eng)
% Signal-to-noise against click duration, under the click panel.
%
% The same reading as the tone panel's detail axes, against the abscissa a
% click table is keyed on. It answers the question that decides a click
% series: the shortest clicks put the least energy into the room, so SNR
% falls as duration does, and where it falls into the noise is where the
% short end of the table stops meaning anything. No distortion is drawn: one
% impulse has no fundamental to refer a THD or a harmonic to. A table saved
% before the sweep stopped computing one still carries thd_db (and NaN
% h2_db/h3_db); those are stripped here rather than drawn.
%
% Nothing here is live; see show_tone_detail_.
%
% Parameters:
%   eng - stimgen.calibration.Engine
arguments
    obj
    eng (1,1) stimgen.calibration.Engine
end

ax = obj.detail_axes_("click", 1);
if isempty(ax)
    return
end

% Durations in microseconds, the unit the click panel's x-axis is in, so the
% detail panel below it lines up with the table above.
m = stimgen.calibration.LiveMonitor.lut_metrics_(eng, "click");
x = [];
C = eng.CalibrationData;
if ~isempty(m) && isstruct(C) && isfield(C, 'click') && ~isempty(C.click)
    x = C.click.duration(:).' .* 1e6;
end

if isstruct(m)
    drop = intersect(fieldnames(m), {'thd_db', 'h2_db', 'h3_db'});
    if ~isempty(drop)
        m = rmfield(m, drop);
    end
end
obj.draw_quality_panel_(ax, "click", x, m, ...
    'click duration (\mus)', 'Click SNR');
end
