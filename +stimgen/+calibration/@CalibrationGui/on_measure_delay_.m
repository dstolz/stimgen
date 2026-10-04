function on_measure_delay_(obj)
if ~obj.apply_controls_to_engine_()
    return
end
obj.with_busy_state_(@() obj.run_measure_delay_(), ...
    'Measuring conduction delay...', true);
end
