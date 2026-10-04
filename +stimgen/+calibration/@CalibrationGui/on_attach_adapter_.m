function on_attach_adapter_(obj)
obj.with_busy_state_(@() obj.run_attach_adapter_(), 'Attaching adapter...');
end
