function on_test_filter_(obj)
obj.with_busy_state_(@() obj.run_test_filter_(), 'Testing filter...', true);
end
