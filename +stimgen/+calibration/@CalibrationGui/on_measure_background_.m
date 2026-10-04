function on_measure_background_(obj)
if ~obj.apply_controls_to_engine_()
    return
end
[p, wasCancelled] = obj.prompt_background_parameters_();
if wasCancelled
    obj.set_status_('Background measurement cancelled.', false);
    return
end
obj.with_busy_state_(@() obj.run_measure_background_(p), ...
    'Recording background...', true);
end
