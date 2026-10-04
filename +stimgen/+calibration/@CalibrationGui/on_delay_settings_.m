function on_delay_settings_(obj)
% Open (or refocus) the Conduction Delay Settings window: what the
% probe searches with, and the air temperature its delay is turned
% into a distance through. These were an inputdlg the Measure
% Conduction Delay button raised every time; they are asked once
% here instead, so the button measures when it is pressed. The
% probe is also the one measurement worth repeating back to back --
% move the microphone, measure again -- which a prompt in front of
% it made three actions instead of one.
obj.DelayDialog_.open(obj.Figure);
end
