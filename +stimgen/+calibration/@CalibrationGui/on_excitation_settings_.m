function on_excitation_settings_(obj)
% Open (or refocus) the Excitation Settings window: the drive
% voltage every sweep plays at, and the per-edge rise/fall time
% every tone burst is gated with. Modal, like the other two
% settings windows (see stimgen.calibration.SettingsDialog), and
% pushes to the engine the moment either field changes -- the
% window is gone by the time a sweep can be started.
obj.ExcitationDialog_.open(obj.Figure);
end
