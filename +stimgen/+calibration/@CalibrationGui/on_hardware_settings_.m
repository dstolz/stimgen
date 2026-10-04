function on_hardware_settings_(obj)
% Open (or refocus) the Hardware and Analysis Settings window: the
% facts the adapter reports, the settings that describe the signal
% path it acquires through, and how the acquired record is
% transformed to a spectrum. Modal, like the other two settings
% windows -- see stimgen.calibration.SettingsDialog. The
% conduction delay is not here: it is measured per acquisition
% rather than set once per rig, so it lives in the column footer
% where it stays visible while a sweep runs.
obj.HardwareDialog_.open(obj.Figure);
end
