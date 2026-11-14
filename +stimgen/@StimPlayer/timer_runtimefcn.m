function timer_runtimefcn(obj, src, ~)
% timer_runtimefcn(obj, src) - Main playback loop; called every timer period.
% Waits until the ISI has elapsed, triggers the current buffer, advances
% the bank selection, and pre-loads the next buffer. Does nothing while the
% session is paused.

try
    if obj.nextSPOIdx < 1
        return  % all reps done; waiting for timer_stopfcn to fire
    end

    % Held by Pause: the timer keeps ticking so nothing is torn down, but
    % nothing is presented. Resume shifts lastTrigTime by the pause length
    % (see playback_control), so the ISI check below picks up where it was.
    if obj.Paused_
        return
    end

    isi = obj.currentISI;
    ts  = obj.timeSinceStart;
    % When this presentation is due: one ISI after the last trigger.
    scheduled = obj.lastTrigTime + isi;

    % Early return if ISI hasn't nearly elapsed (avoid busy-wait overhead)
    if ts - obj.lastTrigTime - isi < src.Period - 0.01
        return
    end

    % Spin until ISI has exactly elapsed
    while obj.timeSinceStart - obj.lastTrigTime < isi, end

    % A run that started with hardware stops if it has lost it (a parameter
    % gone, the connection dropped) rather than trigger nothing and log the
    % trial as presented. Checked before logging, so the log holds only
    % presentations that were triggered.
    obj.require_run_hardware_;

    % The stimulus whose buffer is loaded, and the combination it was
    % generated from. Read before increment, which can move a multi-object
    % bank item's cursor on to another object.
    presentedSP  = obj.CurrentSPObj;
    presentedObj = presentedSP.CurrentStimObj;
    presentedVar = presentedObj.get_variant_info();

    % Log presentation
    obj.StimOrder(end+1, 1)     = obj.nextSPOIdx;
    obj.StimOrderTime(end+1, 1) = obj.timeSinceStart;
    obj.StimPolarity(end+1, 1)  = obj.nextPolarity_;
    obj.StimVariant(end+1, 1)   = presentedVar.ActiveIndex;
    % How late this trigger is. Zero to within the timer's resolution unless
    % the callback was busy when it fell due -- generating the next stimulus
    % after the previous trial took longer than the ISI left for it.
    obj.StimLateness(end+1, 1)  = obj.StimOrderTime(end) - scheduled;
    obj.StimRecord{end+1, 1}    = [];   % filled below, after the trigger

    % Trigger hardware (no-op if hardware unavailable)
    obj.trigger_stim_playback;

    % What was just triggered, described while the stimulus object still
    % holds the waveform that was in the buffer -- advance_variant_ below
    % replaces it. After the trigger, so it costs the presentation nothing;
    % in its own try, so a record that cannot be made is a log line and an
    % empty cell, not a stopped session.
    try
        obj.StimRecord{end, 1} = presentedObj.generation_record();
    catch recordError
        stimgen.util.vprintf(0, 1, 'StimPlayer: no generation record for presentation %d: %s', ...
            numel(obj.StimOrder), recordError.message);
    end

    % Count the presentation, then let the presented stimulus select its
    % next combination through its own VariantSelectionMode.
    presentedSP.increment;
    obj.advance_variant_(presentedObj);

    obj.trialCount_ = obj.trialCount_ + 1;

    % What was just presented, for the operator: bank item, the combination
    % it was generated from, and the trial count.
    obj.set_status_(sprintf('Presenting %s [combo %d/%d] (%d/%d)', ...
        char(presentedSP.Name), presentedVar.ActiveIndex, presentedVar.NumCombinations, ...
        obj.trialCount_, obj.total_count_()));

    % Select next
    obj.nextSPOIdx = obj.select_next_idx;

    obj.update_counter_;
    obj.refresh_combo_controls_;

    if obj.nextSPOIdx < 1
        % All reps done; let timer_stopfcn handle cleanup
        stop(obj.Timer);
        return
    end

    % Pre-load next buffer (into the non-triggered buffer slot)
    obj.nextPolarity_ = obj.claim_polarity_;
    obj.update_buffer;
catch ME
    if ~isempty(obj.Timer) && isvalid(obj.Timer)
        stop(obj.Timer);
    end
    obj.report_gui_error_(ME, "Playback Runtime Error", ...
        "StimPlayer encountered an error during playback and has stopped.");
end
end
