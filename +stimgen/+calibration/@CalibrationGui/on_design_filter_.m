function on_design_filter_(obj)
[source, opts, wasCancelled] = obj.prompt_filter_parameters_();
if wasCancelled
    obj.set_status_('Filter design cancelled.', false);
    return
end
obj.with_busy_state_(@() obj.run_design_filter_(source, opts), 'Designing filter...');
end
