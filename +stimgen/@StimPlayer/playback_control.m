function playback_control(obj, src, ~)
% playback_control(obj, src) - Handle Run/Pause/Stop button presses.
% playback_control(obj, action) - Drive playback programmatically.
%
% Parameters:
%   src - uibutton that was pressed (Text is 'Run', 'Stop', 'Pause' or
%         'Resume'), or an action string: "Run", "Stop", "Pause" or
%         "Resume".  The string form lets an interfacing application run the
%         session when the Run/Pause buttons are hidden — see
%         set_control_visibility.

h = obj.handles;

if nargin < 2 || isempty(src)
    src = h.RunBtn;
end

if ischar(src) || isstring(src)
    action = lower(string(src));
    switch action
        case {"run", "stop"}
            src = h.RunBtn;
        case {"pause", "resume"}
            src = h.PauseBtn;
        otherwise
            error('stimgen:StimPlayer:InvalidPlaybackAction', ...
                'Playback action must be "Run", "Stop", "Pause" or "Resume".');
    end
else
    action = lower(string(src.Text));
end

switch action

    case 'run'
        try
            if isempty(obj.StimPlayObjs)
                obj.show_gui_message_("Add at least one stimulus to the bank before running.", ...
                    "No Stimuli", "warning");
                return
            end

            % A Play All cycle steps the same variant cursors the timer
            % will; end it before the run takes them over.
            if obj.PlayAllActive_
                obj.play_all();
            end

            % Prepare runtime and hardware from the currently loaded protocol.
            obj.initialize_runtime_from_protocol_;

            % Resolve hardware parameters from Runtime
            obj.resolve_params_;

            if ~obj.HardwareAvailable
                stimgen.util.vprintf(1, 'StimPlayer: hardware parameters not found — timer will run without hardware output.');
            end

            % The converter rate belongs to the hardware, so let the host
            % override the bank rate whenever it can report one.
            obj.adopt_host_fs_;

            % Prime each bank item to combination #1 so playback stepping is deterministic
            obj.initialize_variants_;

            % Kill this player's stale timer. Not timerfindall: the tag is
            % shared, and that would stop another StimPlayer's run.
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
                delete(obj.Timer);
            end

            t = timer( ...
                'Tag',           'StimPlayerTimer', ...
                'Period',        0.005, ...
                'ExecutionMode', 'fixedRate', ...
                'BusyMode',      'drop', ...
                'StartFcn',      @obj.timer_startfcn, ...
                'TimerFcn',      @obj.timer_runtimefcn, ...
                'StopFcn',       @obj.timer_stopfcn);

            obj.Timer = t;

            h.RunBtn.Text   = 'Stop';
            h.PauseBtn.Enable = 'on';
            obj.lock_bank_controls_(true);
            obj.refresh_combo_controls_;

            start(t);
            obj.set_status_("Playback started.");
            obj.update_protocol_status_;
        catch ME
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
                delete(obj.Timer);
            end
            obj.disconnect_interfaces_;
            obj.lock_bank_controls_(false);
            h.RunBtn.Text = 'Run';
            h.PauseBtn.Enable = 'off';
            h.PauseBtn.Text = 'Pause';
            obj.report_gui_error_(ME, "Playback Error", ...
                "StimPlayer could not start playback.");
            obj.update_protocol_status_;
        end

    case 'stop'
        try
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
                delete(obj.Timer);
            end
            h.RunBtn.Text     = 'Run';
            h.PauseBtn.Enable = 'off';
            h.PauseBtn.Text   = 'Pause';
            obj.set_status_("Playback stopped.");
            obj.disconnect_interfaces_;
            obj.lock_bank_controls_(false);
            obj.update_protocol_status_;
        catch ME
            obj.report_gui_error_(ME, "Stop Error", ...
                "StimPlayer could not stop playback cleanly.");
        end

    case {'pause', 'resume'}
        % A pause holds the session; it does not stop it. The timer keeps
        % running and timer_runtimefcn presents nothing while Paused_ is
        % set, so the rep counts, presentation log, variant cursors, the
        % buffer already loaded for the next trial and the hardware
        % connection all survive. Stopping the timer instead would run
        % timer_stopfcn (unlock the bank, release the hardware) and a
        % restart would run timer_startfcn (reset every count).
        try
            if isempty(obj.Timer) || ~isvalid(obj.Timer) || ~strcmp(obj.Timer.Running, 'on')
                return  % no session to hold or release
            end
            if action == "pause" && ~obj.Paused_
                obj.Paused_ = true;
                obj.PauseStartedAt_ = obj.timeSinceStart;
                h.PauseBtn.Text = 'Resume';
                obj.set_status_(sprintf('Playback paused after %d of %d presentations.', ...
                    obj.presented_count_(), obj.total_count_()));
            elseif action == "resume" && obj.Paused_
                % Shift the last trigger time by the length of the pause, so
                % the interval in progress when Pause was pressed resumes
                % with the time it had left rather than counting the pause
                % against it (which would trigger at once on resume).
                % StimOrderTime keeps real elapsed time, pause included.
                pausedFor = obj.timeSinceStart - obj.PauseStartedAt_;
                obj.lastTrigTime = obj.lastTrigTime + pausedFor;
                obj.Paused_ = false;
                h.PauseBtn.Text = 'Pause';
                obj.set_status_(sprintf('Playback resumed after a %.1f s pause.', pausedFor));
            end
        catch ME
            obj.report_gui_error_(ME, "Pause Error", ...
                "StimPlayer could not change the playback pause state.");
        end

end
end
