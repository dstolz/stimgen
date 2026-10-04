function s = conduction_delay_summary(d)
% s = stimgen.calibration.Engine.conduction_delay_summary(d)
% One-line status-bar summary of a standalone conduction delay probe.
if d.valid
    s = sprintf('Conduction delay: %.2f ms (~%.2f m of air at %.1f m/s, %.1f °C).', ...
        d.delay_s * 1e3, d.path_m, d.speed_of_sound_ms, d.temperature_c);
else
    s = 'Conduction delay could not be measured -- see the report.';
end
end
