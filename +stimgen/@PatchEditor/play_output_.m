function play_output_(obj)
% play_output_(obj)
% Play the finished stimulus output through the computer speakers. Flashes
% the Play button green during playback, matching StimPlayer.play_preview.

if obj.closing || isempty(obj.fig) || ~isvalid(obj.fig)
    return
end

btn = obj.h.PlayBtn;
prevColor = btn.BackgroundColor;
cleanupObj = onCleanup(@() local_restore_button_color(btn, prevColor));

try
    if isempty(obj.Patch.Signal)
        obj.Patch.update_signal();
    end

    btn.BackgroundColor = [0.2 1.0 0.2];
    drawnow;

    obj.set_status_("Playing stimulus output...", "info");
    obj.Patch.play();
    obj.set_status_("Playback finished.", "info");
catch ME
    obj.set_status_(ME.message, "error");
end

clear cleanupObj;
end


function local_restore_button_color(btn, colorValue)
if ~isempty(btn) && isvalid(btn)
    btn.BackgroundColor = colorValue;
end
end
