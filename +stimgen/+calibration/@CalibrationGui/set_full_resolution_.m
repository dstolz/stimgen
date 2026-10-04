function set_full_resolution_(obj, tf)
% Draw the time-domain panels at every sample (tf true) or as a
% min/max envelope (false, the default). The menu item is the
% inverse of the monitor's DecimateWaveforms, which names the
% mechanism; the menu names what the operator gets.
%
% Both panels that carry a waveform are redrawn, so the change
% shows on the record already on screen rather than at the next
% measurement -- which is the point, since this is turned on to
% look harder at a record that has already been acquired.
obj.Monitor.DecimateWaveforms = ~tf;
obj.sync_display_controls_();
obj.Monitor.show_engine_state(obj.Engine);
obj.Monitor.show_latency(obj.LastLatency_);
if tf
    obj.set_status_(['Waveforms at full resolution. ' ...
        'Redraws are slower on long records.'], false);
else
    obj.set_status_('Waveforms drawn as a min/max envelope.', false);
end
end
