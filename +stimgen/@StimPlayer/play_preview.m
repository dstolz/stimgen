function play_preview(obj, src, ~)
% play_preview(obj) - Play the currently selected stimulus through the
% selected preview output (PlaybackOutput): computer speakers, normalized
% to unit peak, or the host's calibration hardware, which plays the
% generated waveform verbatim so a loaded calibration is heard at its
% calibrated level. Flashes the Play button green during playback.

h = obj.handles;

% Use the listbox-selected item, not the playback cursor
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
    stimgen.util.vprintf(1, 'StimPlayer: no stimulus selected for preview.');
    obj.show_gui_message_("Select a stimulus before previewing it.", ...
        "Nothing To Preview", "warning");
    return
end

stimObj = sp.CurrentStimObj;
btn = [];
if nargin >= 2 && ~isempty(src) && isvalid(src) && isprop(src, 'BackgroundColor')
    btn = src;
elseif isfield(obj.handles, 'PlayBtn') && ~isempty(obj.handles.PlayBtn) && isvalid(obj.handles.PlayBtn)
    btn = obj.handles.PlayBtn;
end

if ~isempty(btn)
    prevColor = btn.BackgroundColor;
    cleanupObj = onCleanup(@() restore_button_color_(btn, prevColor));
else
    cleanupObj = onCleanup(@() []);
end

try
    if isempty(stimObj.Signal)
        obj.set_computing_(true);
        computingCleanup = onCleanup(@() obj.set_computing_(false));
        stimObj.update_signal;
        clear computingCleanup;
    end

    if ~isempty(btn)
        btn.BackgroundColor = [0.2 1.0 0.2];
    end
    drawnow;

    if obj.PlaybackOutput == "Hardware"
        stimgen.util.vprintf(1, 'StimPlayer: playing "%s" via calibrated hardware...', sp.Name);
        obj.set_status_("Previewing via hardware: " + string(sp.Name));
        obj.play_via_hardware_(stimObj);
    else
        stimgen.util.vprintf(1, 'StimPlayer: playing "%s" via speakers...', sp.Name);
        statusText = "Previewing via speakers: " + string(sp.Name);
        if obj.stim_has_calibration_(stimObj)
            statusText = statusText + " (normalized; calibrated levels not reproduced)";
        end
        obj.set_status_(statusText);
        stimObj.play;
    end
catch ME
    obj.report_gui_error_(ME, "Preview Error", ...
        "StimPlayer could not preview the selected stimulus.");
end

clear cleanupObj;
end


function restore_button_color_(btn, colorValue)
if ~isempty(btn) && isvalid(btn)
    btn.BackgroundColor = colorValue;
end
end
