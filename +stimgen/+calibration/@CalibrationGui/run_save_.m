function ffn = run_save_(obj, ffn)
arguments
    obj
    ffn (1,:) char = ''
end
% The notes go in the file, so they have to reach the engine
% before it writes one.
obj.commit_notes_();
ffn = obj.Engine.save(ffn);
if isempty(ffn)
    obj.set_status_('Save cancelled.', false);
    return
end
obj.Dirty_ = false;
obj.add_recent_calibration_(ffn);
obj.set_status_('Calibration saved.', false);
end
