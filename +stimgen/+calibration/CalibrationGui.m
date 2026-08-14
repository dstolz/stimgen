classdef CalibrationGui < handle
    % gui = stimgen.calibration.CalibrationGui()
    % gui = stimgen.calibration.CalibrationGui(host)
    % gui = stimgen.calibration.CalibrationGui(eng)
    % Interactive GUI for the stimgen.calibration package.
    %
    % Provides user parameterization of calibration settings, live inspection of
    % the latest response waveform/spectrum, transfer-curve visualization for
    % tone and click calibration tables, and save/load support for .esgc files.
    % The Calibration section's Iterative Level Refinement toggle follows each
    % tone or click sweep with Engine.refine_tones/refine_clicks: the finished
    % table is tested at its own points and corrected from the measured errors
    % until every point lands within a target accuracy.
    % When no engine is supplied, an offline Engine is created automatically;
    % hardware can be attached later via File > Initialize Runtime From Protocol.
    %
    % Hardware and Analysis Settings (Hardware menu) holds what is set once
    % per rig rather than once per sweep: the output ceiling, AC coupling of
    % the acquired record, and the analysis window and FFT length every
    % spectral measurement is made with. The last two also govern the spectrum
    % panel, so the peak on screen is computed the same way as the number
    % written into the lookup table.
    %
    % Settings are remembered across MATLAB sessions as StimCalibrationGui
    % preferences: the controls-column fields and toggles, the settings
    % window's fields, the display state (spectrum unit, weighting overlays,
    % ghost, drive-voltage axis, log frequency axis), and the per-dialog
    % measurement parameters. Values carried by a supplied engine, or by a
    % loaded or in-progress calibration, always take precedence over
    % remembered ones.
    %
    % All drawing is done by a stimgen.calibration.LiveMonitor attached to this
    % window's axes: during a run it renders the engine's LiveUpdate stream
    % (gated by the Show Engine Live Plots checkbox), and between runs the same
    % renderer draws the committed calibration and the last response.
    %
    % What those panels show is chosen from the toolbar's second group -- which
    % of the two views the transfer panel serves, and one button per overlay --
    % mirrored by the View menu and the Display section, since a display choice
    % is made while reading a plot rather than while setting a sweep up. The
    % state itself lives on the monitor and on TransferView_; every control is
    % a mirror of it, written only by sync_display_controls_.
    %
    % Arguments are identified by type, so an Engine and a HardwareHost may be
    % passed in either order, either one alone, or as Engine=/Host= pairs.
    %
    % Parameters:
    %   eng  - (optional) stimgen.calibration.Engine with an adapter already
    %          attached. Omit to start with a fresh offline engine.
    %   host - (optional) stimgen.HardwareHost. Required only for the runtime
    %          menu actions; omit when supplying an engine that already has an
    %          adapter, or when working offline.
    %
    % Returns:
    %   gui - GUI controller handle.
    %
    % Example:
    %   % Offline mode — load a saved calibration, no hardware:
    %   gui = stimgen.calibration.CalibrationGui();
    %
    %   % Host-driven: attach hardware from the GUI menu.
    %   gui = stimgen.calibration.CalibrationGui(host);
    %
    %   % Pre-built engine with adapter:
    %   eng = stimgen.calibration.Engine(adapter);
    %   gui = stimgen.calibration.CalibrationGui(eng);
    %
    %   % Both, in either order or by name:
    %   gui = stimgen.calibration.CalibrationGui(eng, host);
    %   gui = stimgen.calibration.CalibrationGui(Host=host);
    %
    % See also: stimgen.calibration.Engine, stimgen.calibration.HwAdapter,
    %           stimgen.HardwareHost,
    %           documentation/stimgen_CalibrationGui.md,
    %           documentation/stimgen_calibration.md

    properties (Constant)
        % Help > Calibration Quick Start opens this page.
        QuickStartURL = 'https://github.com/dstolz/stimgen/wiki/Calibrating-Your-Rig'
    end

    properties (SetAccess = private)
        Engine stimgen.calibration.Engine
        Monitor stimgen.calibration.LiveMonitor  % renders all three axes
    end

    properties (Access = private)
        Figure
        Grid
        Host                    % stimgen.HardwareHost | []

        % File menu
        RecentProtocolsMenu
        RecentCalibrationsMenu

        % View menu
        CalibrationViewMenu
        BackgroundViewMenu
        WeightingMenus          % one checkable item per LiveMonitor.WeightingTypes
        SpectrumUnitMenus       % one checkable item per LiveMonitor.SpectrumUnitList
        GhostMenu
        VoltageMenu
        TransferView_ (1,1) string = "calibration"  % which view the transfer panel last drew

        % Display toolbar. Each of these mirrors a View menu item or the
        % Display section's checkbox rather than owning state of its own:
        % what a plot shows is changed while reading the plot, which is when
        % crossing the window to a menu is most in the way. sync_display_-
        % controls_ is the one writer that keeps every mirror in step.
        ToolCalibrationView
        ToolBackgroundView
        ToolGhost
        ToolVoltage
        ToolLogX

        % Controls
        RefLevelField
        RefFreqField
        MicSensField
        NormativeField
        ExcitationField
        ShowLivePlotsCheck
        TransferLogXCheck
        ToneSweptSineCheck
        IterativeCheck
        StatusLabel
        LevelRefLabel
        ConductionDelayLabel

        % Hardware & Analysis Settings window (Hardware menu). Created on
        % demand, so these handles are empty until it is first opened and
        % dead once it is closed -- everything that writes them guards on
        % validity. The settings themselves live on the Engine; the window is
        % only a view of them.
        HardwareDialog_
        MaxOutputField
        AcCoupleCheck
        SpectralWindowDrop
        SpectralFftDrop
        SampleRateLabel

        % Listener on the engine's ConductionDelay property, so the readout
        % updates the moment a click probe lands rather than waiting for the
        % run to finish. Rebound whenever the engine is swapped (run_load_).
        DelayListener_

        % Buttons
        BtnReference
        BtnBackground
        BtnTones
        BtnClicks
        BtnSweptSine
        BtnTestTones
        BtnTestClicks
        BtnFilter
        BtnTestFilter
        BtnCopyFilter
        BtnStop
        BtnReset

        % Axes
        AxTime
        AxSpectrum
        AxTransfer
    end

    methods
        function obj = CalibrationGui(varargin)
            % obj = stimgen.calibration.CalibrationGui()
            % obj = stimgen.calibration.CalibrationGui(host)
            % obj = stimgen.calibration.CalibrationGui(eng)
            % obj = stimgen.calibration.CalibrationGui(eng, host)
            % obj = stimgen.calibration.CalibrationGui(Engine=eng, Host=host)
            % Construct and display the calibration GUI.
            %
            % Arguments are matched by type rather than position, so either may
            % be omitted or given in either order.
            %
            % Parameters:
            %   eng  - (optional) stimgen.calibration.Engine; omit for a fresh
            %          offline engine.
            %   host - (optional) stimgen.HardwareHost enabling the runtime menu
            %          actions (Initialize Runtime From Protocol, Attach Adapter).
            [eng, host] = parse_construction_args_(varargin);

            obj.Engine = eng;
            obj.Host   = host;

            obj.build_ui_();
            obj.restore_settings_prefs_();
            obj.bind_engine_listeners_();
            obj.sync_controls_();
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.show_startup_hint_();
        end

        function show(obj)
            % show(obj)
            % Bring the GUI window to the foreground.
            if isvalid(obj.Figure)
                figure(obj.Figure);
            end
        end

        function delete(obj)
            % Release the monitor's registration on the engine. The engine may
            % outlive this window -- it might be saved, or shared with a
            % StimType -- and must not keep notifying a renderer whose axes
            % died with the figure.
            if ~isempty(obj.Monitor) && isvalid(obj.Monitor)
                delete(obj.Monitor);
            end
            % Same reason: the engine must not keep calling back into a
            % label that died with the figure.
            delete(obj.DelayListener_);
            % The settings window is owned by this object, not by
            % the main figure, so it does not die with either on its own.
            if ~isempty(obj.HardwareDialog_) && isvalid(obj.HardwareDialog_)
                delete(obj.HardwareDialog_);
            end
        end

        function set_adapter(obj, adapter)
            % set_adapter(obj, adapter)
            % Attach/replace the hardware adapter used for live calibration.
            arguments
                obj
                adapter (1,1) stimgen.calibration.HwAdapter
            end
            obj.Engine.set_adapter(adapter);
            obj.update_runtime_state_();
            obj.set_status_('Adapter attached. Ready for live calibration.', false);
        end
    end

    methods (Access = private)
        function build_ui_(obj)
            obj.Figure = uifigure( ...
                Name='Stim Calibration', ...
                Position=[120 60 1360 820], ...
                CloseRequestFcn=@(src,~) obj.on_close_(src));

            obj.Grid = uigridlayout(obj.Figure, [1 2]);
            obj.Grid.ColumnWidth = {380, '1x'};
            obj.Grid.RowHeight = {'1x'};

            obj.build_menu_();
            obj.build_toolbar_();
            obj.build_controls_panel_();
            obj.build_plots_panel_();

            % Last, because it writes to all three of them and the monitor
            % holding the state it writes is created by the last call above.
            obj.sync_display_controls_();
        end

        function build_toolbar_(obj)
            % Quick-access toolbar mirroring the most common File menu actions.
            tb = uitoolbar(obj.Figure);

            tip = @(key) stimgen.util.tooltip('CalibrationGui', key);

            uipushtool(tb, Tooltip=tip('InitializeRuntimeTool'), ...
                Icon=stimgen.util.toolbar_icon('protocol'), ...
                ClickedCallback=@(~,~) obj.on_initialize_runtime_());

            uipushtool(tb, Tooltip=tip('AttachAdapterTool'), ...
                Icon=stimgen.util.toolbar_icon('connect'), ...
                ClickedCallback=@(~,~) obj.on_attach_adapter_());

            uipushtool(tb, Tooltip=tip('DisconnectTool'), ...
                Icon=stimgen.util.toolbar_icon('disconnect'), ...
                ClickedCallback=@(~,~) obj.on_disconnect_runtime_());

            uipushtool(tb, Tooltip=tip('LoadTool'), Separator='on', ...
                Icon=stimgen.util.toolbar_icon('open'), ...
                ClickedCallback=@(~,~) obj.on_load_());

            uipushtool(tb, Tooltip=tip('SaveTool'), ...
                Icon=stimgen.util.toolbar_icon('save'), ...
                ClickedCallback=@(~,~) obj.on_save_());

            uipushtool(tb, Tooltip=tip('QuickStartTool'), Separator='on', ...
                Icon=stimgen.util.toolbar_icon('help'), ...
                ClickedCallback=@(~,~) obj.on_show_quick_start_());

            obj.build_display_tools_(tb, tip);
        end

        function build_display_tools_(obj, tb, tip)
            % Second toolbar group: what the panels show. The first pair
            % chooses which view the transfer panel serves and is exclusive;
            % the second group toggles one overlay each. All five are toggle
            % tools rather than push tools so the toolbar states what is on
            % screen as well as changing it -- which is what makes it usable
            % as the display readout it now is.
            obj.ToolCalibrationView = uitoggletool(tb, Separator='on', ...
                Tooltip=tip('TransferViewTool'), ...
                Icon=stimgen.util.toolbar_icon('transfer'), ...
                ClickedCallback=@(~,~) obj.set_transfer_view_("calibration"));

            obj.ToolBackgroundView = uitoggletool(tb, Enable='off', ...
                Tooltip=tip('BackgroundViewTool'), ...
                Icon=stimgen.util.toolbar_icon('background'), ...
                ClickedCallback=@(~,~) obj.set_transfer_view_("background"));

            obj.ToolGhost = uitoggletool(tb, Separator='on', ...
                Tooltip=tip('SpectrumGhost'), ...
                Icon=stimgen.util.toolbar_icon('ghost'), ...
                ClickedCallback=@(src,~) obj.set_show_ghost_(logical(src.State)));

            obj.ToolVoltage = uitoggletool(tb, Tooltip=tip('TransferVoltage'), ...
                Icon=stimgen.util.toolbar_icon('voltage'), ...
                ClickedCallback=@(src,~) obj.set_show_voltage_(logical(src.State)));

            obj.ToolLogX = uitoggletool(tb, Tooltip=tip('TransferLogX'), ...
                Icon=stimgen.util.toolbar_icon('logx'), ...
                ClickedCallback=@(src,~) obj.set_transfer_log_x_(logical(src.State)));
        end

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

            % The transfer panel serves one view at a time; this is how a user
            % gets back to the other one without re-running anything. Checkable
            % rather than plain items, so the menu names the view that is up
            % instead of only offering to change it.
            viewMenu = uimenu(obj.Figure, Text='View');
            obj.CalibrationViewMenu = uimenu(viewMenu, ...
                Text='Calibration Transfer Curves', ...
                MenuSelectedFcn=@(~,~) obj.set_transfer_view_("calibration"));
            obj.BackgroundViewMenu = uimenu(viewMenu, Text='Background Noise Analysis', ...
                Enable='off', ...
                MenuSelectedFcn=@(~,~) obj.set_transfer_view_("background"));

            % Weightings annotate whichever view is up rather than being a
            % view of their own, and more than one at a time is a reasonable
            % thing to want -- hence checkable items instead of a dropdown,
            % which also keeps them off the already-crowded controls panel.
            weightMenu = uimenu(viewMenu, Text='Weighting Overlay', Separator='on');
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

            % Rig facts, acquisition and analysis settings live in their own
            % window rather than the controls column: they are set once per
            % rig, not once per sweep, and the column reads better carrying
            % only the per-sweep workflow.
            hwMenu = uimenu(obj.Figure, Text='Hardware');
            uimenu(hwMenu, Text='Hardware and Analysis Settings...', ...
                MenuSelectedFcn=@(~,~) obj.on_hardware_settings_());

            helpMenu = uimenu(obj.Figure, Text='Help');
            uimenu(helpMenu, Text='Calibration Quick Start (Wiki)', ...
                MenuSelectedFcn=@(~,~) obj.on_show_quick_start_());
        end

        function build_controls_panel_(obj)
            % Left column: a scrolling stack of titled sections above a footer
            % that does not scroll. One flat list of 23 rows made the reading
            % order carry the whole workflow; the sections carry it instead, so
            % a row is found by what it is about rather than by counting down
            % from the top. Each section holds the settings a step consumes and
            % then the button that consumes them.
            %
            % Stop, the conduction delay readout and the status line are in the
            % footer because they are what is needed while a sweep is running,
            % when the stack may be scrolled anywhere.
            col = uigridlayout(obj.Grid, [2 1]);
            col.Layout.Row = 1;
            col.Layout.Column = 1;
            col.RowHeight = {'1x', 92};
            col.ColumnWidth = {'1x'};
            col.Padding = [0 0 0 0];
            col.RowSpacing = 6;

            stack = uigridlayout(col, [4 1]);
            stack.Layout.Row = 1;
            stack.Layout.Column = 1;
            stack.ColumnWidth = {'1x'};
            stack.Padding = [0 0 0 0];
            stack.RowSpacing = 6;
            stack.Scrollable = 'on';

            h = zeros(1, 4);

            [g, h(1)] = obj.add_section_(stack, 1, 'Microphone Reference', [24 24 24 30]);
            obj.build_reference_section_(g);

            [g, h(2)] = obj.add_section_(stack, 2, 'Calibration', [24 24 30 30 24 24]);
            obj.build_calibration_section_(g);

            [g, h(3)] = obj.add_section_(stack, 3, 'Verification & Equalization', [30 30 30 24]);
            obj.build_verification_section_(g);

            [g, h(4)] = obj.add_section_(stack, 4, 'Display', [24 24]);
            obj.build_display_section_(g);

            stack.RowHeight = num2cell(h);

            obj.build_footer_(col);
        end

        function [g, h] = add_section_(~, parent, row, titleText, rowHeights)
            % [g, h] = add_section_(obj, parent, row, titleText, rowHeights)
            % Titled section panel in the controls column, returning its
            % label/widget grid and the pixel height the column must reserve
            % for it. The height is computed rather than left as '1x' because
            % the column scrolls, and a scrollable grid collapses a '1x' row to
            % its minimum.
            p = uipanel(parent, Title=titleText);
            p.Layout.Row = row;
            p.Layout.Column = 1;

            g = uigridlayout(p, [numel(rowHeights) 2]);
            g.RowHeight = num2cell(rowHeights);
            % Captions get the wider share: they carry the units, the fields
            % hold three or four digits.
            g.ColumnWidth = {'1.3x', '1x'};
            g.Padding = [8 6 8 6];
            g.RowSpacing = 4;
            g.ColumnSpacing = 8;

            h = sum(rowHeights) + 4*(numel(rowHeights)-1) + 12 + 26;
        end

        function build_reference_section_(obj, g)
            % What the acoustic calibrator produces, and the sensitivity
            % measuring it yields.
            obj.RefLevelField = numeric_row_(g, 1, 'Reference Level (dB SPL)', ...
                [1, 160], '%.1f');
            obj.RefFreqField = numeric_row_(g, 2, 'Reference Frequency (Hz)', ...
                [20, 200000], '%.1f');
            obj.MicSensField = numeric_row_(g, 3, 'Mic Sensitivity (V/Pa)', ...
                [eps, 100], '%.5f');

            obj.BtnReference = action_button_(g, 4, 1, 'Measure Reference', ...
                'BtnReference', @(~,~) obj.on_measure_reference_());

            % Background sits with the reference step, the other measurement
            % that plays nothing, and after it: the noise floor is only a level
            % in dB SPL once the reference has set the scale it is read on.
            obj.BtnBackground = action_button_(g, 4, 2, 'Measure Background', ...
                'BtnBackground', @(~,~) obj.on_measure_background_());
        end

        function on_hardware_settings_(obj)
            % Open (or refocus) the Hardware and Analysis Settings window: the
            % facts the adapter reports, the settings that describe the signal
            % path it acquires through, and how the acquired record is
            % transformed to a spectrum. Non-modal, so it can stay up during a
            % run. The conduction delay is not here: it is measured per
            % acquisition rather than set once per rig, so it lives in the
            % column footer where it stays visible while a sweep runs.
            if ~isempty(obj.HardwareDialog_) && isvalid(obj.HardwareDialog_)
                figure(obj.HardwareDialog_);
                return
            end

            pos = obj.Figure.Position;
            obj.HardwareDialog_ = uifigure( ...
                Name='Hardware and Analysis Settings', ...
                Position=[pos(1)+40 pos(2)+pos(4)-300 400 208], ...
                Resize='off');

            g = uigridlayout(obj.HardwareDialog_, [7 2]);
            g.RowHeight = {24 24 24 12 20 24 24};
            % Same split as the controls column's sections: captions carry
            % the units, the fields hold a few digits.
            g.ColumnWidth = {'1.3x', '1x'};
            g.Padding = [8 8 8 8];
            g.RowSpacing = 4;
            g.ColumnSpacing = 8;

            obj.SampleRateLabel = readout_row_(g, 1, 'Sample Rate', 'No adapter', '');

            obj.MaxOutputField = numeric_row_(g, 2, 'Max Output Voltage (V)', ...
                [eps, 1000], '%.1f', stimgen.util.tooltip('CalibrationGui', 'MaxOutputVoltage'));

            % An acquisition setting, not a display one: it changes the
            % numbers that go into the table, not how they are drawn. The
            % corner frequency is fixed at Engine's 20 Hz default and is not
            % exposed here.
            obj.AcCoupleCheck = check_row_(g, 3, 'AC Couple Acquired Signal', ...
                stimgen.util.tooltip('CalibrationGui', 'AcCoupleResponse'));

            % The two below are analysis rather than acquisition: they change
            % how an already-acquired record is turned into a spectrum, and so
            % what every level read off one becomes. They share this window
            % with AC coupling because they share its consequence -- the
            % numbers in the table move -- and are separated by a heading
            % because the reason they move is a different one.
            heading_row_(g, 5, 'Spectral Analysis');

            obj.SpectralWindowDrop = dropdown_row_(g, 6, 'Analysis Window', ...
                arrayfun(@stimgen.calibration.SpectralOptions.windowLabel, ...
                    stimgen.calibration.SpectralOptions.WindowList), ...
                stimgen.calibration.SpectralOptions.WindowList, ...
                stimgen.util.tooltip('CalibrationGui', 'SpectralWindow'));

            obj.SpectralFftDrop = dropdown_row_(g, 7, 'FFT Length (samples)', ...
                arrayfun(@stimgen.calibration.SpectralOptions.fftLengthLabel, ...
                    stimgen.calibration.SpectralOptions.FftLengthList), ...
                stimgen.calibration.SpectralOptions.FftLengthList, ...
                stimgen.util.tooltip('CalibrationGui', 'SpectralFftLength'));

            % Settings push to the engine as they change: the window may be
            % closed by run time, so apply-at-next-run would silently depend
            % on whether it happened to be open then.
            obj.MaxOutputField.ValueChangedFcn = @(~,~) obj.on_hardware_setting_changed_();
            obj.AcCoupleCheck.ValueChangedFcn = @(~,~) obj.on_hardware_setting_changed_();
            obj.SpectralWindowDrop.ValueChangedFcn = @(~,~) obj.on_spectral_setting_changed_();
            obj.SpectralFftDrop.ValueChangedFcn = @(~,~) obj.on_spectral_setting_changed_();

            obj.sync_hardware_dialog_();
            obj.refresh_sample_rate_label_();
        end

        function on_hardware_setting_changed_(obj)
            try
                obj.Engine.set_configuration( ...
                    MaxOutputVoltage=obj.MaxOutputField.Value, ...
                    AcCoupleResponse=obj.AcCoupleCheck.Value);
                obj.set_status_('Hardware settings applied.', false);
            catch ME
                obj.set_status_(sprintf('Parameter update failed: %s', ME.message), true);
                % Put the rejected control back to what the engine holds.
                obj.sync_hardware_dialog_();
            end
        end

        function on_spectral_setting_changed_(obj)
            % Separate from on_hardware_setting_changed_ only because of what
            % follows it: the last acquired record is re-analysed and redrawn,
            % so the choice is answered on screen rather than at the next
            % sweep. Nothing already in a lookup table is recomputed -- those
            % numbers are what their own measurement found.
            try
                obj.Engine.set_configuration( ...
                    SpectralWindow=obj.SpectralWindowDrop.Value, ...
                    SpectralFftLength=obj.SpectralFftDrop.Value);
            catch ME
                obj.set_status_(sprintf('Parameter update failed: %s', ME.message), true);
                obj.sync_hardware_dialog_();
                return
            end

            obj.Monitor.show_engine_state(obj.Engine);
            obj.set_status_(sprintf( ...
                'Spectral analysis: %s window, %s. Applies to the next measurement.', ...
                stimgen.calibration.SpectralOptions.windowLabel(obj.Engine.SpectralWindow), ...
                stimgen.calibration.SpectralOptions.fftLengthLabel(obj.Engine.SpectralFftLength)), ...
                false);
        end

        function sync_hardware_dialog_(obj)
            % The engine owns these settings; the window, when open, is only
            % a view of them. Called wherever the engine may have changed
            % under the window -- construction, load, engine swap.
            if isempty(obj.HardwareDialog_) || ~isvalid(obj.HardwareDialog_)
                return
            end
            obj.MaxOutputField.Value = obj.Engine.MaxOutputVoltage;
            obj.AcCoupleCheck.Value = obj.Engine.AcCoupleResponse;
            obj.SpectralWindowDrop.Value = obj.Engine.SpectralWindow;
            % A loaded calibration may name a length this list does not offer,
            % having been saved from a hand-configured engine. Show it rather
            % than silently snapping the engine to a neighbouring value.
            set_dropdown_value_(obj.SpectralFftDrop, obj.Engine.SpectralFftLength, ...
                @stimgen.calibration.SpectralOptions.fftLengthLabel);
        end

        function build_calibration_section_(obj, g)
            % The sweeps and the two settings every sweep is run at: the drive
            % voltage it plays at, and the level its table is anchored to.
            obj.ExcitationField = numeric_row_(g, 1, 'Excitation Voltage (V)', ...
                [eps, 10], '%.3f');
            obj.NormativeField = numeric_row_(g, 2, 'Normative Value (dB SPL)', ...
                [1, 180], '%.1f');

            % Tones get the full width and the two optional sweeps share the
            % row below: the layout says which one an experiment normally needs.
            obj.BtnTones = action_button_(g, 3, [1 2], 'Calibrate Tones', ...
                'BtnTones', @(~,~) obj.on_calibrate_tones_());
            obj.BtnClicks = action_button_(g, 4, 1, 'Calibrate Clicks', ...
                'BtnClicks', @(~,~) obj.on_calibrate_clicks_());
            obj.BtnSweptSine = action_button_(g, 4, 2, 'Calibrate Swept Sine', ...
                'BtnSweptSine', @(~,~) obj.on_calibrate_swept_sine_());

            % Directly under the sweep it redirects tone lookups to.
            obj.ToneSweptSineCheck = check_row_(g, 5, 'Tone Lookup From Swept Sine', ...
                stimgen.util.tooltip('CalibrationGui', 'ToneLutFromSweptSine'), ...
                @(~,~) obj.on_tone_lut_source_());

            % Follows each tone or click sweep with Engine.refine_tones/
            % refine_clicks: the finished table is tested at its own points
            % and corrected from the errors that come back, until every point
            % lands within a target accuracy. The sweep dialog collects the
            % pass limit and target while this is checked.
            obj.IterativeCheck = check_row_(g, 6, 'Iterative Level Refinement', ...
                stimgen.util.tooltip('CalibrationGui', 'IterativeRefinement'));
        end

        function build_verification_section_(obj, g)
            % The two lookup-table tests share the top row, each under the
            % sweep it verifies in the section above. Both are ahead of the
            % equalizer: a filter designed on a table whose levels are wrong
            % inherits that error. Design and its own verification then share
            % the row below, since neither is much use without the other. The
            % export of the taps gets the full width under both, being the one
            % thing here that leaves the window.
            obj.BtnTestTones = action_button_(g, 1, 1, 'Test Tones', ...
                'BtnTestTones', @(~,~) obj.on_test_tones_());
            obj.BtnTestClicks = action_button_(g, 1, 2, 'Test Clicks', ...
                'BtnTestClicks', @(~,~) obj.on_test_clicks_());
            obj.BtnFilter = action_button_(g, 2, 1, 'Design Filter', ...
                'BtnFilter', @(~,~) obj.on_design_filter_());
            obj.BtnTestFilter = action_button_(g, 2, 2, 'Test Filter', ...
                'BtnTestFilter', @(~,~) obj.on_test_filter_());
            obj.BtnCopyFilter = action_button_(g, 3, [1 2], 'Copy Filter Coefficients', ...
                'BtnCopyFilter', @(~,~) obj.on_copy_filter_coefficients_());

            % What the equalizer does to a level once it runs in hardware,
            % where nothing renormalizes after the FIR. Shown for the 1 V RMS
            % white-noise convention; Engine.filter_level_reference takes the
            % actual source waveform when that assumption does not hold.
            obj.LevelRefLabel = readout_row_(g, 4, 'Unity-Gain Noise Level', ...
                'Not designed', ...
                stimgen.util.tooltip('CalibrationGui', 'FilterLevelReference'));
        end

        function build_display_section_(obj, g)
            % Toggles that change only what is drawn. The rest of the drawing
            % options are checkable items on the View menu.
            obj.ShowLivePlotsCheck = check_row_(g, 1, 'Show Engine Live Plots', ...
                stimgen.util.tooltip('CalibrationGui', 'ShowLivePlots'));
            obj.TransferLogXCheck = check_row_(g, 2, 'Transfer Plot Log X-Axis', ...
                stimgen.util.tooltip('CalibrationGui', 'TransferLogX'), ...
                @(src,~) obj.set_transfer_log_x_(src.Value));
            obj.TransferLogXCheck.Value = true;
        end

        function build_footer_(obj, col)
            % Pinned below the scrolling stack: during a run these are the only
            % controls and readouts that matter, and none may scroll out of
            % reach.
            foot = uigridlayout(col, [3 2]);
            foot.Layout.Row = 2;
            foot.Layout.Column = 1;
            foot.RowHeight = {30, 22, 24};
            foot.ColumnWidth = {'1x', '1x'};
            foot.Padding = [0 4 0 4];
            foot.RowSpacing = 4;

            obj.BtnStop = action_button_(foot, 1, 1, 'Stop', 'BtnStop', ...
                @(~,~) obj.on_stop_());
            obj.BtnStop.BackgroundColor = [0.7 0.15 0.15];
            obj.BtnStop.FontColor = [1 1 1];
            obj.BtnStop.Enable = 'off';

            obj.BtnReset = action_button_(foot, 1, 2, 'Reset Calibration', ...
                'BtnReset', @(~,~) obj.on_reset_calibration_());

            % Measured by the click probe at the head of every tone
            % acquisition, so it moves while a sweep runs -- and a wrong
            % reading invalidates the levels the sweep is writing. That makes
            % it something to watch during the run rather than a rig fact to
            % look up afterwards, which is why it sits here with the status
            % line and not in the settings window.
            obj.ConductionDelayLabel = readout_row_(foot, 2, 'Conduction Delay', ...
                'Not measured', stimgen.util.tooltip('CalibrationGui', 'ConductionDelay'));

            obj.StatusLabel = uilabel(foot, Text='Ready.', HorizontalAlignment='left');
            obj.StatusLabel.Layout.Row = 3;
            obj.StatusLabel.Layout.Column = [1 2];
        end

        function build_plots_panel_(obj)
            % Create the three axes and hand them to a LiveMonitor, which does
            % all the drawing -- live during a run, static between runs.
            panel = uipanel(obj.Grid, Title='Visualization');
            panel.Layout.Row = 1;
            panel.Layout.Column = 2;

            g = uigridlayout(panel, [2 2]);
            g.RowHeight = {'1x', '1x'};
            g.ColumnWidth = {'1x', '1x'};

            obj.AxTime = uiaxes(g);
            obj.AxTime.Layout.Row = 1;
            obj.AxTime.Layout.Column = 1;
            grid(obj.AxTime, 'on');

            obj.AxSpectrum = uiaxes(g);
            obj.AxSpectrum.Layout.Row = 1;
            obj.AxSpectrum.Layout.Column = 2;
            grid(obj.AxSpectrum, 'on');

            obj.AxTransfer = uiaxes(g);
            obj.AxTransfer.Layout.Row = 2;
            obj.AxTransfer.Layout.Column = [1 2];
            grid(obj.AxTransfer, 'on');

            obj.Monitor = stimgen.calibration.LiveMonitor(obj.Engine, ...
                Axes=[obj.AxTime obj.AxSpectrum obj.AxTransfer]);
            obj.Monitor.LogX = obj.TransferLogXCheck.Value;
            obj.sync_spectrum_units_menu_();
        end

        function on_spectrum_units_(obj, src)
            % Redraw the spectrum panel in the selected unit. The record is
            % kept in volts by the monitor, so this costs a redraw of what is
            % already measured -- nothing has to be re-acquired.
            obj.Monitor.SpectrumUnits = src.UserData;
            obj.sync_spectrum_units_menu_();
            obj.Monitor.show_engine_state(obj.Engine);
            obj.set_status_(sprintf('Spectrum in %s.', src.UserData), false);
        end

        function sync_spectrum_units_menu_(obj)
            % Check the item matching the monitor's unit, so the menu follows
            % the monitor even when something other than the menu set it.
            if isempty(obj.SpectrumUnitMenus)
                return
            end
            for h = obj.SpectrumUnitMenus
                h.Checked = matlab.lang.OnOffSwitchState(h.UserData == obj.Monitor.SpectrumUnits);
            end
        end

        function set_transfer_log_x_(obj, tf)
            % Log or linear frequency on the transfer panel.
            obj.Monitor.LogX = tf;
            obj.sync_display_controls_();
            obj.redraw_transfer_view_();
        end

        function set_show_ghost_(obj, tf)
            % Overlay of the previous spectrum. Only the response panels are
            % redrawn: a transfer redraw resets the monitor's whole graphics
            % cache, and the ghost being toggled -- along with the measurement
            % behind it that has not been drawn yet -- lives in that cache.
            obj.Monitor.ShowGhost = tf;
            obj.sync_display_controls_();
            obj.Monitor.show_engine_state(obj.Engine);
        end

        function set_show_voltage_(obj, tf)
            % Right-hand drive-voltage axis on the transfer panel.
            obj.Monitor.ShowVoltage = tf;
            obj.sync_display_controls_();
            obj.redraw_transfer_view_();
        end

        function set_transfer_view_(obj, view)
            % Point the transfer panel at one of its two views. Everything
            % that switches it comes through here -- both menu items, both
            % toolbar buttons, and the fallback when a reset takes the
            % background data away -- so the state, the controls mirroring it,
            % and what is on screen cannot disagree.
            arguments
                obj
                view (1,1) string {mustBeMember(view, ["calibration", "background"])}
            end
            obj.TransferView_ = view;
            obj.sync_display_controls_();
            obj.redraw_transfer_view_();
            if view == "background"
                obj.set_status_('Showing background noise analysis.', false);
            else
                obj.set_status_('Showing calibration transfer curves.', false);
            end
        end

        function redraw_transfer_view_(obj)
            % Redraw whichever view the transfer panel is serving, without
            % changing which one that is. show_background resets the monitor's
            % whole graphics cache, not just the transfer panel's share of it,
            % so the response panels have to be redrawn after it -- the same
            % ordering refresh_all_plots_ depends on.
            if obj.TransferView_ == "background"
                obj.Monitor.show_background(obj.Engine);
                obj.Monitor.show_engine_state(obj.Engine);
            else
                obj.refresh_all_plots_();
            end
        end

        function sync_display_controls_(obj)
            % Push the display state to every control that mirrors it: the
            % View menu, the display toolbar, and the Display section's
            % checkbox. One writer for all three, so a change made through any
            % of them shows on the others without each callback having to know
            % what the others are. Setting a toggle tool's State
            % programmatically does not fire its ClickedCallback, so this
            % cannot re-enter the handler that called it.
            if isempty(obj.Monitor) || ~isvalid(obj.Monitor)
                return
            end

            isBackground = obj.TransferView_ == "background";
            set_checked_(obj.CalibrationViewMenu, ~isBackground);
            set_checked_(obj.BackgroundViewMenu,  isBackground);
            set_checked_(obj.GhostMenu,   obj.Monitor.ShowGhost);
            set_checked_(obj.VoltageMenu, obj.Monitor.ShowVoltage);

            set_tool_state_(obj.ToolCalibrationView, ~isBackground);
            set_tool_state_(obj.ToolBackgroundView,  isBackground);
            set_tool_state_(obj.ToolGhost,   obj.Monitor.ShowGhost);
            set_tool_state_(obj.ToolVoltage, obj.Monitor.ShowVoltage);
            set_tool_state_(obj.ToolLogX,    obj.Monitor.LogX);

            if ~isempty(obj.TransferLogXCheck) && all(isgraphics(obj.TransferLogXCheck))
                obj.TransferLogXCheck.Value = obj.Monitor.LogX;
            end
        end

        function on_weighting_(obj, src)
            % Toggle one weighting curve on the transfer panel.
            src.Checked = ~strcmp(src.Checked, 'on');
            obj.apply_weightings_();
        end

        function on_weighting_none_(obj)
            % Clear every weighting curve in one step.
            set(obj.WeightingMenus, Checked='off');
            obj.apply_weightings_();
        end

        function apply_weightings_(obj)
            % Push the checked set to the monitor, which owns the curves, and
            % redraw so the change shows without waiting for a measurement.
            % Redrawn in whichever view is up: an overlay is an annotation on
            % the current view, and switching the panel out from under a user
            % who asked for A-weighting on the noise floor is not what they
            % asked for.
            checked = arrayfun(@(h) strcmp(h.Checked, 'on'), obj.WeightingMenus);
            obj.Monitor.Weightings = ...
                stimgen.calibration.LiveMonitor.WeightingTypes(checked);
            obj.redraw_transfer_view_();
        end

        function on_close_(obj, fig)
            % Settings are snapshotted before anything is torn down: the
            % monitor still holds the display state being saved.
            obj.save_settings_prefs_();
            % Release the monitor before the axes it draws into are deleted.
            % The engine may outlive this window -- it might be shared with a
            % host application -- and must not keep notifying a renderer whose
            % axes died with the figure.
            if ~isempty(obj.Monitor) && isvalid(obj.Monitor)
                obj.Monitor.detach();
                delete(obj.Monitor);
            end
            % The settings window is a satellite of this one and has
            % no reason to outlive it.
            if ~isempty(obj.HardwareDialog_) && isvalid(obj.HardwareDialog_)
                delete(obj.HardwareDialog_);
            end
            delete(fig);
        end

        function on_measure_reference_(obj)
            if ~obj.apply_controls_to_engine_()
                return
            end

            % The step records only -- the tone comes from an acoustic
            % calibrator on the microphone -- so the rig has to be set up by
            % hand before the recording starts. Confirming here is what makes
            % that sequence explicit instead of a silent prerequisite.
            msg = sprintf([ ...
                'Place the acoustic calibrator (e.g. PCB CAL150) on the microphone ' ...
                'and switch it on.\n\n' ...
                'It must produce %g Hz at %g dB SPL, matching the Reference ' ...
                'Frequency and Reference Level fields.\n\n' ...
                'Nothing is played through the speaker: the microphone is recorded ' ...
                'for one second and the calibrator sets the scale.'], ...
                obj.Engine.ReferenceFrequency, obj.Engine.ReferenceLevel);
            choice = uiconfirm(obj.Figure, msg, 'Measure Reference', ...
                Options={'Record', 'Cancel'}, DefaultOption=1, CancelOption=2, ...
                Icon='info');
            if ~strcmp(choice, 'Record')
                obj.set_status_('Reference measurement cancelled.', false);
                return
            end

            obj.with_busy_state_(@() obj.run_measure_reference_(), 'Recording calibrator...');
        end

        function run_measure_reference_(obj)
            obj.Engine.calibrate_reference();
            obj.sync_controls_();
            obj.Monitor.show_engine_state(obj.Engine);
            obj.set_status_('Reference measurement complete. Remove the calibrator.', false);
        end

        function on_measure_background_(obj)
            if ~obj.apply_controls_to_engine_()
                return
            end
            obj.with_busy_state_(@() obj.run_measure_background_(), ...
                'Recording background...', true);
        end

        function run_measure_background_(obj)
            [duration, nRecords, promDb, wasCancelled] = obj.prompt_background_parameters_();
            if wasCancelled
                obj.set_status_('Background measurement cancelled.', false);
                return
            end

            r = obj.Engine.measure_background(duration, nRecords, ...
                TonalProminenceDb=promDb);

            % The panels are left showing the background rather than refreshed
            % back to the lookup tables: the band curve is the result, and
            % View > Calibration Transfer Curves brings the tables back. Routed
            % through set_transfer_view_ rather than drawn directly, so the
            % view the panel is left on is the view the menu and toolbar report.
            obj.set_transfer_view_("background");

            hasFindings = ~isempty(r.flags);
            obj.set_status_(background_summary_(r), hasFindings);

            if hasFindings
                icon = 'warning';
            else
                icon = 'info';
            end
            uialert(obj.Figure, background_report_(r), 'Background Noise', Icon=icon);
        end

        function [duration, nRecords, promDb, wasCancelled] = prompt_background_parameters_(obj)
            % Collect the capture parameters. The first prompt carries the
            % physical prerequisites: unlike a sweep, this measurement is only
            % meaningful when the rig is in the state an experiment runs in,
            % and nothing else in the dialog can say so.
            durationPref = obj.get_pref_('backgroundDurationS', '2');
            recordsPref  = obj.get_pref_('backgroundRecords', '3');
            promPref     = obj.get_pref_('backgroundProminenceDb', '6');

            prompts = {
                ['Nothing is played during this measurement. Take the acoustic ' ...
                 'calibrator off the microphone, put the microphone where it sits ' ...
                 'during an experiment, and leave the rig running as it normally ' ...
                 'does. Recording duration (s, >0):'], ...
                'Number of records (positive integer). Their spectra are averaged, and the spread of their levels reports how steady the background is:', ...
                'Tonal peak prominence (dB above the local noise floor). Peaks below this are not reported:'
            };
            defaults = {durationPref, recordsPref, promPref};
            answer = inputdlg(prompts, 'Measure Background', [3 90; 2 90; 2 90], defaults);

            if isempty(answer)
                duration = 2;
                nRecords = 3;
                promDb = 6;
                wasCancelled = true;
                return
            end

            durationText = strtrim(string(answer{1}));
            duration = str2double(durationText);
            if isnan(duration) || ~isfinite(duration) || duration <= 0
                error('stimgen:calibration:CalibrationGui:badDuration', ...
                    'Recording duration must be a positive number of seconds.');
            end

            recordsText = strtrim(string(answer{2}));
            nRecords = obj.parse_positive_integer_(recordsText, 'number of records');

            promText = strtrim(string(answer{3}));
            promDb = str2double(promText);
            if isnan(promDb) || ~isfinite(promDb) || promDb <= 0
                error('stimgen:calibration:CalibrationGui:badProminence', ...
                    'Tonal peak prominence must be a positive number of decibels.');
            end

            obj.set_pref_('backgroundDurationS', char(durationText));
            obj.set_pref_('backgroundRecords', char(recordsText));
            obj.set_pref_('backgroundProminenceDb', char(promText));
            wasCancelled = false;
        end

        function update_background_view_state_(obj)
            % The background view is only reachable once something has been
            % captured; there is nothing to draw before that. A Reset takes the
            % data away without touching the panel, so a view still pointing at
            % it falls back to the lookup tables rather than leaving the menu
            % and toolbar claiming a view that can no longer be drawn. Nothing
            % is redrawn here: every caller draws for its own reasons.
            C = obj.Engine.CalibrationData;
            hasBackground = isstruct(C) && isfield(C, 'background') && ~isempty(C.background);

            set_enabled_(obj.BackgroundViewMenu,  hasBackground);
            set_enabled_(obj.ToolBackgroundView,  hasBackground);

            if ~hasBackground && obj.TransferView_ == "background"
                obj.TransferView_ = "calibration";
            end
            obj.sync_display_controls_();
        end

        function on_calibrate_tones_(obj)
            if ~obj.apply_controls_to_engine_()
                return
            end
            obj.with_busy_state_(@() obj.run_calibrate_tones_(), 'Running tone calibration...', true);
        end

        function run_calibrate_tones_(obj)
            [freqs, repeatCount, refine, wasCancelled] = obj.prompt_vector_parameter_( ...
                'toneFreqs', ...
                'toneRepeats', ...
                'Tone frequencies (Hz), e.g. 500:250:32000 or 500.*2.^(0:.5:5). Leave empty to use default log sweep.', ...
                'Tone Calibration', ...
                '', ...
                1, ...
                obj.IterativeCheck.Value);
            if wasCancelled
                obj.set_status_('Tone calibration cancelled.', false);
                return
            end
            if isempty(freqs)
                obj.Engine.calibrate_tones([], repeatCount);
            else
                obj.Engine.calibrate_tones(freqs, repeatCount);
            end
            if isempty(refine)
                obj.refresh_all_plots_();
                obj.update_runtime_state_();
                obj.set_status_('Tone calibration complete.', false);
                return
            end

            % The sweep's own averaging carries into the refinement passes:
            % what was accurate enough to build the table is accurate enough
            % to correct it.
            obj.set_status_('Tone calibration complete. Refining against measured levels...', false);
            drawnow;
            r = obj.Engine.refine_tones( ...
                MaxIterations=refine.MaxIterations, ...
                ToleranceDb=refine.ToleranceDb, ...
                RepeatCount=repeatCount);
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.report_refinement_(r, 'Tone');
        end

        function on_calibrate_clicks_(obj)
            if ~obj.apply_controls_to_engine_()
                return
            end
            obj.with_busy_state_(@() obj.run_calibrate_clicks_(), 'Running click calibration...', true);
        end

        function run_calibrate_clicks_(obj)
            [durs, repeatCount, refine, wasCancelled] = obj.prompt_vector_parameter_( ...
                'clickDurationsMs', ...
                'clickRepeats', ...
                'Click durations (ms), e.g. 0.01 0.02 0.04 or 0.01.*2.^(0:9). Leave empty for the default 0.01..5.12 ms octave series. Durations below one sample at the current Fs are skipped.', ...
                'Click Calibration', ...
                '', ...
                1, ...
                obj.IterativeCheck.Value);
            if wasCancelled
                obj.set_status_('Click calibration cancelled.', false);
                return
            end
            if isempty(durs)
                obj.Engine.calibrate_clicks([], repeatCount);
            else
                % Prompt is in ms; Engine.calibrate_clicks takes seconds.
                obj.Engine.calibrate_clicks(durs ./ 1e3, repeatCount);
            end
            if isempty(refine)
                obj.refresh_all_plots_();
                obj.update_runtime_state_();
                obj.set_status_('Click calibration complete.', false);
                return
            end

            % The sweep's own averaging carries into the refinement passes:
            % what was accurate enough to build the table is accurate enough
            % to correct it.
            obj.set_status_('Click calibration complete. Refining against measured levels...', false);
            drawnow;
            r = obj.Engine.refine_clicks( ...
                MaxIterations=refine.MaxIterations, ...
                ToleranceDb=refine.ToleranceDb, ...
                RepeatCount=repeatCount);
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.report_refinement_(r, 'Click');
        end

        function on_calibrate_swept_sine_(obj)
            if ~obj.apply_controls_to_engine_()
                return
            end
            obj.with_busy_state_(@() obj.run_calibrate_swept_sine_(), 'Running swept sine calibration...', true);
        end

        function run_calibrate_swept_sine_(obj)
            [duration, freqs, repeatCount, wasCancelled] = obj.prompt_swept_sine_parameters_();
            if wasCancelled
                obj.set_status_('Swept sine calibration cancelled.', false);
                return
            end
            if isempty(freqs)
                obj.Engine.calibrate_swept_sine(duration, [], repeatCount);
            else
                obj.Engine.calibrate_swept_sine(duration, freqs, repeatCount);
            end
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.set_status_('Swept sine calibration complete.', false);
        end

        function on_tone_lut_source_(obj)
            % Applies immediately rather than at the next run: the source
            % choice affects lookups on committed data, not measurements.
            if obj.ToneSweptSineCheck.Value
                obj.Engine.set_configuration(ToneLutSource="swept_sine");
                C = obj.Engine.CalibrationData;
                if isstruct(C) && isfield(C, 'swept_sine') && ~isempty(C.swept_sine)
                    obj.set_status_('Tone lookups now use the swept sine calibration, overriding any direct tone calibration.', false);
                else
                    obj.set_status_('Tone lookups will use the swept sine calibration once one is run; until then the direct tone calibration applies.', false);
                end
            else
                obj.Engine.set_configuration(ToneLutSource="tone");
                obj.set_status_('Tone lookups use the direct tone calibration.', false);
            end
        end

        function on_test_tones_(obj)
            if ~obj.apply_controls_to_engine_()
                return
            end
            obj.with_busy_state_(@() obj.run_test_tones_(), 'Testing tone lookup table...', true);
        end

        function run_test_tones_(obj)
            % Verify the tone LUT empirically: Engine.test_tones plays discrete
            % tones at the drive voltages the table asks for and compares the
            % levels that come back to the ones requested. Stored in
            % CalibrationData.toneTest by the engine.
            [freqs, levels, repeatCount, wasCancelled] = obj.prompt_tone_test_parameters_();
            if wasCancelled
                obj.set_status_('Tone LUT test cancelled.', false);
                return
            end

            % The plots are deliberately left showing the test's own curve
            % rather than refreshed back to the committed LUTs -- the measured
            % level against the requested one is the result.
            r = obj.Engine.test_tones(freqs, levels, RepeatCount=repeatCount);

            if r.passed
                verdict = 'PASS';
            else
                verdict = 'FAIL';
            end
            msg = sprintf( ...
                'Tone LUT test %s (%s table): worst error %.2f dB at %.0f Hz / %g dB SPL, bias %+.2f dB (tolerance %.1f dB).', ...
                verdict, r.lut_source, r.max_abs_error_db, r.worst.frequency, ...
                r.worst.level_db, r.bias_db, r.tolerance_db);

            nSkipped = numel(r.skipped.frequency);
            if nSkipped > 0
                msg = sprintf('%s %d point(s) skipped as unreachable.', msg, nSkipped);
            end
            obj.set_status_(msg, ~r.passed);

            if ~r.passed
                uialert(obj.Figure, sprintf(['%s\n\nLevels are not being reproduced within ' ...
                    'tolerance. A uniform bias usually means the reference measurement or ' ...
                    'Normative Value moved since the sweep; errors at scattered frequencies ' ...
                    'mean the table is too sparse to interpolate through -- recalibrate tones ' ...
                    'with a finer frequency list.'], msg), ...
                    'Tone LUT Test Failed', Icon='warning');
            end
        end

        function on_test_clicks_(obj)
            if ~obj.apply_controls_to_engine_()
                return
            end
            obj.with_busy_state_(@() obj.run_test_clicks_(), 'Testing click lookup table...', true);
        end

        function run_test_clicks_(obj)
            % Verify the click LUT empirically: Engine.test_clicks plays clicks
            % at the drive voltages the table asks for and compares the levels
            % that come back to the ones requested. Stored in
            % CalibrationData.clickTest by the engine.
            [durs, levels, repeatCount, wasCancelled] = obj.prompt_click_test_parameters_();
            if wasCancelled
                obj.set_status_('Click LUT test cancelled.', false);
                return
            end

            % Prompt is in ms; Engine.test_clicks takes seconds. The plots are
            % deliberately left showing the test's own curve rather than
            % refreshed back to the committed LUTs -- the measured level
            % against the requested one is the result.
            r = obj.Engine.test_clicks(durs ./ 1e3, levels, RepeatCount=repeatCount);

            if r.passed
                verdict = 'PASS';
            else
                verdict = 'FAIL';
            end
            msg = sprintf( ...
                'Click LUT test %s: worst error %.2f dB at %.1f \x00B5s / %g dB SPL, bias %+.2f dB (tolerance %.1f dB).', ...
                verdict, r.max_abs_error_db, r.worst.duration * 1e6, ...
                r.worst.level_db, r.bias_db, r.tolerance_db);

            nSkipped = numel(r.skipped.duration);
            if nSkipped > 0
                msg = sprintf('%s %d point(s) skipped as unreachable.', msg, nSkipped);
            end
            obj.set_status_(msg, ~r.passed);

            if ~r.passed
                uialert(obj.Figure, sprintf(['%s\n\nLevels are not being reproduced within ' ...
                    'tolerance. A uniform bias usually means the reference measurement or ' ...
                    'Normative Value moved since the sweep; errors at scattered durations ' ...
                    'mean the table is too sparse to interpolate through -- recalibrate ' ...
                    'clicks with a finer duration list. Very short clicks are the first to ' ...
                    'fail on SNR, since they put little energy into the room.'], msg), ...
                    'Click LUT Test Failed', Icon='warning');
            end
        end

        function on_design_filter_(obj)
            obj.with_busy_state_(@() obj.run_design_filter_(), 'Designing filter...');
        end

        function run_design_filter_(obj)
            [source, opts, wasCancelled] = obj.prompt_filter_parameters_();
            if wasCancelled
                obj.set_status_('Filter design cancelled.', false);
                return
            end
            args = namedargs2cell(opts);
            obj.Engine.design_filter(source, args{:});
            D = obj.Engine.CalibrationData.filterDesign;
            % %.10g: full precision for TDT-style non-integer rates
            % (24414.0625), plain "44100" for integer ones. %g would show two
            % nearly equal rates as the same number while calling them
            % mismatched.
            msg = sprintf( ...
                'Equalization filter designed: %d taps, %.1f dB correction span, Fs = %.10g Hz.', ...
                D.numCoefficients, D.correctionDb, D.sampleRate);

            % The number a hardware chain scales its gain against, stated at
            % design time so it travels with the taps it belongs to. Guarded:
            % the reference needs the LUT lookup, which can still refuse.
            try
                rRef = obj.Engine.filter_level_reference(1);
                msg = sprintf(['%s 1 V RMS white noise at unity gain: %.1f dB SPL ' ...
                    '(scale by %.3g for %g dB SPL).'], ...
                    msg, rRef.unityGainSpl, rRef.scale, rRef.normativeValue);
            catch
            end

            % A filter cut for a rate other than the one attached is a
            % legitimate thing to want, and a silent trap if it was not
            % intended -- test_filter is the only thing that refuses it, and
            % apply_calibration would happily run it at the wrong rate. Flag it
            % on the way out.
            fsHardware = obj.Engine.Fs;
            isOverride = fsHardware > 0 && abs(D.sampleRate - fsHardware) > 1e-6 * fsHardware;
            if isOverride
                msg = sprintf(['%s The attached hardware runs at %.10g Hz, so this filter is ' ...
                    'for another rig -- it cannot be tested or used here.'], msg, fsHardware);
            end
            obj.set_status_(msg, isOverride);
        end

        function on_test_filter_(obj)
            % Verify the calibration the way it will actually be used. A
            % filter designed from the tone table is checked with real
            % discrete tones -- played at the drive voltages the lookup
            % table asks for -- because that table, not the sweep, is what
            % scales a stimulus. A swept sine design is checked with the
            % sweep flatness test.
            if obj.filter_source_() == "tone"
                obj.on_test_tones_();
            else
                obj.with_busy_state_(@() obj.run_test_filter_(), 'Testing filter...', true);
            end
        end

        function run_test_filter_(obj)
            % Verify the designed filter empirically: Engine.test_filter plays
            % the sweep raw and through the filter and compares the flatness
            % of the two measured responses. Stored in
            % CalibrationData.filterTest by the engine.
            r = obj.Engine.test_filter();
            if r.passed
                verdict = 'PASS';
            else
                verdict = 'FAIL';
            end
            msg = sprintf( ...
                'Filter test %s: ripple %.1f \x2192 %.1f dB over %g\x2013%g Hz (tolerance %.1f dB).', ...
                verdict, r.unfiltered.ripple_db, r.filtered.ripple_db, ...
                r.band(1), r.band(2), r.ripple_tolerance_db);
            obj.set_status_(msg, ~r.passed);
            if ~r.passed
                uialert(obj.Figure, sprintf(['%s\n\nThe equalized response still ripples more ' ...
                    'than the tolerance. Consider redesigning the filter (more taps, or less ' ...
                    'smoothing/correction limiting).'], msg), ...
                    'Filter Test Failed', Icon='warning');
            end
        end

        function on_copy_filter_coefficients_(obj)
            % Put the equalizer's taps on the system clipboard, one per line
            % and nothing else, so the text pastes as-is into an RPvds
            % coefficient file, a spreadsheet column, or another language's
            % array literal. The design metadata a reader needs alongside them
            % -- tap count and design rate -- goes to the status line instead
            % of into the text, which stays purely numeric.
            C = obj.Engine.CalibrationData;
            if ~isstruct(C) || ~isfield(C, 'filter') || isempty(C.filter)
                obj.set_status_('No equalization filter to copy. Design or load one first.', true);
                return
            end

            filt = C.filter;
            if ~isfir(filt)
                obj.set_status_(['This filter is not FIR, so it has no single tap list. ' ...
                    'Redesign it, or read the coefficients from the .esgc file.'], true);
                return
            end
            b = tf(filt);

            % %.17g round-trips a double exactly. The taps are the calibration
            % once they leave here -- whatever reads them back has no way to
            % recover a digit this print drops.
            if ispc
                eol = sprintf('\r\n');   % Notepad and RPvds want CRLF
            else
                eol = newline;
            end
            txt = strjoin(compose('%.17g', b(:)), eol);

            try
                clipboard('copy', char(txt));
            catch ME
                stimgen.util.vprintf(0, 1, ME);
                obj.set_status_(sprintf('Could not write to the clipboard: %s', ME.message), true);
                return
            end

            fs = obj.filter_design_rate_();
            if fs > 0
                % %.10g: 24414.0625 is a real converter rate, and a filter is
                % only its designed response at the rate it was cut for.
                msg = sprintf('%d filter coefficients copied to the clipboard (designed for Fs = %.10g Hz).', ...
                    numel(b), fs);
            else
                msg = sprintf('%d filter coefficients copied to the clipboard.', numel(b));
            end
            obj.set_status_(msg, false);
        end

        function on_save_(obj)
            obj.with_busy_state_(@() obj.run_save_(''), 'Saving calibration file...');
        end

        function run_save_(obj, ffn)
            arguments
                obj
                ffn (1,:) char = ''
            end
            ffn = obj.Engine.save(ffn);
            if isempty(ffn)
                obj.set_status_('Save cancelled.', false);
                return
            end
            obj.add_recent_calibration_(ffn);
            obj.set_status_('Calibration saved.', false);
        end

        function on_load_(obj)
            obj.with_busy_state_(@() obj.run_load_(''), 'Loading calibration file...');
        end

        function run_load_(obj, ffn)
            arguments
                obj
                ffn (1,:) char = ''
            end
            if ~isempty(ffn) && ~isfile(ffn)
                obj.remove_recent_calibration_(ffn);
                obj.set_status_(sprintf('Recent calibration not found: %s', ffn), true);
                return
            end

            prevAdapter = obj.Engine.Adapter;
            [eng, ffn] = stimgen.calibration.Engine.load(ffn);
            if isempty(eng)
                obj.set_status_('Load cancelled.', false);
                return
            end
            if ~isempty(prevAdapter)
                eng.set_adapter(prevAdapter);
            end
            obj.Engine = eng;
            % The monitor follows an engine, not this object; a load that
            % swaps the engine has to move it across or it would keep
            % rendering the discarded one. The delay listener follows the
            % engine the same way.
            obj.Monitor.attach(eng);
            obj.bind_engine_listeners_();
            obj.sync_controls_();
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.add_recent_calibration_(ffn);
            obj.set_status_('Calibration loaded.', false);
        end

        function on_attach_adapter_(obj)
            obj.with_busy_state_(@() obj.run_attach_adapter_(), 'Attaching adapter...');
        end

        function run_attach_adapter_(obj)
            obj.assert_host_();
            obj.set_adapter(obj.Host.calibrationAdapter());
        end

        function on_initialize_runtime_(obj)
            obj.with_busy_state_(@() obj.run_initialize_runtime_(''), 'Initializing calibration runtime...');
        end

        function run_initialize_runtime_(obj, protocolPath)
            arguments
                obj
                protocolPath (1,:) char = ''
            end
            obj.assert_host_();

            if isempty(protocolPath)
                [fn, pn] = uigetfile( ...
                    {'*.eprot;*.prot;*.json', 'Protocol files (*.eprot, *.prot, *.json)'}, ...
                    'Load Protocol For Calibration');
                if isequal(fn, 0)
                    obj.set_status_('Runtime initialization cancelled.', false);
                    return
                end
                protocolPath = fullfile(pn, fn);
            elseif ~isfile(protocolPath)
                obj.remove_recent_protocol_(protocolPath);
                obj.set_status_(sprintf('Recent protocol not found: %s', protocolPath), true);
                return
            end

            obj.Host.loadProtocol(protocolPath);
            obj.Host.connect();
            obj.Host.setMode("Preview");

            obj.set_adapter(obj.Host.calibrationAdapter());
            obj.add_recent_protocol_(protocolPath);
            [~, fn, ext] = fileparts(protocolPath);
            obj.set_status_(sprintf('Runtime initialized from protocol: %s%s', fn, ext), false);
        end

        function on_disconnect_runtime_(obj)
            obj.with_busy_state_(@() obj.run_disconnect_runtime_(), 'Disconnecting calibration runtime...');
        end

        function run_disconnect_runtime_(obj)
            if ~isempty(obj.Host) && obj.Host.connectionState() ~= "None"
                try
                    obj.Host.setMode("Idle");
                catch ME
                    stimgen.util.vprintf(0, 1, 'CalibrationGui: failed to return runtime interfaces to Idle.');
                    stimgen.util.vprintf(0, 1, ME);
                end
                obj.Host.release();
            end

            obj.Engine.set_adapter([]);
            obj.update_runtime_state_();
            obj.set_status_('Calibration runtime disconnected.', false);
        end

        function refresh_recent_protocols_menu_(obj)
            obj.refresh_recent_menu_(obj.RecentProtocolsMenu, 'RecentProtocols', @obj.open_recent_protocol_);
        end

        function refresh_recent_calibrations_menu_(obj)
            obj.refresh_recent_menu_(obj.RecentCalibrationsMenu, 'RecentCalibrations', @obj.open_recent_calibration_);
        end

        function refresh_recent_menu_(obj, menu, prefName, openFcn)
            % Rebuild a Recent-files submenu (most recent first) from stored preferences.
            if isempty(menu) || ~isvalid(menu)
                return
            end
            delete(allchild(menu));

            paths = obj.get_recent_paths_(prefName);
            if isempty(paths)
                uimenu(menu, Text='(None)', Enable='off');
                return
            end

            for idx = 1:numel(paths)
                filePath = paths{idx};
                [~, fn, ext] = fileparts(filePath);
                uimenu(menu, ...
                    Text=sprintf('%d. %s%s | %s', idx, fn, ext, filePath), ...
                    MenuSelectedFcn=@(~,~) openFcn(filePath));
            end
        end

        function open_recent_protocol_(obj, filePath)
            % Re-run Initialize Runtime From Protocol with a remembered path.
            obj.with_busy_state_(@() obj.run_initialize_runtime_(filePath), 'Initializing calibration runtime...');
        end

        function open_recent_calibration_(obj, filePath)
            % Re-run Load .esgc with a remembered path.
            obj.with_busy_state_(@() obj.run_load_(filePath), 'Loading calibration file...');
        end

        function add_recent_protocol_(obj, filePath)
            obj.add_recent_path_('RecentProtocols', filePath);
            obj.refresh_recent_protocols_menu_();
        end

        function remove_recent_protocol_(obj, filePath)
            obj.remove_recent_path_('RecentProtocols', filePath);
            obj.refresh_recent_protocols_menu_();
        end

        function add_recent_calibration_(obj, filePath)
            obj.add_recent_path_('RecentCalibrations', filePath);
            obj.refresh_recent_calibrations_menu_();
        end

        function remove_recent_calibration_(obj, filePath)
            obj.remove_recent_path_('RecentCalibrations', filePath);
            obj.refresh_recent_calibrations_menu_();
        end

        function paths = get_recent_paths_(~, prefName)
            % Recent-file lists are cell arrays and so are kept out of
            % get_pref_/set_pref_, which coerce every stored value to char.
            groupName = 'StimCalibrationGui';
            if ispref(groupName, prefName)
                paths = getpref(groupName, prefName);
            else
                paths = {};
            end
            if ischar(paths)
                paths = {paths};
            end
            paths = paths(:).';
            paths = paths(~cellfun(@isempty, paths));
        end

        function add_recent_path_(obj, prefName, filePath)
            filePath = strtrim(char(filePath));
            if isempty(filePath)
                return
            end
            paths = obj.get_recent_paths_(prefName);
            paths(strcmpi(paths, filePath)) = [];
            paths = [{filePath}, paths];
            paths = paths(1:min(9, numel(paths)));
            setpref('StimCalibrationGui', prefName, paths);
        end

        function remove_recent_path_(obj, prefName, filePath)
            paths = obj.get_recent_paths_(prefName);
            paths(strcmpi(paths, char(filePath))) = [];
            setpref('StimCalibrationGui', prefName, paths);
        end

        function assert_host_(obj)
            % Guard the hardware-backed menu actions; offline mode has no host.
            if isempty(obj.Host)
                error('stimgen:calibration:CalibrationGui:noHost', ...
                    ['No hardware host is attached. Construct CalibrationGui with a ' ...
                    'stimgen.HardwareHost, or supply an Engine that already has an adapter.']);
            end
        end

        function on_show_quick_start_(obj)
            % Open the calibration walkthrough in a browser. The workflow is
            % maintained once, on the wiki, rather than in a dialog that drifts
            % out of step with the GUI it describes.
            status = web(stimgen.calibration.CalibrationGui.QuickStartURL, '-browser');
            if status ~= 0
                uialert(obj.Figure, sprintf(['No browser could be opened.\n\n' ...
                    'The calibration walkthrough is at:\n%s'], ...
                    stimgen.calibration.CalibrationGui.QuickStartURL), ...
                    'Calibration Quick Start', Icon='info');
            end
        end

        function ok = apply_controls_to_engine_(obj)
            ok = false;
            try
                if obj.ToneSweptSineCheck.Value
                    toneLutSource = "swept_sine";
                else
                    toneLutSource = "tone";
                end
                % Max Output Voltage and AC Couple are absent deliberately:
                % the settings window pushes them to the engine the
                % moment they change, and its controls exist only while it is
                % open.
                obj.Engine.set_configuration( ...
                    ReferenceLevel=obj.RefLevelField.Value, ...
                    ReferenceFrequency=obj.RefFreqField.Value, ...
                    MicSensitivity=obj.MicSensField.Value, ...
                    NormativeValue=obj.NormativeField.Value, ...
                    ExcitationVoltage=obj.ExcitationField.Value, ...
                    ShowLivePlots=obj.ShowLivePlotsCheck.Value, ...
                    ToneLutSource=toneLutSource);
                ok = true;
                % Every run starts here, so saving on success means a hard
                % MATLAB exit costs at most the edits since the last run.
                obj.save_settings_prefs_();
                % The unity-gain readout is anchored to NormativeValue and
                % the LUT choice, both of which may have just changed.
                obj.refresh_level_reference_label_();
            catch ME
                obj.set_status_(sprintf('Parameter update failed: %s', ME.message), true);
                uialert(obj.Figure, ME.message, 'Parameter Error', Icon='error');
            end
        end

        function sync_controls_(obj)
            obj.RefLevelField.Value = obj.Engine.ReferenceLevel;
            obj.RefFreqField.Value = obj.Engine.ReferenceFrequency;
            obj.MicSensField.Value = obj.Engine.MicSensitivity;
            obj.NormativeField.Value = obj.Engine.NormativeValue;
            obj.ExcitationField.Value = obj.Engine.ExcitationVoltage;
            obj.ShowLivePlotsCheck.Value = obj.Engine.ShowLivePlots;
            obj.ToneSweptSineCheck.Value = obj.Engine.ToneLutSource == "swept_sine";
            obj.sync_hardware_dialog_();
        end

        function refresh_all_plots_(obj)
            % Redraw all three panels from the Engine's current state, via the
            % monitor. Order matters: show_calibration resets the monitor's
            % graphics cache before drawing the lookup tables, so the response
            % panels have to be drawn after it, not before.
            obj.Monitor.show_calibration(obj.Engine);
            obj.Monitor.show_engine_state(obj.Engine);
        end

        function update_runtime_state_(obj)
            obj.refresh_sample_rate_label_();
            obj.refresh_conduction_delay_label_();
            obj.refresh_level_reference_label_();

            obj.update_background_view_state_();

            hasAdapter = ~isempty(obj.Engine.Adapter);
            if hasAdapter
                obj.BtnReference.Enable = 'on';
                obj.BtnBackground.Enable = 'on';
                obj.BtnTones.Enable = 'on';
                obj.BtnClicks.Enable = 'on';
                obj.BtnSweptSine.Enable = 'on';
            else
                obj.BtnReference.Enable = 'off';
                obj.BtnBackground.Enable = 'off';
                obj.BtnTones.Enable = 'off';
                obj.BtnClicks.Enable = 'off';
                obj.BtnSweptSine.Enable = 'off';
            end

            % Either LUT can drive the equalizer; Engine.design_filter picks.
            C = obj.Engine.CalibrationData;
            hasLut = obj.Engine.IsCalibrated && ...
                ((isfield(C, 'tone') && ~isempty(C.tone)) || ...
                 (isfield(C, 'swept_sine') && ~isempty(C.swept_sine)));
            % Testing the tone lookup needs a table to test and hardware to
            % play it through. hasLut is the right condition rather than a
            % tone-only one: with Tone Lookup From Swept Sine set, the sweep is
            % the table a Tone stimulus is scaled by, so it is what the test
            % has to verify.
            if hasLut && hasAdapter
                obj.BtnTestTones.Enable = 'on';
            else
                obj.BtnTestTones.Enable = 'off';
            end

            % The click table has no alternative source: only calibrate_clicks
            % ever writes it, so its own data is the condition.
            hasClickLut = obj.Engine.IsCalibrated && ...
                isfield(C, 'click') && ~isempty(C.click);
            if hasClickLut && hasAdapter
                obj.BtnTestClicks.Enable = 'on';
            else
                obj.BtnTestClicks.Enable = 'off';
            end

            if hasLut
                obj.BtnFilter.Enable = 'on';
            else
                obj.BtnFilter.Enable = 'off';
            end

            % Testing needs both a designed (or loaded) filter and hardware to
            % play it through.
            hasFilter = obj.Engine.IsCalibrated && ...
                isfield(C, 'filter') && ~isempty(C.filter);
            if hasFilter && hasAdapter
                obj.BtnTestFilter.Enable = 'on';
            else
                obj.BtnTestFilter.Enable = 'off';
            end

            % Copying reads the taps that already exist, so unlike testing it
            % asks nothing of the hardware -- a filter loaded from a .esgc on a
            % machine with no rig attached is still exportable.
            if hasFilter
                obj.BtnCopyFilter.Enable = 'on';
            else
                obj.BtnCopyFilter.Enable = 'off';
            end
        end

        function bind_engine_listeners_(obj)
            % Follow the current engine's ConductionDelay property. The click
            % probes fire during a run, while this window sits in
            % with_busy_state_ showing only "Running tone calibration...", so
            % without the listener the delay would not be seen until the run
            % finished.
            delete(obj.DelayListener_);
            obj.DelayListener_ = addlistener(obj.Engine, 'ConductionDelay', ...
                'PostSet', @(~,~) obj.refresh_conduction_delay_label_());
        end

        function refresh_conduction_delay_label_(obj)
            % Speaker-to-mic delay from the most recent click probe. The
            % equivalent air path at 343 m/s is the sanity check -- a reading
            % far from the actual mic distance means converter latency
            % dominates, or the probe locked onto the wrong thing.
            % Guarded rather than ordered: update_runtime_state_ may run
            % before the footer is built.
            if isempty(obj.ConductionDelayLabel) || ~isvalid(obj.ConductionDelayLabel)
                return
            end
            d = obj.Engine.ConductionDelay;
            if d.valid
                txt = sprintf('%.2f ms  (~%.2f m at 343 m/s)', ...
                    d.delay_s * 1e3, d.delay_s * 343);
                obj.ConductionDelayLabel.FontColor = [0 0 0];
            elseif d.at_bound || isfinite(d.delay_s)
                txt = 'Measurement unreliable';
                obj.ConductionDelayLabel.FontColor = [0.7 0 0];
            else
                txt = 'Not measured';
                obj.ConductionDelayLabel.FontColor = [0 0 0];
            end
            obj.ConductionDelayLabel.Text = txt;
        end

        function refresh_sample_rate_label_(obj)
            % %.10g keeps non-integer converter rates exact on screen; %g
            % would show 24414.0625 as 24414.1, and a user transcribing that
            % rounded figure gets a filter assert_filter_rate refuses.
            % Lives in the settings window, so with that closed there
            % is nothing to update; reopening it refreshes from the engine.
            if isempty(obj.SampleRateLabel) || ~isvalid(obj.SampleRateLabel)
                return
            end
            fs = obj.Engine.Fs;
            if fs > 0
                txt = sprintf('%.10g Hz', fs);
            else
                txt = 'No adapter';
            end

            % An FIR's taps carry the rate they were designed for, so a loaded
            % calibration whose filter was cut at another rate equalizes the
            % wrong frequencies -- quietly, since apply_calibration does not
            % compare rates. Report it where the rate is read, not only when
            % test_filter happens to be run.
            designFs = obj.filter_design_rate_();
            mismatched = designFs > 0 && (fs <= 0 || abs(designFs - fs) > 1e-6 * fs);
            if mismatched
                txt = sprintf('%s (filter designed at %.10g Hz)', txt, designFs);
                obj.SampleRateLabel.FontColor = [0.7 0 0];
            else
                obj.SampleRateLabel.FontColor = [0 0 0];
            end
            obj.SampleRateLabel.Text = txt;
        end

        function refresh_level_reference_label_(obj)
            % SPL the equalized source produces at unity hardware gain, and
            % the factor that brings it to the normative level. This is what a
            % hardware chain (source -> FIR -> gain) needs, because
            % apply_calibration's renormalize-then-scale runs in software
            % only: without it the filter's insertion loss lands on the output
            % level. Shown for a 1 V RMS white-noise source -- the closed-form
            % case; a shaped source needs Engine.filter_level_reference with
            % its actual waveform.
            try
                r = obj.Engine.filter_level_reference(1);
                % char(215) is the multiplication sign; the scale reads as
                % "multiply the filtered source (or the taps) by this".
                obj.LevelRefLabel.Text = sprintf('%.1f dB SPL  (%c%.3g)', ...
                    r.unityGainSpl, char(215), r.scale);
            catch
                % No filter, or no LUT to anchor it -- either way there is no
                % reference to report yet.
                obj.LevelRefLabel.Text = 'Not designed';
            end
        end

        function src = filter_source_(obj)
            % src = filter_source_(obj)
            % LUT the current equalization filter was designed from ("tone"
            % or "swept_sine"), or "" when there is no filter or it predates
            % the filterSource metadata. Decides which verification Test
            % Calibration runs.
            src = "";
            C = obj.Engine.CalibrationData;
            if ~isstruct(C) || ~isfield(C, 'filter') || isempty(C.filter), return; end
            if isfield(C, 'filterSource')
                src = string(C.filterSource);
            end
        end

        function fs = filter_design_rate_(obj)
            % fs = filter_design_rate_(obj)
            % Rate the current equalization filter was designed for, or 0 when
            % there is no filter or it predates the filterDesign metadata.
            fs = 0;
            C = obj.Engine.CalibrationData;
            if ~isstruct(C) || ~isfield(C, 'filter') || isempty(C.filter), return; end
            if ~isfield(C, 'filterDesign') || ~isfield(C.filterDesign, 'sampleRate'), return; end
            v = double(C.filterDesign.sampleRate);
            if isscalar(v) && isfinite(v) && v > 0
                fs = v;
            end
        end

        function show_startup_hint_(obj)
            % Provide immediate guidance on the next actionable step.
            if isempty(obj.Engine.Adapter)
                obj.set_status_('No adapter attached. Initialize Runtime From Protocol, then Attach Adapter.', true);
                return
            end

            if obj.Engine.IsCalibrated
                obj.set_status_('Calibration loaded. Review plots or save updates.', false);
            else
                obj.set_status_('Ready. Start with "Measure Reference", then "Calibrate Tones".', false);
            end
        end

        function values = parse_numeric_vector_(~, textValue, label)
            % Delegated to the shared utility so every vector entry in the
            % package accepts the same syntax.
            values = stimgen.util.parse_numeric_vector(textValue, char(label));
        end

        function [values, repeatCount, refine, wasCancelled] = prompt_vector_parameter_(obj, prefName, repeatPrefName, promptText, dlgTitle, defaultValue, repeatDefault, includeRefinement)
            % With includeRefinement set (the Iterative Level Refinement
            % toggle), the same dialog also collects the refinement's pass
            % limit and accuracy target, so the whole run is parameterized in
            % one place before any hardware moves. refine is [] when the
            % toggle is off, or a struct with MaxIterations and ToleranceDb.
            if nargin < 8
                includeRefinement = false;
            end
            wasCancelled = false;
            refine = [];
            stored = obj.get_pref_(prefName, defaultValue);
            repeatStored = obj.get_pref_(repeatPrefName, num2str(repeatDefault));

            prompts = {
                promptText, ...
                'Number of averages (positive integer):'
            };
            defaults = {stored, repeatStored};
            if includeRefinement
                prompts(end+1:end+2) = {
                    ['Refinement: maximum test passes (positive integer). The table is ' ...
                     'corrected between passes and always left as the last pass verified it:'], ...
                    ['Refinement: target accuracy (dB). Passes stop early once every point ' ...
                     'lands within this of its requested level:']
                };
                defaults(end+1:end+2) = {
                    obj.get_pref_('refineMaxPasses', '3'), ...
                    obj.get_pref_('refineToleranceDb', '1')
                };
            end
            answer = inputdlg(prompts, dlgTitle, repmat([1 90], numel(prompts), 1), defaults);
            if isempty(answer)
                values = [];
                repeatCount = repeatDefault;
                wasCancelled = true;
                return
            end

            raw = strtrim(string(answer{1}));
            repeatRaw = strtrim(string(answer{2}));
            obj.set_pref_(prefName, char(raw));
            obj.set_pref_(repeatPrefName, char(repeatRaw));
            values = obj.parse_numeric_vector_(raw, lower(dlgTitle));
            repeatCount = obj.parse_positive_integer_(repeatRaw, 'number of averages');

            if includeRefinement
                passesRaw = strtrim(string(answer{3}));
                tolRaw    = strtrim(string(answer{4}));
                maxPasses = obj.parse_positive_integer_(passesRaw, 'maximum test passes');
                tolDb = str2double(tolRaw);
                if isnan(tolDb) || ~isfinite(tolDb) || tolDb <= 0
                    error('stimgen:calibration:CalibrationGui:badTolerance', ...
                        'Refinement target accuracy must be a positive number of decibels.');
                end
                obj.set_pref_('refineMaxPasses', char(passesRaw));
                obj.set_pref_('refineToleranceDb', char(tolRaw));
                refine = struct('MaxIterations', maxPasses, 'ToleranceDb', tolDb);
            end
        end

        function report_refinement_(obj, r, whatLabel)
            % Status line (and an alert on non-convergence) after an
            % iterative refinement. The residual is the last test's verdict,
            % so what is reported is what the committed table was measured
            % to do -- not what the corrections were hoped to achieve.
            if r.converged
                obj.set_status_(sprintf( ...
                    ['%s calibration refined: worst error %.2f dB after %d test ' ...
                     'pass(es), within the %.2g dB target.'], ...
                    whatLabel, r.final_max_abs_error_db, r.n_iterations, ...
                    r.tolerance_db), false);
                return
            end

            msg = sprintf( ...
                ['%s calibration refined from %.2f to %.2f dB worst error, but did ' ...
                 'not reach the %.2g dB target in %d test pass(es).'], ...
                whatLabel, r.initial_max_abs_error_db, r.final_max_abs_error_db, ...
                r.tolerance_db, r.n_iterations);
            obj.set_status_(msg, true);
            uialert(obj.Figure, sprintf(['%s\n\nThe table keeps the last verified ' ...
                'corrections, so nothing was lost. A residual that will not shrink ' ...
                'is usually measurement spread: raise the number of averages, or ' ...
                'loosen the target. If %d point(s) were left uncorrected as ' ...
                'unreliable, they are unreachable at the normative level or too ' ...
                'quiet to measure -- see the log.'], msg, r.n_unreliable), ...
                'Refinement Did Not Converge', Icon='warning');
        end

        function [duration, freqs, repeatCount, wasCancelled] = prompt_swept_sine_parameters_(obj)
            % The dialog works in milliseconds; the returned duration is in
            % seconds, as Engine.calibrate_swept_sine expects. The pref key
            % carries a Ms suffix so pre-ms values are not reinterpreted.
            durationPref = obj.get_pref_('sweptSineDurationMs', '1000');
            freqsPref = obj.get_pref_('sweptSineFreqs', '');
            repeatsPref = obj.get_pref_('sweptSineRepeats', '4');

            prompts = {
                'Swept sine duration (ms, >0):', ...
                'Swept sine frequencies (Hz). Leave empty to use default log sweep:', ...
                'Number of averages (positive integer):'
            };
            defaults = {durationPref, freqsPref, repeatsPref};
            answer = inputdlg(prompts, 'Swept Sine Calibration', [1 90; 1 90; 1 90], defaults);

            if isempty(answer)
                duration = 1;
                freqs = [];
                repeatCount = 4;
                wasCancelled = true;
                return
            end

            durationText = strtrim(string(answer{1}));
            durationMs = str2double(durationText);
            if isnan(durationMs) || ~isfinite(durationMs) || durationMs <= 0
                error('stimgen:calibration:CalibrationGui:badDuration', ...
                    'Swept sine duration must be a positive number of milliseconds.');
            end
            duration = durationMs / 1e3;

            freqsText = strtrim(string(answer{2}));
            freqs = obj.parse_numeric_vector_(freqsText, 'swept sine frequencies');

            repeatsText = strtrim(string(answer{3}));
            repeatCount = obj.parse_positive_integer_(repeatsText, 'number of averages');

            obj.set_pref_('sweptSineDurationMs', char(durationText));
            obj.set_pref_('sweptSineFreqs', char(freqsText));
            obj.set_pref_('sweptSineRepeats', char(repeatsText));
            wasCancelled = false;
        end

        function [freqs, levels, repeatCount, wasCancelled] = prompt_tone_test_parameters_(obj)
            % Collect the frequency/level grid for the tone LUT test. Both
            % lists default to empty, which hands the choice to Engine.test_tones:
            % the midpoints between LUT points, at NormativeValue and 10/20 dB
            % below it. Those defaults are the interesting ones, so the dialog
            % opens ready to run.
            freqsPref   = obj.get_pref_('toneTestFreqs', '');
            levelsPref  = obj.get_pref_('toneTestLevels', '');
            repeatsPref = obj.get_pref_('toneTestRepeats', '2');

            prompts = {
                'Test frequencies (Hz), e.g. 1000 2000 4000. Leave empty to probe midway between the calibrated points, where the table is interpolating:', ...
                'Requested levels (dB SPL), e.g. 50 60 70. Leave empty for the normative value and 10/20 dB below it:', ...
                'Number of averages (positive integer):'
            };
            defaults = {freqsPref, levelsPref, repeatsPref};
            answer = inputdlg(prompts, 'Test Tone Lookup Table', [1 90; 1 90; 1 90], defaults);

            if isempty(answer)
                freqs = [];
                levels = [];
                repeatCount = 2;
                wasCancelled = true;
                return
            end

            freqsText  = strtrim(string(answer{1}));
            levelsText = strtrim(string(answer{2}));
            repeatsText = strtrim(string(answer{3}));

            freqs       = obj.parse_numeric_vector_(freqsText, 'test frequencies');
            levels      = obj.parse_numeric_vector_(levelsText, 'requested levels');
            repeatCount = obj.parse_positive_integer_(repeatsText, 'number of averages');

            obj.set_pref_('toneTestFreqs', char(freqsText));
            obj.set_pref_('toneTestLevels', char(levelsText));
            obj.set_pref_('toneTestRepeats', char(repeatsText));
            wasCancelled = false;
        end

        function [durs, levels, repeatCount, wasCancelled] = prompt_click_test_parameters_(obj)
            % Collect the duration/level grid for the click LUT test. Both
            % lists default to empty, which hands the choice to
            % Engine.test_clicks: the midpoints between LUT points, at
            % NormativeValue and 10/20 dB below it. Durations are in
            % milliseconds here, as they are for the click sweep itself.
            dursPref    = obj.get_pref_('clickTestDurationsMs', '');
            levelsPref  = obj.get_pref_('clickTestLevels', '');
            repeatsPref = obj.get_pref_('clickTestRepeats', '2');

            prompts = {
                'Test click durations (ms), e.g. 0.02 0.08 0.32. Leave empty to probe midway between the calibrated durations, where the table is interpolating:', ...
                'Requested levels (dB SPL), e.g. 50 60 70. Leave empty for the normative value and 10/20 dB below it:', ...
                'Number of averages (positive integer):'
            };
            defaults = {dursPref, levelsPref, repeatsPref};
            answer = inputdlg(prompts, 'Test Click Lookup Table', [1 90; 1 90; 1 90], defaults);

            if isempty(answer)
                durs = [];
                levels = [];
                repeatCount = 2;
                wasCancelled = true;
                return
            end

            dursText    = strtrim(string(answer{1}));
            levelsText  = strtrim(string(answer{2}));
            repeatsText = strtrim(string(answer{3}));

            durs        = obj.parse_numeric_vector_(dursText, 'test click durations');
            levels      = obj.parse_numeric_vector_(levelsText, 'requested levels');
            repeatCount = obj.parse_positive_integer_(repeatsText, 'number of averages');

            obj.set_pref_('clickTestDurationsMs', char(dursText));
            obj.set_pref_('clickTestLevels', char(levelsText));
            obj.set_pref_('clickTestRepeats', char(repeatsText));
            wasCancelled = false;
        end

        function [source, opts, wasCancelled] = prompt_filter_parameters_(obj)
            % Collect equalizer design options. Everything except the source is
            % returned as a name-value struct for Engine.design_filter, so the
            % dialog stays a thin front end to that argument list.
            source = "auto";
            opts = struct();
            wasCancelled = false;

            % The design rate is offered here rather than as a settings field
            % because it belongs to the filter, not to the measurement: the LUT
            % is in Hz and volts and holds at any rate, while the taps fitted to
            % it only realize the designed response at the rate they were cut
            % for. Naming the hardware rate in the prompt makes an intentional
            % override obvious and an accidental one unlikely.
            % Full precision: this prompt is the one place a user is invited
            % to type a rate, and typing back a %g-rounded 24414.1 for a
            % 24414.0625 Hz converter designs a filter the rate guard refuses.
            fsHardware = obj.Engine.Fs;
            if fsHardware > 0
                ratePrompt = sprintf( ...
                    'Design sample rate (Hz; empty or 0 = hardware rate, %.10g Hz):', fsHardware);
            else
                ratePrompt = 'Design sample rate (Hz; required, no adapter attached):';
            end

            prompts = {
                'LUT source (auto | tone | swept_sine):', ...
                'Number of coefficients (taps; 0 = auto from LUT size):', ...
                'Design method (freqsamp | ls):', ...
                'Interpolation (pchip | linear | spline | makima):', ...
                'Frequency scale (log | linear):', ...
                'Fractional-octave smoothing (octaves, e.g. 0.333; 0 = none):', ...
                'Maximum correction depth (dB below peak; Inf = unlimited):', ...
                'Frequency range (Hz, "lo hi"; empty = LUT span):', ...
                ratePrompt
            };
            defaults = {
                obj.get_pref_('filterSource', 'auto'), ...
                obj.get_pref_('filterNumCoefficients', '0'), ...
                obj.get_pref_('filterDesignMethod', 'freqsamp'), ...
                obj.get_pref_('filterInterpolation', 'pchip'), ...
                obj.get_pref_('filterFrequencyScale', 'log'), ...
                obj.get_pref_('filterSmoothingOctaves', '0'), ...
                obj.get_pref_('filterMaxCorrectionDb', 'Inf'), ...
                obj.get_pref_('filterFrequencyRange', ''), ...
                obj.get_pref_('filterSampleRate', '')
            };

            answer = inputdlg(prompts, 'Design Equalization Filter', ...
                repmat([1 90], numel(prompts), 1), defaults);
            if isempty(answer)
                wasCancelled = true;
                return
            end

            raw = strtrim(string(answer));
            source           = obj.parse_choice_(raw(1), ["auto" "tone" "swept_sine"], 'LUT source');
            nCoef            = obj.parse_nonnegative_integer_(raw(2), 'number of coefficients');
            designMethod     = obj.parse_choice_(raw(3), ["freqsamp" "ls"], 'design method');
            interpolation    = obj.parse_choice_(raw(4), ["pchip" "linear" "spline" "makima"], 'interpolation');
            frequencyScale   = obj.parse_choice_(raw(5), ["log" "linear"], 'frequency scale');
            smoothingOctaves = obj.parse_nonnegative_scalar_(raw(6), 'smoothing width', 0, false);
            maxCorrectionDb  = obj.parse_nonnegative_scalar_(raw(7), 'maximum correction depth', Inf, true);
            if maxCorrectionDb <= 0
                error('stimgen:calibration:CalibrationGui:badCorrection', ...
                    'Maximum correction depth must be greater than zero, or Inf for unlimited.');
            end

            freqRange = obj.parse_numeric_vector_(raw(8), 'frequency range');
            if ~isempty(freqRange) && numel(freqRange) ~= 2
                error('stimgen:calibration:CalibrationGui:badFrequencyRange', ...
                    'Frequency range must be two values, "lo hi", or empty for the LUT span.');
            end

            sampleRate = obj.parse_nonnegative_scalar_(raw(9), 'design sample rate', 0, false);
            if sampleRate == 0 && fsHardware <= 0
                error('stimgen:calibration:CalibrationGui:noSampleRate', ...
                    ['With no adapter attached there is no hardware rate to fall back on. ' ...
                     'Enter the sample rate the filter will run at.']);
            end

            opts.DesignMethod     = designMethod;
            opts.Interpolation    = interpolation;
            opts.FrequencyScale   = frequencyScale;
            opts.SmoothingOctaves = smoothingOctaves;
            opts.MaxCorrectionDb  = maxCorrectionDb;
            opts.FrequencyRange   = freqRange;
            if nCoef > 0
                opts.NumCoefficients = nCoef;
            end
            if sampleRate > 0
                opts.SampleRate = sampleRate;
            end

            prefNames = {'filterSource', 'filterNumCoefficients', 'filterDesignMethod', ...
                         'filterInterpolation', 'filterFrequencyScale', ...
                         'filterSmoothingOctaves', 'filterMaxCorrectionDb', ...
                         'filterFrequencyRange', 'filterSampleRate'};
            for k = 1:numel(prefNames)
                obj.set_pref_(prefNames{k}, char(raw(k)));
            end
        end

        function value = parse_choice_(~, textValue, allowed, label)
            value = lower(strtrim(string(textValue)));
            if ~ismember(value, allowed)
                error('stimgen:calibration:CalibrationGui:badChoice', ...
                    '%s must be one of: %s.', label, strjoin(allowed, ', '));
            end
        end

        function value = parse_nonnegative_integer_(~, textValue, label)
            value = str2double(strtrim(string(textValue)));
            if isnan(value) || ~isfinite(value) || value < 0 || value ~= round(value)
                error('stimgen:calibration:CalibrationGui:badInteger', ...
                    '%s must be a non-negative integer.', label);
            end
        end

        function value = parse_nonnegative_scalar_(~, textValue, label, emptyValue, allowInf)
            raw = strtrim(string(textValue));
            if raw == ""
                value = emptyValue;
                return
            end
            value = str2double(raw);
            if isnan(value) || value < 0 || (~allowInf && ~isfinite(value))
                error('stimgen:calibration:CalibrationGui:badScalar', ...
                    '%s must be a non-negative number.', label);
            end
        end

        function value = parse_positive_integer_(~, textValue, label)
            raw = strtrim(string(textValue));
            value = str2double(raw);
            if isnan(value) || ~isfinite(value) || value <= 0 || value ~= round(value)
                error('stimgen:calibration:CalibrationGui:badInteger', ...
                    '%s must be a positive integer.', label);
            end
            value = round(value);
        end

        function value = get_pref_(~, prefName, defaultValue)
            groupName = 'StimCalibrationGui';
            if ispref(groupName, prefName)
                value = getpref(groupName, prefName);
            else
                value = defaultValue;
            end
            value = char(string(value));
        end

        function set_pref_(~, prefName, value)
            groupName = 'StimCalibrationGui';
            setpref(groupName, prefName, char(string(value)));
        end

        function restore_settings_prefs_(obj)
            % Reapply the settings the user last worked with, written by
            % save_settings_prefs_. Engine-side settings are restored per
            % field and only where the engine still holds its factory
            % default, so values arriving on a supplied engine win -- and
            % not at all when the engine is calibrated, since its settings
            % document the measurement. Display settings belong to this
            % window rather than the engine and are always restored.
            if ~obj.Engine.IsCalibrated
                obj.restore_engine_settings_();
            end
            obj.restore_display_settings_();

            % GUI-owned workflow toggle, not an engine setting: whether each
            % tone/click sweep is followed by the iterative refinement.
            stored = obj.get_pref_('iterativeCalibration', '');
            if any(strcmp(stored, {'0', '1'}))
                obj.IterativeCheck.Value = strcmp(stored, '1');
            end
        end

        function restore_engine_settings_(obj)
            % Preference keys are the Engine property names. Numeric values
            % are validated against the field each is headed for via
            % sync_controls_: a hand-edited preference outside its range
            % would otherwise throw there rather than here. Max Output and the
            % FFT length state their limits literally because their controls
            % live in the on-demand settings window and do not exist yet.
            factory = stimgen.calibration.Engine();
            numericPairs = {
                'ReferenceLevel',     obj.RefLevelField.Limits
                'ReferenceFrequency', obj.RefFreqField.Limits
                'MicSensitivity',     obj.MicSensField.Limits
                'NormativeValue',     obj.NormativeField.Limits
                'ExcitationVoltage',  obj.ExcitationField.Limits
                'MaxOutputVoltage',   [eps, 1000]
                'SpectralFftLength',  [0, 2^24]
                };

            opts = struct();
            for k = 1:size(numericPairs, 1)
                prop = numericPairs{k, 1};
                limits = numericPairs{k, 2};
                v = str2double(obj.get_pref_(prop, ''));
                if isfinite(v) && v >= limits(1) && v <= limits(2) && ...
                        obj.Engine.(prop) == factory.(prop)
                    opts.(prop) = v;
                end
            end

            for prop = ["AcCoupleResponse" "ShowLivePlots"]
                stored = obj.get_pref_(char(prop), '');
                if any(strcmp(stored, {'0', '1'})) && ...
                        obj.Engine.(prop) == factory.(prop)
                    opts.(prop) = strcmp(stored, '1');
                end
            end

            stored = obj.get_pref_('ToneLutSource', '');
            if any(strcmp(stored, {'tone', 'swept_sine'})) && ...
                    obj.Engine.ToneLutSource == factory.ToneLutSource
                opts.ToneLutSource = string(stored);
            end

            stored = string(obj.get_pref_('SpectralWindow', ''));
            if ismember(stored, stimgen.calibration.SpectralOptions.WindowList) && ...
                    obj.Engine.SpectralWindow == factory.SpectralWindow
                opts.SpectralWindow = stored;
            end

            if isempty(fieldnames(opts))
                return
            end
            args = namedargs2cell(opts);
            try
                obj.Engine.set_configuration(args{:});
            catch ME
                % A stale preference must never block the window opening.
                stimgen.util.vprintf(-1, ME);
            end
        end

        function restore_display_settings_(obj)
            stored = obj.get_pref_('transferLogX', '');
            if any(strcmp(stored, {'0', '1'}))
                obj.Monitor.LogX = strcmp(stored, '1');
            end

            stored = obj.get_pref_('spectrumGhost', '');
            if any(strcmp(stored, {'0', '1'}))
                obj.Monitor.ShowGhost = strcmp(stored, '1');
            end

            stored = obj.get_pref_('transferVoltage', '');
            if any(strcmp(stored, {'0', '1'}))
                obj.Monitor.ShowVoltage = strcmp(stored, '1');
            end

            units = string(obj.get_pref_('spectrumUnits', ''));
            if ismember(units, stimgen.calibration.LiveMonitor.SpectrumUnitList)
                obj.Monitor.SpectrumUnits = units;
                obj.sync_spectrum_units_menu_();
            end

            types = stimgen.calibration.LiveMonitor.WeightingTypes;
            sel = split(string(obj.get_pref_('weightingOverlays', '')), ',');
            checked = ismember(types, sel);
            if any(checked)
                for k = 1:numel(types)
                    obj.WeightingMenus(k).Checked = ...
                        matlab.lang.OnOffSwitchState(checked(k));
                end
                obj.Monitor.Weightings = types(checked);
            end

            % Everything above writes the monitor; this is what makes the
            % controls that mirror it agree with what was restored.
            obj.sync_display_controls_();
        end

        function save_settings_prefs_(obj)
            % Snapshot every remembered setting: the controls-column values
            % and the View menu's display state. Read from the controls
            % rather than the engine -- the controls hold what the user
            % last set, applied to an engine or not. The two hardware
            % settings are the exception: their window pushes every change
            % to the engine immediately and may be closed by now, so the
            % engine is where what the user last set lives. Never throws:
            % this runs on the window's close path.
            try
                obj.set_pref_('ReferenceLevel',     sprintf('%.15g', obj.RefLevelField.Value));
                obj.set_pref_('ReferenceFrequency', sprintf('%.15g', obj.RefFreqField.Value));
                obj.set_pref_('MicSensitivity',     sprintf('%.15g', obj.MicSensField.Value));
                obj.set_pref_('NormativeValue',     sprintf('%.15g', obj.NormativeField.Value));
                obj.set_pref_('ExcitationVoltage',  sprintf('%.15g', obj.ExcitationField.Value));
                obj.set_pref_('MaxOutputVoltage',   sprintf('%.15g', obj.Engine.MaxOutputVoltage));
                obj.set_pref_('AcCoupleResponse',   sprintf('%d', obj.Engine.AcCoupleResponse));
                obj.set_pref_('SpectralWindow',     char(obj.Engine.SpectralWindow));
                obj.set_pref_('SpectralFftLength',  sprintf('%d', obj.Engine.SpectralFftLength));
                obj.set_pref_('ShowLivePlots',      sprintf('%d', obj.ShowLivePlotsCheck.Value));
                obj.set_pref_('iterativeCalibration', sprintf('%d', obj.IterativeCheck.Value));
                if obj.ToneSweptSineCheck.Value
                    obj.set_pref_('ToneLutSource', 'swept_sine');
                else
                    obj.set_pref_('ToneLutSource', 'tone');
                end

                obj.set_pref_('transferLogX',    sprintf('%d', obj.Monitor.LogX));
                obj.set_pref_('spectrumGhost',   sprintf('%d', obj.Monitor.ShowGhost));
                obj.set_pref_('transferVoltage', sprintf('%d', obj.Monitor.ShowVoltage));
                obj.set_pref_('spectrumUnits', char(obj.Monitor.SpectrumUnits));
                types = stimgen.calibration.LiveMonitor.WeightingTypes;
                sel = types(arrayfun(@(h) strcmp(h.Checked, 'on'), obj.WeightingMenus));
                if isempty(sel)
                    obj.set_pref_('weightingOverlays', '');
                else
                    obj.set_pref_('weightingOverlays', char(strjoin(sel, ',')));
                end
            catch ME
                stimgen.util.vprintf(-1, ME);
            end
        end

        function on_stop_(obj)
            % Request cancellation of the running calibration. Takes effect at
            % the next measurement boundary, not immediately.
            obj.Engine.cancel();
            obj.set_status_('Stopping...', false);
            obj.BtnStop.Enable = 'off';
        end

        function on_reset_calibration_(obj)
            % Discard acquired calibration data and start over. The engine's
            % adapter, its persistent parameters (including mic sensitivity
            % from Measure Reference), and this window's preferences are left
            % untouched -- only CalibrationData, the last response record, and
            % the calibration timestamp are cleared.
            if obj.Engine.IsCalibrated
                msg = ['Discard all acquired tone/click/swept-sine calibration ' ...
                    'data and any designed filter?' newline newline ...
                    'The attached adapter, loaded protocol, mic sensitivity, ' ...
                    'and other settings are kept.'];
                choice = uiconfirm(obj.Figure, msg, 'Reset Calibration', ...
                    Options={'Reset', 'Cancel'}, DefaultOption=2, CancelOption=2, ...
                    Icon='warning');
                if ~strcmp(choice, 'Reset')
                    obj.set_status_('Reset cancelled.', false);
                    return
                end
            end

            obj.Engine.reset_calibration();
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.set_status_('Calibration reset. Ready to measure again.', false);
        end

        function set_busy_(obj, tf, cancellable)
            % Disable calibration actions while an operation is running.
            % Stop is only enabled for operations that actually poll cancel().
            if tf
                obj.BtnReference.Enable = 'off';
                obj.BtnBackground.Enable = 'off';
                obj.BtnTones.Enable = 'off';
                obj.BtnClicks.Enable = 'off';
                obj.BtnSweptSine.Enable = 'off';
                obj.BtnTestTones.Enable = 'off';
                obj.BtnTestClicks.Enable = 'off';
                obj.BtnFilter.Enable = 'off';
                obj.BtnTestFilter.Enable = 'off';
                obj.BtnCopyFilter.Enable = 'off';
                obj.BtnReset.Enable = 'off';
                if cancellable
                    obj.BtnStop.Enable = 'on';
                else
                    obj.BtnStop.Enable = 'off';
                end
            else
                obj.BtnStop.Enable = 'off';
                obj.BtnReset.Enable = 'on';
            end
        end

        function with_busy_state_(obj, fcn, busyMessage, cancellable)
            arguments
                obj
                fcn
                busyMessage
                cancellable (1,1) logical = false
            end
            obj.set_status_(busyMessage, false);
            obj.Figure.Pointer = 'watch';
            obj.set_busy_(true, cancellable);
            drawnow;
            try
                fcn();
            catch ME
                if isequal(ME.identifier, 'stimgen:calibration:Engine:cancelled')
                    obj.set_status_('Calibration cancelled.', false);
                else
                    obj.set_status_(ME.message, true);
                    uialert(obj.Figure, ME.message, 'Calibration Error', Icon='error');
                end
            end
            obj.Figure.Pointer = 'arrow';
            obj.set_busy_(false, false);
            obj.update_runtime_state_();
            drawnow;
        end

        function set_status_(obj, msg, isError)
            if isError
                obj.StatusLabel.FontColor = [0.7 0 0];
            else
                obj.StatusLabel.FontColor = [0 0 0];
            end
            obj.StatusLabel.Text = msg;
            % A result line -- a test verdict, a background summary -- is
            % routinely wider than the controls column, and the label clips it.
            % The tooltip is where the rest of it stays reachable.
            obj.StatusLabel.Tooltip = msg;
        end
    end
end

% -------------------------------------------------------------------------
% Row builders for the controls column. One call per row keeps a section's
% code the same shape as the section on screen, and puts the tooltip on the
% caption as well as the widget so the whole row is a hover target.

function fld = numeric_row_(g, row, labelText, limits, format, tip)
% fld = numeric_row_(g, row, labelText, limits, format)
% fld = numeric_row_(g, row, labelText, limits, format, tip)
% Right-aligned caption and a numeric edit field.
arguments
    g
    row (1,1) double
    labelText (1,:) char
    limits (1,2) double
    format (1,:) char
    tip (1,:) char = ''
end
lbl = uilabel(g, Text=labelText, HorizontalAlignment='right');
lbl.Layout.Row = row;
lbl.Layout.Column = 1;

fld = uieditfield(g, 'numeric');
fld.Layout.Row = row;
fld.Layout.Column = 2;
fld.Limits = limits;
fld.ValueDisplayFormat = format;

if ~isempty(tip)
    lbl.Tooltip = tip;
    fld.Tooltip = tip;
end
end

% -------------------------------------------------------------------------
function set_checked_(h, tf)
% Check state of a menu item that may not have been built yet. Guarded rather
% than ordered, so sync_display_controls_ can run at any point in the build.
if ~isempty(h) && all(isgraphics(h))
    h.Checked = matlab.lang.OnOffSwitchState(tf);
end
end

% -------------------------------------------------------------------------
function set_tool_state_(h, tf)
% Pressed state of a toolbar toggle tool. Same guard, same reason.
if ~isempty(h) && all(isgraphics(h))
    h.State = matlab.lang.OnOffSwitchState(tf);
end
end

% -------------------------------------------------------------------------
function set_enabled_(h, tf)
% Enable state of a menu item or toolbar tool. Same guard, same reason.
if ~isempty(h) && all(isgraphics(h))
    h.Enable = matlab.lang.OnOffSwitchState(tf);
end
end

% -------------------------------------------------------------------------
function chk = check_row_(g, row, labelText, tip, callback)
% chk = check_row_(g, row, labelText)
% chk = check_row_(g, row, labelText, tip)
% chk = check_row_(g, row, labelText, tip, callback)
% Right-aligned caption and an unlabelled checkbox, so a toggle lines up with
% the fields above it instead of starting its own column.
arguments
    g
    row (1,1) double
    labelText (1,:) char
    tip (1,:) char = ''
    callback = []
end
lbl = uilabel(g, Text=labelText, HorizontalAlignment='right');
lbl.Layout.Row = row;
lbl.Layout.Column = 1;

chk = uicheckbox(g, Text='');
chk.Layout.Row = row;
chk.Layout.Column = 2;

if ~isempty(callback)
    chk.ValueChangedFcn = callback;
end
if ~isempty(tip)
    lbl.Tooltip = tip;
    chk.Tooltip = tip;
end
end

% -------------------------------------------------------------------------
function dd = dropdown_row_(g, row, labelText, itemLabels, itemValues, tip)
% dd = dropdown_row_(g, row, labelText, itemLabels, itemValues)
% dd = dropdown_row_(g, row, labelText, itemLabels, itemValues, tip)
% Right-aligned caption and a dropdown whose ItemsData carries the value a
% caller acts on, so the list can read in prose while Value stays the name or
% number the engine takes.
arguments
    g
    row (1,1) double
    labelText (1,:) char
    itemLabels (1,:) string
    itemValues
    tip (1,:) char = ''
end
lbl = uilabel(g, Text=labelText, HorizontalAlignment='right');
lbl.Layout.Row = row;
lbl.Layout.Column = 1;

dd = uidropdown(g, Items=cellstr(itemLabels), ItemsData=itemValues);
dd.Layout.Row = row;
dd.Layout.Column = 2;

if ~isempty(tip)
    lbl.Tooltip = tip;
    dd.Tooltip = tip;
end
end

% -------------------------------------------------------------------------
function set_dropdown_value_(dd, value, labelFcn)
% set_dropdown_value_(dd, value, labelFcn)
% Select value in a dropdown, appending it to the list first when it is not
% already offered. A saved file or a scripted engine may hold a setting the
% GUI's list never included; snapping to the nearest offered value would edit
% the engine behind the user's back just for opening a window.
if ~isempty(dd.ItemsData) && any(dd.ItemsData == value)
    dd.Value = value;
    return
end
dd.Items = [dd.Items, {char(labelFcn(value))}];
dd.ItemsData = [dd.ItemsData, value];
dd.Value = value;
end

% -------------------------------------------------------------------------
function lbl = heading_row_(g, row, titleText)
% lbl = heading_row_(g, row, titleText)
% Bold full-width heading that groups the rows beneath it. Used where a
% settings window carries two kinds of setting that happen to share a
% consequence but not a reason.
lbl = uilabel(g, Text=titleText, FontWeight='bold');
lbl.Layout.Row = row;
lbl.Layout.Column = [1 2];
end

% -------------------------------------------------------------------------
function val = readout_row_(g, row, labelText, initialText, tip)
% val = readout_row_(g, row, labelText, initialText, tip)
% Right-aligned caption and a left-aligned label the GUI writes into. A label
% rather than a disabled field: nothing here is editable, and greyed-out text
% would be harder to read than the value deserves.
arguments
    g
    row (1,1) double
    labelText (1,:) char
    initialText (1,:) char
    tip (1,:) char = ''
end
lbl = uilabel(g, Text=labelText, HorizontalAlignment='right');
lbl.Layout.Row = row;
lbl.Layout.Column = 1;

val = uilabel(g, Text=initialText, HorizontalAlignment='left');
val.Layout.Row = row;
val.Layout.Column = 2;

if ~isempty(tip)
    lbl.Tooltip = tip;
    val.Tooltip = tip;
end
end

% -------------------------------------------------------------------------
function btn = action_button_(g, row, columns, labelText, tooltipKey, callback)
% btn = action_button_(g, row, columns, labelText, tooltipKey, callback)
% Action button spanning the given column(s). Every button in this window has
% an entry in the CalibrationGui tooltip section, so the key is looked up here
% rather than passed as text.
btn = uibutton(g, Text=labelText, ButtonPushedFcn=callback);
btn.Layout.Row = row;
btn.Layout.Column = columns;
btn.Tooltip = stimgen.util.tooltip('CalibrationGui', tooltipKey);
end

% -------------------------------------------------------------------------
function s = spectrum_unit_menu_text_(unit)
% s = spectrum_unit_menu_text_(unit)
% Menu caption for a LiveMonitor spectrum unit: what the unit is for, with the
% unit itself in parentheses. The list of units belongs to the monitor; only
% the wording of it belongs here, and an unlisted unit still gets an item
% rather than an error.

switch unit
    case "dB SPL",      s = 'Sound Pressure Level (dB SPL)';
    case "dB SPL/Hz",   s = 'Spectral Density (dB SPL/Hz)';
    case "Pa",          s = 'Sound Pressure (Pa rms)';
    case "V",           s = 'Measured Voltage (V rms)';
    case "dBV",         s = 'Measured Voltage (dB re 1 V)';
    case "V/sqrt(Hz)",  s = 'Voltage Density (V/sqrt(Hz))';
    case "dB re peak",  s = 'Relative to Peak (dB)';
    otherwise,          s = char(unit);
end
end

% -------------------------------------------------------------------------
function [eng, host] = parse_construction_args_(args)
% [eng, host] = parse_construction_args_(args)
% Resolve the constructor inputs by type so an Engine and a HardwareHost can
% be supplied in any order, alone, or as Engine=/Host= pairs. A missing engine
% becomes a fresh offline Engine; a missing host leaves the runtime menu
% actions disabled.

eng  = stimgen.calibration.Engine.empty;
host = [];

k = 1;
while k <= numel(args)
    a = args{k};
    if isa(a, 'stimgen.calibration.Engine')
        eng = a;
        k = k + 1;
    elseif isa(a, 'stimgen.HardwareHost')
        host = a;
        k = k + 1;
    elseif isempty(a) && ~ischar(a) && ~isstring(a)
        % Tolerate [] placeholders forwarded by callers with an optional host.
        k = k + 1;
    elseif (ischar(a) || (isstring(a) && isscalar(a))) && k < numel(args)
        value = args{k+1};
        switch lower(string(a))
            case "engine"
                mustBeA(value, 'stimgen.calibration.Engine');
                eng = value;
            case "host"
                if ~isempty(value)
                    mustBeA(value, 'stimgen.HardwareHost');
                end
                host = value;
            otherwise
                error('stimgen:calibration:CalibrationGui:invalidArgument', ...
                    'Unrecognized option "%s". Valid options are Engine and Host.', a);
        end
        k = k + 2;
    else
        error('stimgen:calibration:CalibrationGui:invalidArgument', ...
            ['Unrecognized argument of class "%s". Expected a ' ...
            'stimgen.calibration.Engine, a stimgen.HardwareHost, or ' ...
            'Engine=/Host= pairs.'], class(a));
    end
end

if isempty(eng)
    eng = stimgen.calibration.Engine();
end
eng = eng(1);
end

% -------------------------------------------------------------------------
function s = background_summary_(r)
% s = background_summary_(r)
% One-line status-bar summary of a background capture.
s = sprintf('Background: %.1f dB SPL (%.1f dB(A)), loudest band %.0f Hz at %.1f dB SPL.', ...
    r.spl_db, r.spl_dba, r.worst_band.frequency, r.worst_band.level_db);
if ~isempty(r.flags)
    s = sprintf('%s %d finding(s) -- see the report.', s, numel(r.flags));
end
end

% -------------------------------------------------------------------------
function s = background_report_(r)
% s = background_report_(r)
% Full text of a background capture, for the dialog shown after a run.
%
% The plots carry the shape of the noise; this carries the numbers that are
% awkward to read off a curve -- the broadband levels, the quietest and
% loudest bands, the tonal components and what they line up with, and whatever
% the analysis flagged as worth acting on.
lines = {};
lines{end+1} = sprintf('%g s x %d record(s) at %g Hz, %s', ...
    round(r.duration_s, 2), r.repeat_count, r.fs, ...
    char(datetime(r.measuredOn, Format='dd-MMM-yyyy HH:mm')));
lines{end+1} = '';
lines{end+1} = sprintf('Broadband        %.1f dB SPL   |   A-weighted  %.1f dB(A)', ...
    r.spl_db, r.spl_dba);
lines{end+1} = sprintf('Below normative  %.1f dB (normative %g dB SPL)', ...
    r.headroom_to_normative_db, r.normative_value_db);

if r.repeat_count > 1
    lines{end+1} = sprintf('Across records   %.1f dB spread, SD %.2f dB (%s)', ...
        r.range_db, r.sd_db, steadiness_(r.stable));
end
lines{end+1} = sprintf('Input            peak %.4f V, %.1f dB below full scale, crest %.0f dB', ...
    r.peak_v, r.headroom_db, r.crest_factor_db);

lines{end+1} = '';
lines{end+1} = sprintf('1/%d-octave bands (%d):', r.bands.fraction, numel(r.bands.frequency));
if isempty(r.bands.frequency)
    lines{end+1} = '  none resolvable at this duration and sample rate';
else
    [~, iHi] = max(r.bands.level_db);
    [~, iLo] = min(r.bands.level_db);
    lines{end+1} = sprintf('  loudest   %6.0f Hz   %.1f dB SPL', ...
        r.bands.frequency(iHi), r.bands.level_db(iHi));
    lines{end+1} = sprintf('  quietest  %6.0f Hz   %.1f dB SPL', ...
        r.bands.frequency(iLo), r.bands.level_db(iLo));
    lines{end+1} = sprintf('  span      %6.0f-%.0f Hz', ...
        r.bands.frequency(1), r.bands.frequency(end));
end

lines{end+1} = '';
if isempty(r.peaks.frequency)
    lines{end+1} = sprintf('Tonal components: none more than %g dB above the local floor.', ...
        r.tonal_prominence_db);
else
    lines{end+1} = sprintf('Tonal components (>= %g dB above the local floor):', ...
        r.tonal_prominence_db);
    for k = 1:numel(r.peaks.frequency)
        lines{end+1} = sprintf('  %7.1f Hz   %.1f dB SPL   (+%.0f dB)', ...
            r.peaks.frequency(k), r.peaks.level_db(k), r.peaks.prominence_db(k));
    end
    if isfinite(r.mains.frequency)
        lines{end+1} = sprintf('  %d of these are %g Hz mains harmonics, %.1f dB SPL combined.', ...
            r.mains.n_harmonics, r.mains.frequency, r.mains.level_db);
    end
end

if ~isempty(r.flags)
    lines{end+1} = '';
    lines{end+1} = 'Findings:';
    for k = 1:numel(r.flags)
        lines{end+1} = sprintf('  - %s', r.flags(k));
    end
end

s = strjoin(string(lines), newline);
end

% -------------------------------------------------------------------------
function s = steadiness_(tf)
if tf
    s = 'steady';
else
    s = 'not steady';
end
end
