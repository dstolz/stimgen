function refresh_conduction_delay_label_(obj)
% Speaker-to-mic delay from the most recent click probe. The
% equivalent air path is the sanity check -- a reading far from the
% actual mic distance means converter latency dominates, or the
% probe locked onto the wrong thing. The speed it is converted at
% is the one the reading was taken under, carried on the reading
% itself, so a temperature changed since does not restate an old
% measurement as a distance it never implied.
% Guarded rather than ordered: update_runtime_state_ may run
% before the footer is built.
if isempty(obj.ConductionDelayLabel) || ~isvalid(obj.ConductionDelayLabel)
    return
end
d = obj.Engine.ConductionDelay;
if d.valid
    txt = sprintf('%.2f ms  (~%.2f m at %.0f m/s)', ...
        d.delay_s * 1e3, d.path_m, d.speed_of_sound_ms);
    obj.ConductionDelayLabel.FontColor = [0 0 0];
elseif d.at_bound || isfinite(d.delay_s)
    txt = 'Measurement unreliable';
    obj.ConductionDelayLabel.FontColor = [0.7 0 0];
else
    txt = 'Not measured';
    obj.ConductionDelayLabel.FontColor = [0 0 0];
end
obj.ConductionDelayLabel.Text = txt;
end
