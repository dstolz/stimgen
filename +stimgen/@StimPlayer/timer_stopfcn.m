function timer_stopfcn(obj, ~, ~)
% timer_stopfcn(obj) - Called when the playback timer stops.
% Resets button states and updates the counter.

obj.Paused_      = false;
obj.HardwareRun_ = false;
obj.update_counter_;

h = obj.handles;
if isfield(h, 'RunBtn') && isvalid(h.RunBtn)
    h.RunBtn.Text = 'Run';
end
if isfield(h, 'PauseBtn') && isvalid(h.PauseBtn)
    h.PauseBtn.Enable = 'off';
    h.PauseBtn.Text   = 'Pause';
end

% Say how the session ended; a Stop press or an error reports over this.
presented = obj.presented_count_();
total     = obj.total_count_();
if total > 0 && presented >= total
    obj.set_status_(sprintf('Run complete: %d presentations.', presented));
else
    obj.set_status_(sprintf('Playback stopped after %d of %d presentations.', presented, total));
end

obj.lock_bank_controls_(false);
obj.disconnect_interfaces_;
obj.update_protocol_status_;

stimgen.util.vprintf(2, 'StimPlayer timer stopped. %d presentations logged.', numel(obj.StimOrder));
end
