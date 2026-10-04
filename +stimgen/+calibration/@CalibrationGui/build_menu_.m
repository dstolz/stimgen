function build_menu_(obj)
% Create File menu with Load and Save options.
fileMenu = uimenu(obj.Figure, Text='File');
uimenu(fileMenu, Text='Initialize Runtime From Protocol...', ...
    MenuSelectedFcn=@(~,~) obj.on_initialize_runtime_());
obj.RecentProtocolsMenu = uimenu(fileMenu, Text='Recent Protocols');
obj.refresh_recent_protocols_menu_();
uimenu(fileMenu, Text='Attach Adapter', ...
    MenuSelectedFcn=@(~,~) obj.on_attach_adapter_());
uimenu(fileMenu, Text='Disconnect Runtime/Adapter', ...
    MenuSelectedFcn=@(~,~) obj.on_disconnect_runtime_());
uimenu(fileMenu, Text='Load .esgc', ...
    Separator='on', ...
    MenuSelectedFcn=@(~,~) obj.on_load_());
uimenu(fileMenu, Text='Save .esgc', ...
    MenuSelectedFcn=@(~,~) obj.on_save_());
obj.RecentCalibrationsMenu = uimenu(fileMenu, Text='Recent Calibrations');
obj.refresh_recent_calibrations_menu_();

% The calibration in words, on the command window: what it was
% measured through, what each table covers, how each verification
% came out, and the operator's notes. Text rather than a dialog
% because it is meant to be copied -- into a notebook entry, a
% message, a commit -- and because it is as useful typed at the
% prompt (Engine.describe) as chosen from here.
uimenu(fileMenu, Text='Print Calibration Summary', Separator='on', ...
    Tooltip=stimgen.util.tooltip('CalibrationGui', 'PrintSummary'), ...
    MenuSelectedFcn=@(~,~) obj.on_print_summary_());

% The window itself as a record: a calibration ends up in a lab
% notebook or an e-mail, and the whole window -- settings and
% plots together -- is the state worth reporting. exportapp is
% the one capture that includes the UI components; copygraphics
% and print skip them.
uimenu(fileMenu, Text='Save Screenshot...', ...
    MenuSelectedFcn=@(~,~) obj.on_save_screenshot_());
uimenu(fileMenu, Text='Copy Window to Clipboard', ...
    MenuSelectedFcn=@(~,~) obj.on_copy_window_());

% Everything on this menu changes how the panels draw; which
% measurement is being looked at is chosen on the plots panel's
% tab strip. The three checkable items that used to select a view
% were removed with the shared panel: a tab both selects and
% reports, in the place the plot is read, and a menu duplicating
% it would be one more thing that can disagree with the screen.
viewMenu = uimenu(obj.Figure, Text='View');

% Weightings annotate whichever view is up rather than being a
% view of their own, and more than one at a time is a reasonable
% thing to want -- hence checkable items instead of a dropdown,
% which also keeps them off the already-crowded controls panel.
weightMenu = uimenu(viewMenu, Text='Weighting Overlay');
types = stimgen.calibration.LiveMonitor.WeightingTypes;
obj.WeightingMenus = gobjects(1, numel(types));
for k = 1:numel(types)
    obj.WeightingMenus(k) = uimenu(weightMenu, ...
        Text=sprintf('%s-weighting', types(k)), ...
        MenuSelectedFcn=@(src,~) obj.on_weighting_(src));
end
uimenu(weightMenu, Text='None', Separator='on', ...
    MenuSelectedFcn=@(~,~) obj.on_weighting_none_());

% The spectrum answers a different question in each unit -- is the
% level right, is the input stage clipping, how does this floor
% compare to the last one, what is the shape -- and only one at a
% time, so these are exclusive checkmarks. The unit is carried in
% UserData rather than parsed back out of the menu text.
unitMenu = uimenu(viewMenu, Text='Spectrum Y-Axis', Separator='on');
units = stimgen.calibration.LiveMonitor.SpectrumUnitList;
obj.SpectrumUnitMenus = gobjects(1, numel(units));
for k = 1:numel(units)
    obj.SpectrumUnitMenus(k) = uimenu(unitMenu, ...
        Text=spectrum_unit_menu_text_(units(k)), ...
        UserData=units(k), ...
        Tooltip=stimgen.util.tooltip('CalibrationGui', 'SpectrumUnits'), ...
        MenuSelectedFcn=@(src,~) obj.on_spectrum_units_(src));
end

% Two overlays worth turning off once a panel is crowded, and the
% non-toolbar home for the pair of toolbar buttons that share them.
% Both default on: the ghost is what makes run-to-run drift visible
% rather than inferred, and the drive axis is what says whether a
% point is reachable at all.
obj.GhostMenu = uimenu(viewMenu, Text='Previous-Measurement Ghost', ...
    Separator='on', ...
    Tooltip=stimgen.util.tooltip('CalibrationGui', 'SpectrumGhost'), ...
    MenuSelectedFcn=@(~,~) obj.set_show_ghost_(~obj.Monitor.ShowGhost));
obj.VoltageMenu = uimenu(viewMenu, Text='Transfer Drive-Voltage Axis', ...
    Tooltip=stimgen.util.tooltip('CalibrationGui', 'TransferVoltage'), ...
    MenuSelectedFcn=@(~,~) obj.set_show_voltage_(~obj.Monitor.ShowVoltage));

% How much of a time-domain record is handed to the renderer.
% Off by default -- the envelope is what keeps a redraw cheap on
% a record of hundreds of thousands of samples -- and worth
% turning on when zoomed in far enough that a block of it spans
% several pixels. Phrased as what checking it gets you rather
% than as the mechanism it turns off.
obj.WaveformResMenu = uimenu(viewMenu, Text='Full-Resolution Waveforms', ...
    Tooltip=stimgen.util.tooltip('CalibrationGui', 'FullResolutionWaveforms'), ...
    MenuSelectedFcn=@(~,~) obj.set_full_resolution_(obj.Monitor.DecimateWaveforms));

% Rig facts, acquisition and analysis settings live in their own
% window rather than the controls column: they are set once per
% rig, not once per sweep, and the column reads better carrying
% only the per-sweep workflow.
optMenu = uimenu(obj.Figure, Text='Options');
uimenu(optMenu, Text='Hardware and Analysis Settings...', ...
    MenuSelectedFcn=@(~,~) obj.on_hardware_settings_());
% The delay probe's own settings, on a second window rather than
% on the one above: they are asked of a measurement rather than of
% the rig, and the button that runs it now runs it immediately
% instead of stopping to ask.
uimenu(optMenu, Text='Conduction Delay Settings...', ...
    MenuSelectedFcn=@(~,~) obj.on_delay_settings_());
% The drive voltage and the tone burst's rise/fall shape: settings
% every sweep runs at, but not steps of their own, so they earn a
% window over a place in the per-sweep controls column.
uimenu(optMenu, Text='Excitation Settings...', ...
    MenuSelectedFcn=@(~,~) obj.on_excitation_settings_());

helpMenu = uimenu(obj.Figure, Text='Help');
uimenu(helpMenu, Text='Calibration Quick Start (Wiki)', ...
    MenuSelectedFcn=@(~,~) obj.on_show_quick_start_());
uimenu(helpMenu, Text='Guide to This Window (Wiki)', ...
    MenuSelectedFcn=@(~,~) obj.on_show_gui_guide_());
end
