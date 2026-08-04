classdef CalibrationGui < handle
    % gui = stimgen.calibration.CalibrationGui()
    % gui = stimgen.calibration.CalibrationGui(host)
    % gui = stimgen.calibration.CalibrationGui(eng)
    % Interactive GUI for the stimgen.calibration package.
    %
    % Provides user parameterization of calibration settings, live inspection of
    % the latest response waveform/spectrum, transfer-curve visualization for
    % tone and click calibration tables, and save/load support for .esgc files.
    % When no engine is supplied, an offline Engine is created automatically;
    % hardware can be attached later via File > Initialize Runtime From Protocol.
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

    properties (SetAccess = private)
        Engine stimgen.calibration.Engine
    end

    properties (Access = private)
        Figure
        Grid
        Host                    % stimgen.HardwareHost | []

        % File menu
        RecentProtocolsMenu
        RecentCalibrationsMenu

        % Controls
        RefLevelField
        RefFreqField
        MicSensField
        NormativeField
        ExcitationField
        ShowLivePlotsCheck
        TransferLogXCheck
        SampleRateLabel
        StatusLabel

        % Buttons
        BtnReference
        BtnTones
        BtnClicks
        BtnSweptSine
        BtnFilter
        BtnStop

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
                Position=[120 80 1320 760]);

            obj.Grid = uigridlayout(obj.Figure, [1 2]);
            obj.Grid.ColumnWidth = {360, '1x'};
            obj.Grid.RowHeight = {'1x'};

            obj.build_menu_();
            obj.build_toolbar_();
            obj.build_controls_panel_();
            obj.build_plots_panel_();
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

            helpMenu = uimenu(obj.Figure, Text='Help');
            uimenu(helpMenu, Text='Calibration Quick Start', ...
                MenuSelectedFcn=@(~,~) obj.on_show_quick_start_());
        end

        function build_controls_panel_(obj)
            panel = uipanel(obj.Grid, Title='Controls');
            panel.Layout.Row = 1;
            panel.Layout.Column = 1;

            g = uigridlayout(panel, [16 2]);
            g.RowHeight = {24, 24, 24, 24, 24, 24, 24, 24, 32, 32, 32, 32, 32, 32, 24, '1x'};
            g.ColumnWidth = {'1x', '1x'};
            g.Scrollable = 'on';

            refLevelLabel = uilabel(g, Text='Reference Level (dB SPL)', HorizontalAlignment='right');
            refLevelLabel.Layout.Row = 1;
            refLevelLabel.Layout.Column = 1;
            obj.RefLevelField = uieditfield(g, 'numeric');
            obj.RefLevelField.Layout.Row = 1;
            obj.RefLevelField.Layout.Column = 2;
            obj.RefLevelField.Limits = [1, 160];
            obj.RefLevelField.ValueDisplayFormat = '%.1f';

            refFreqLabel = uilabel(g, Text='Reference Frequency (Hz)', HorizontalAlignment='right');
            refFreqLabel.Layout.Row = 2;
            refFreqLabel.Layout.Column = 1;
            obj.RefFreqField = uieditfield(g, 'numeric');
            obj.RefFreqField.Layout.Row = 2;
            obj.RefFreqField.Layout.Column = 2;
            obj.RefFreqField.Limits = [20, 200000];
            obj.RefFreqField.ValueDisplayFormat = '%.1f';

            micSensLabel = uilabel(g, Text='Mic Sensitivity (V/Pa)', HorizontalAlignment='right');
            micSensLabel.Layout.Row = 3;
            micSensLabel.Layout.Column = 1;
            obj.MicSensField = uieditfield(g, 'numeric');
            obj.MicSensField.Layout.Row = 3;
            obj.MicSensField.Layout.Column = 2;
            obj.MicSensField.Limits = [eps, 100];
            obj.MicSensField.ValueDisplayFormat = '%.5f';

            normativeLabel = uilabel(g, Text='Normative Value (dB SPL)', HorizontalAlignment='right');
            normativeLabel.Layout.Row = 4;
            normativeLabel.Layout.Column = 1;
            obj.NormativeField = uieditfield(g, 'numeric');
            obj.NormativeField.Layout.Row = 4;
            obj.NormativeField.Layout.Column = 2;
            obj.NormativeField.Limits = [1, 180];
            obj.NormativeField.ValueDisplayFormat = '%.1f';

            excitationLabel = uilabel(g, Text='Excitation Voltage (V)', HorizontalAlignment='right');
            excitationLabel.Layout.Row = 5;
            excitationLabel.Layout.Column = 1;
            obj.ExcitationField = uieditfield(g, 'numeric');
            obj.ExcitationField.Layout.Row = 5;
            obj.ExcitationField.Layout.Column = 2;
            obj.ExcitationField.Limits = [eps, 10];
            obj.ExcitationField.ValueDisplayFormat = '%.3f';

            sampleRateLabelCaption = uilabel(g, Text='Hardware Sample Rate', HorizontalAlignment='right');
            sampleRateLabelCaption.Layout.Row = 6;
            sampleRateLabelCaption.Layout.Column = 1;
            obj.SampleRateLabel = uilabel(g, Text='No adapter', HorizontalAlignment='left');
            obj.SampleRateLabel.Layout.Row = 6;
            obj.SampleRateLabel.Layout.Column = 2;

            showPlotsLabel = uilabel(g, Text='Show Engine Live Plots', HorizontalAlignment='right');
            showPlotsLabel.Layout.Row = 7;
            showPlotsLabel.Layout.Column = 1;
            obj.ShowLivePlotsCheck = uicheckbox(g, Text='');
            obj.ShowLivePlotsCheck.Layout.Row = 7;
            obj.ShowLivePlotsCheck.Layout.Column = 2;

            transferLogXLabel = uilabel(g, Text='Transfer Plot Log X-Axis', HorizontalAlignment='right');
            transferLogXLabel.Layout.Row = 8;
            transferLogXLabel.Layout.Column = 1;
            obj.TransferLogXCheck = uicheckbox(g, Text='', Value=true, ...
                ValueChangedFcn=@(~,~) obj.refresh_transfer_plot_());
            obj.TransferLogXCheck.Layout.Row = 8;
            obj.TransferLogXCheck.Layout.Column = 2;

            obj.BtnReference = uibutton(g, Text='Measure Reference', ...
                ButtonPushedFcn=@(~,~) obj.on_measure_reference_());
            obj.BtnReference.Layout.Row = 9;
            obj.BtnReference.Layout.Column = [1 2];
            obj.BtnReference.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnReference');

            obj.BtnTones = uibutton(g, Text='Calibrate Tones', ...
                ButtonPushedFcn=@(~,~) obj.on_calibrate_tones_());
            obj.BtnTones.Layout.Row = 10;
            obj.BtnTones.Layout.Column = [1 2];
            obj.BtnTones.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnTones');

            obj.BtnClicks = uibutton(g, Text='Calibrate Clicks', ...
                ButtonPushedFcn=@(~,~) obj.on_calibrate_clicks_());
            obj.BtnClicks.Layout.Row = 11;
            obj.BtnClicks.Layout.Column = [1 2];
            obj.BtnClicks.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnClicks');

            obj.BtnSweptSine = uibutton(g, Text='Calibrate Swept Sine', ...
                ButtonPushedFcn=@(~,~) obj.on_calibrate_swept_sine_());
            obj.BtnSweptSine.Layout.Row = 12;
            obj.BtnSweptSine.Layout.Column = [1 2];
            obj.BtnSweptSine.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnSweptSine');

            obj.BtnFilter = uibutton(g, Text='Design Filter', ...
                ButtonPushedFcn=@(~,~) obj.on_design_filter_());
            obj.BtnFilter.Layout.Row = 13;
            obj.BtnFilter.Layout.Column = [1 2];
            obj.BtnFilter.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnFilter');

            obj.BtnStop = uibutton(g, Text='Stop', ...
                BackgroundColor=[0.7 0.15 0.15], FontColor=[1 1 1], ...
                Enable='off', ...
                ButtonPushedFcn=@(~,~) obj.on_stop_());
            obj.BtnStop.Layout.Row = 14;
            obj.BtnStop.Layout.Column = [1 2];
            obj.BtnStop.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnStop');

            obj.StatusLabel = uilabel(g, Text='Ready.', HorizontalAlignment='left');
            obj.StatusLabel.Layout.Row = 15;
            obj.StatusLabel.Layout.Column = [1 2];
        end

        function build_plots_panel_(obj)
            panel = uipanel(obj.Grid, Title='Visualization');
            panel.Layout.Row = 1;
            panel.Layout.Column = 2;

            g = uigridlayout(panel, [2 2]);
            g.RowHeight = {'1x', '1x'};
            g.ColumnWidth = {'1x', '1x'};

            obj.AxTime = uiaxes(g);
            obj.AxTime.Layout.Row = 1;
            obj.AxTime.Layout.Column = 1;
            title(obj.AxTime, 'Temporal Response');
            xlabel(obj.AxTime, 'Time (ms)');
            ylabel(obj.AxTime, 'V');
            grid(obj.AxTime, 'on');

            obj.AxSpectrum = uiaxes(g);
            obj.AxSpectrum.Layout.Row = 1;
            obj.AxSpectrum.Layout.Column = 2;
            title(obj.AxSpectrum, 'Spectral Response');
            xlabel(obj.AxSpectrum, 'Frequency (Hz)');
            ylabel(obj.AxSpectrum, 'Power/Frequency');
            set(obj.AxSpectrum, 'XScale', 'log', 'YScale', 'log');
            grid(obj.AxSpectrum, 'on');

            obj.AxTransfer = uiaxes(g);
            obj.AxTransfer.Layout.Row = 2;
            obj.AxTransfer.Layout.Column = [1 2];
            title(obj.AxTransfer, 'Calibration Transfer Curves');
            xlabel(obj.AxTransfer, 'Parameter');
            ylabel(obj.AxTransfer, 'dB SPL');
            grid(obj.AxTransfer, 'on');
        end

        function on_measure_reference_(obj)
            if ~obj.apply_controls_to_engine_()
                return
            end
            obj.with_busy_state_(@() obj.run_measure_reference_(), 'Measuring reference...');
        end

        function run_measure_reference_(obj)
            obj.Engine.calibrate_reference();
            obj.sync_controls_();
            obj.refresh_response_plots_();
            obj.set_status_('Reference measurement complete.', false);
        end

        function on_calibrate_tones_(obj)
            if ~obj.apply_controls_to_engine_()
                return
            end
            obj.with_busy_state_(@() obj.run_calibrate_tones_(), 'Running tone calibration...', true);
        end

        function run_calibrate_tones_(obj)
            [freqs, repeatCount, wasCancelled] = obj.prompt_vector_parameter_( ...
                'toneFreqs', ...
                'toneRepeats', ...
                'Tone frequencies (Hz), e.g. 500:250:32000 or 500.*2.^(0:.5:5). Leave empty to use default log sweep.', ...
                'Tone Calibration', ...
                '', ...
                1);
            if wasCancelled
                obj.set_status_('Tone calibration cancelled.', false);
                return
            end
            if isempty(freqs)
                obj.Engine.calibrate_tones([], repeatCount);
            else
                obj.Engine.calibrate_tones(freqs, repeatCount);
            end
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.set_status_('Tone calibration complete.', false);
        end

        function on_calibrate_clicks_(obj)
            if ~obj.apply_controls_to_engine_()
                return
            end
            obj.with_busy_state_(@() obj.run_calibrate_clicks_(), 'Running click calibration...', true);
        end

        function run_calibrate_clicks_(obj)
            [durs, repeatCount, wasCancelled] = obj.prompt_vector_parameter_( ...
                'clickDurationsMs', ...
                'clickRepeats', ...
                'Click durations (ms). Leave empty to use default 1..128 samples.', ...
                'Click Calibration', ...
                '', ...
                1);
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
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.set_status_('Click calibration complete.', false);
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
            obj.set_status_(sprintf( ...
                'Equalization filter designed: %d taps, %.1f dB correction span.', ...
                D.numCoefficients, D.correctionDb), false);
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
            % Show a concise calibration workflow for first-time users.
            msg = sprintf([ ...
                'Calibration Quick Start\n\n', ...
                '1) File > Initialize Runtime From Protocol..., then File > Attach Adapter (if needed).\n\n', ...
                '2) Verify parameters (reference level/frequency, mic sensitivity, excitation).\n\n', ...
                '3) Click "Measure Reference" to update microphone sensitivity.\n\n', ...
                '4) Click "Calibrate Tones" (required for tone lookup).\n\n', ...
                '5) Optional: run "Calibrate Clicks" and/or "Calibrate Swept Sine".\n\n', ...
                '6) Optional: click "Design Filter" (enabled after tone or swept sine calibration).\n\n', ...
                '7) Save calibration with File > Save .esgc.']);
            uialert(obj.Figure, msg, 'Calibration Quick Start', Icon='info');
        end

        function ok = apply_controls_to_engine_(obj)
            ok = false;
            try
                obj.Engine.set_configuration( ...
                    ReferenceLevel=obj.RefLevelField.Value, ...
                    ReferenceFrequency=obj.RefFreqField.Value, ...
                    MicSensitivity=obj.MicSensField.Value, ...
                    NormativeValue=obj.NormativeField.Value, ...
                    ExcitationVoltage=obj.ExcitationField.Value, ...
                    ShowLivePlots=obj.ShowLivePlotsCheck.Value);
                ok = true;
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
        end

        function refresh_all_plots_(obj)
            obj.refresh_response_plots_();
            obj.refresh_transfer_plot_();
        end

        function refresh_response_plots_(obj)
            cla(obj.AxTime);
            cla(obj.AxSpectrum);

            y = obj.Engine.ResponseSignal;
            fs = obj.Engine.Fs;
            if isempty(y) || fs <= 0
                title(obj.AxTime, 'Temporal Response (no data)');
                title(obj.AxSpectrum, 'Spectral Response (no data)');
                return
            end

            t = (0:numel(y)-1) ./ fs .* 1e3; % ms
            plot(obj.AxTime, t, y, 'b-');
            grid(obj.AxTime, 'on');
            xlabel(obj.AxTime, 'Time (ms)');
            ylabel(obj.AxTime, 'V');
            title(obj.AxTime, sprintf('Temporal Response (N=%d)', numel(y)));

            n = numel(y);
            w = flattopwin(n);
            [pxx, f] = periodogram(y, w, 2^nextpow2(n), fs, 'power');
            pxx = max(pxx, eps);
            plot(obj.AxSpectrum, f, pxx, 'r-');
            set(obj.AxSpectrum, 'XScale', 'log', 'YScale', 'log');
            grid(obj.AxSpectrum, 'on');
            xlabel(obj.AxSpectrum, 'Frequency (Hz)');
            ylabel(obj.AxSpectrum, 'Power/Frequency');
            title(obj.AxSpectrum, 'Spectral Response (periodogram)');
        end

        function refresh_transfer_plot_(obj)
            cla(obj.AxTransfer);
            grid(obj.AxTransfer, 'on');
            hold(obj.AxTransfer, 'on');

            hasData = false;
            if obj.Engine.IsCalibrated
                C = obj.Engine.CalibrationData;

                if isfield(C, 'tone') && ~isempty(C.tone)
                    plot(obj.AxTransfer, C.tone.frequency, C.tone.spl_db, 'o-b', ...
                        DisplayName='Tone SPL');
                    hasData = true;
                end

                if isfield(C, 'click') && ~isempty(C.click)
                    plot(obj.AxTransfer, C.click.duration * 1e6, C.click.spl_db, 's-r', ...
                        DisplayName='Click SPL');
                    hasData = true;
                end

                if isfield(C, 'swept_sine') && ~isempty(C.swept_sine)
                    plot(obj.AxTransfer, C.swept_sine.frequency, C.swept_sine.spl_db, '^-g', ...
                        DisplayName='Swept Sine SPL');
                    hasData = true;
                end
            end

            if obj.TransferLogXCheck.Value
                obj.AxTransfer.XScale = 'log';
            else
                obj.AxTransfer.XScale = 'linear';
            end

            if hasData
                xlabel(obj.AxTransfer, 'Frequency (Hz) / Duration (\mus)');
                ylabel(obj.AxTransfer, 'Measured Level (dB SPL)');
                title(obj.AxTransfer, 'Calibration Transfer Curves');
                legend(obj.AxTransfer, 'Location', 'best');
            else
                title(obj.AxTransfer, 'Calibration Transfer Curves (no data)');
                xlabel(obj.AxTransfer, 'Parameter');
                ylabel(obj.AxTransfer, 'dB SPL');
            end
            hold(obj.AxTransfer, 'off');
        end

        function update_runtime_state_(obj)
            obj.refresh_sample_rate_label_();

            hasAdapter = ~isempty(obj.Engine.Adapter);
            if hasAdapter
                obj.BtnReference.Enable = 'on';
                obj.BtnTones.Enable = 'on';
                obj.BtnClicks.Enable = 'on';
                obj.BtnSweptSine.Enable = 'on';
            else
                obj.BtnReference.Enable = 'off';
                obj.BtnTones.Enable = 'off';
                obj.BtnClicks.Enable = 'off';
                obj.BtnSweptSine.Enable = 'off';
            end

            % Either LUT can drive the equalizer; Engine.design_filter picks.
            C = obj.Engine.CalibrationData;
            hasLut = obj.Engine.IsCalibrated && ...
                ((isfield(C, 'tone') && ~isempty(C.tone)) || ...
                 (isfield(C, 'swept_sine') && ~isempty(C.swept_sine)));
            if hasLut
                obj.BtnFilter.Enable = 'on';
            else
                obj.BtnFilter.Enable = 'off';
            end
        end

        function refresh_sample_rate_label_(obj)
            fs = obj.Engine.Fs;
            if fs > 0
                obj.SampleRateLabel.Text = sprintf('%g Hz', fs);
            else
                obj.SampleRateLabel.Text = 'No adapter';
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
            values = [];
            if ischar(textValue)
                raw = string(textValue);
            elseif isstring(textValue)
                raw = strjoin(textValue, ' ');
            elseif iscell(textValue)
                raw = strjoin(string(textValue), ' ');
            else
                raw = "";
            end

            raw = strtrim(raw);
            if raw == "" || startsWith(raw, "(empty", IgnoreCase=true)
                return
            end

            vals = str2num(char(raw));
            if ~isnumeric(vals) || isempty(vals) || ~isreal(vals) || ~isvector(vals) || any(isnan(vals(:)))
                error('stimgen:calibration:CalibrationGui:badVector', ...
                    'Could not parse %s. Use comma/space separated numbers or a MATLAB expression (e.g. 500:250:32000).', label);
            end
            values = vals(:)';
            if any(values <= 0)
                error('stimgen:calibration:CalibrationGui:badVector', ...
                    '%s must contain only positive values.', label);
            end
        end

        function [values, repeatCount, wasCancelled] = prompt_vector_parameter_(obj, prefName, repeatPrefName, promptText, dlgTitle, defaultValue, repeatDefault)
            wasCancelled = false;
            stored = obj.get_pref_(prefName, defaultValue);
            repeatStored = obj.get_pref_(repeatPrefName, num2str(repeatDefault));

            prompts = {
                promptText, ...
                'Number of averages (positive integer):'
            };
            defaults = {stored, repeatStored};
            answer = inputdlg(prompts, dlgTitle, [1 90; 1 90], defaults);
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

        function [source, opts, wasCancelled] = prompt_filter_parameters_(obj)
            % Collect equalizer design options. Everything except the source is
            % returned as a name-value struct for Engine.design_filter, so the
            % dialog stays a thin front end to that argument list.
            source = "auto";
            opts = struct();
            wasCancelled = false;

            prompts = {
                'LUT source (auto | tone | swept_sine):', ...
                'Number of coefficients (taps; 0 = auto from LUT size):', ...
                'Design method (freqsamp | ls):', ...
                'Interpolation (pchip | linear | spline | makima):', ...
                'Frequency scale (log | linear):', ...
                'Fractional-octave smoothing (octaves, e.g. 0.333; 0 = none):', ...
                'Maximum correction depth (dB below peak; Inf = unlimited):', ...
                'Frequency range (Hz, "lo hi"; empty = LUT span):'
            };
            defaults = {
                obj.get_pref_('filterSource', 'auto'), ...
                obj.get_pref_('filterNumCoefficients', '0'), ...
                obj.get_pref_('filterDesignMethod', 'freqsamp'), ...
                obj.get_pref_('filterInterpolation', 'pchip'), ...
                obj.get_pref_('filterFrequencyScale', 'log'), ...
                obj.get_pref_('filterSmoothingOctaves', '0'), ...
                obj.get_pref_('filterMaxCorrectionDb', 'Inf'), ...
                obj.get_pref_('filterFrequencyRange', '')
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

            opts.DesignMethod     = designMethod;
            opts.Interpolation    = interpolation;
            opts.FrequencyScale   = frequencyScale;
            opts.SmoothingOctaves = smoothingOctaves;
            opts.MaxCorrectionDb  = maxCorrectionDb;
            opts.FrequencyRange   = freqRange;
            if nCoef > 0
                opts.NumCoefficients = nCoef;
            end

            prefNames = {'filterSource', 'filterNumCoefficients', 'filterDesignMethod', ...
                         'filterInterpolation', 'filterFrequencyScale', ...
                         'filterSmoothingOctaves', 'filterMaxCorrectionDb', ...
                         'filterFrequencyRange'};
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

        function on_stop_(obj)
            % Request cancellation of the running calibration. Takes effect at
            % the next measurement boundary, not immediately.
            obj.Engine.cancel();
            obj.set_status_('Stopping...', false);
            obj.BtnStop.Enable = 'off';
        end

        function set_busy_(obj, tf, cancellable)
            % Disable calibration actions while an operation is running.
            % Stop is only enabled for operations that actually poll cancel().
            if tf
                obj.BtnReference.Enable = 'off';
                obj.BtnTones.Enable = 'off';
                obj.BtnClicks.Enable = 'off';
                obj.BtnSweptSine.Enable = 'off';
                obj.BtnFilter.Enable = 'off';
                if cancellable
                    obj.BtnStop.Enable = 'on';
                else
                    obj.BtnStop.Enable = 'off';
                end
            else
                obj.BtnStop.Enable = 'off';
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
        end
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
