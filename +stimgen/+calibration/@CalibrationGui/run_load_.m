function run_load_(obj, ffn)
arguments
    obj
    ffn (1,:) char = ''
end
if ~isempty(ffn) && ~isfile(ffn)
    obj.remove_recent_calibration_(ffn);
    obj.set_status_(sprintf('Recent calibration not found: %s', ffn), true);
    return
end

prevAdapter = obj.Engine.Adapter;
[eng, ffn] = stimgen.calibration.Engine.load(ffn);
if isempty(eng)
    obj.set_status_('Load cancelled.', false);
    return
end
if ~isempty(prevAdapter)
    eng.set_adapter(prevAdapter);
end
obj.Engine = eng;
% The monitor follows an engine, not this object; a load that
% swaps the engine has to move it across or it would keep
% rendering the discarded one. The delay listener follows the
% engine the same way.
obj.Monitor.attach(eng);
obj.bind_engine_listeners_();
obj.sync_controls_();
obj.refresh_all_plots_();
obj.update_runtime_state_();
obj.Dirty_ = false;
obj.add_recent_calibration_(ffn);
obj.set_status_('Calibration loaded.', false);
end
