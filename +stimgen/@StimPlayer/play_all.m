function play_all(obj, src, ~)
% play_all(obj)
% play_all(obj, src)
% Play all variant combinations for the selected bank stimulus through the
% selected preview output (PlaybackOutput): speakers, or the host's
% calibration hardware playing the calibrated waveform verbatim. While a
% cycle is running, the same button (relabeled "Stop") interrupts it: it
% kills the currently-playing sound and stops the loop before the next
% combination. Hardware playback cannot be cut off mid-waveform, so there
% Stop takes effect once the current combination finishes.
%
% The cycle plays a copy() of the bank item, pinned to each combination in
% turn with VariantReselectOnUpdate off -- the same way CombinationViewer
% and capture_stim generate -- so the bank item's active combination, its
% selection order and use counts, and its Signal are exactly as they were
% before Play All. The plot and the combo line show the copy while it plays
% and return to the bank item afterwards.
%
% Parameters:
%   src - Optional button handle used to flash active playback state

h = obj.handles;

if obj.PlayAllActive_
    % Reentrant call from clicking "Stop" while the loop below is running
    % (reached via the drawnow/pause calls in that loop). Signal the
    % running cycle to stop and cut off whatever is currently playing.
    obj.PlayAllActive_ = false;
    if ~isempty(obj.PlayAllStimObj_) && isvalid(obj.PlayAllStimObj_)
        obj.PlayAllStimObj_.stop_playback();
    end
    return
end

% Use the listbox-selected item, not the playback cursor.
sp = [];
if isfield(h, 'BankList') && isvalid(h.BankList) && ~isempty(h.BankList.Value)
    idx = h.BankList.Value;
    if idx >= 1 && idx <= numel(obj.StimPlayObjs)
        sp = obj.StimPlayObjs(idx);
    end
end
if isempty(sp)
    sp = obj.CurrentSPObj;
end

if isempty(sp)
    stimgen.util.vprintf(1, 'StimPlayer: no stimulus selected for play-all preview.');
    obj.show_gui_message_("Select a stimulus before using Play All.", ...
        "Nothing To Preview", "warning");
    return
end

stimObj = sp.CurrentStimObj;
info = stimObj.get_variant_info();
numCombos = info.NumCombinations;
if numCombos < 1
    obj.show_gui_message_("The selected stimulus has no playable combinations.", ...
        "Empty Variants", "warning");
    return
end

activeBtn = [];
if nargin >= 2 && ~isempty(src) && isvalid(src) && isprop(src, 'BackgroundColor')
    activeBtn = src;
elseif isfield(h, 'PlayAllBtn') && ~isempty(h.PlayAllBtn) && isvalid(h.PlayAllBtn)
    activeBtn = h.PlayAllBtn;
end

prevColor = [];
if ~isempty(activeBtn)
    prevColor = activeBtn.BackgroundColor;
    activeBtn.BackgroundColor = [0.2 1.0 0.2];
end

% Copied once with reselection off, so set_variant_index on it generates
% exactly the combination asked for and touches nothing on the bank item.
playObj = copy(stimObj);
playObj.VariantReselectOnUpdate = false;
label = string(sp.Name);

obj.PlayAllActive_  = true;
obj.PlayAllStimObj_ = playObj;
restoreObj = onCleanup(@() restore_play_all_ui_(obj, activeBtn, prevColor));

try
    obj.sync_control_enable_;  % Play (button, menu, toolbar) off while the cycle runs
    if isfield(h, 'PlayAllBtn') && ~isempty(h.PlayAllBtn) && isvalid(h.PlayAllBtn)
        h.PlayAllBtn.Text = 'Stop';
    end

    for comboIdx = 1:numCombos
        if ~obj.PlayAllActive_
            break
        end

        obj.set_computing_(true);
        computingCleanup = onCleanup(@() obj.set_computing_(false));
        playObj.set_variant_index(comboIdx);
        clear computingCleanup;

        show_combo_(obj, playObj, label, comboIdx, numCombos);
        drawnow;
        if ~obj.PlayAllActive_   % stopped, or a Run took over, during drawnow
            break
        end

        if isempty(playObj.Signal)
            error('StimPlayer:EmptySignal', ...
                'Stimulus combination %d did not produce a signal for preview.', comboIdx);
        end

        obj.set_status_(sprintf('Previewing combo %d of %d.', comboIdx, numCombos));
        if obj.PlaybackOutput == "Hardware"
            stimgen.util.vprintf(1, 'StimPlayer: previewing "%s" combo %d/%d via calibrated hardware...', ...
                sp.Name, comboIdx, numCombos);
            obj.play_via_hardware_(playObj);
        else
            stimgen.util.vprintf(1, 'StimPlayer: previewing "%s" combo %d/%d via speakers...', ...
                sp.Name, comboIdx, numCombos);
            playObj.play;
        end

        if ~obj.PlayAllActive_
            break
        end

        if comboIdx < numCombos
            obj.get_isi_;
            pause(obj.currentISI);
        end
    end

    if obj.PlayAllActive_
        obj.set_status_(sprintf('Finished Play All (%d combinations).', numCombos));
    else
        obj.set_status_('Play All stopped.');
    end
catch ME
    obj.report_gui_error_(ME, "Play All Error", ...
        "StimPlayer could not preview all combinations for the selected stimulus.");
end

obj.PlayAllActive_  = false;
obj.PlayAllStimObj_ = [];
clear restoreObj;
end


function show_combo_(obj, playObj, label, comboIdx, numCombos)
% The copy on the plot, and which combination of how many it is.
if numCombos > 1
    label = label + sprintf(' [combo %d/%d]', comboIdx, numCombos);
end
obj.update_signal_plot(playObj, label);
h = obj.handles;
if isfield(h, 'ComboStatusLbl') && ~isempty(h.ComboStatusLbl) && isvalid(h.ComboStatusLbl)
    h.ComboStatusLbl.Text = sprintf('Play All: combo %d / %d', comboIdx, numCombos);
end
end


function restore_play_all_ui_(obj, activeBtn, prevColor)
h = obj.handles;
% Back to the bank item, which Play All left as it was.
obj.refresh_combo_controls_;
obj.update_signal_plot;
% Play comes back through the shared rule, which leaves it off when a run
% started while this cycle was ending holds the lock, or nothing is selected.
obj.sync_control_enable_;
if isfield(h, 'PlayAllBtn') && ~isempty(h.PlayAllBtn) && isvalid(h.PlayAllBtn)
    h.PlayAllBtn.Text = 'Play All';
end
if ~isempty(activeBtn) && isvalid(activeBtn) && ~isempty(prevColor)
    activeBtn.BackgroundColor = prevColor;
end
end
