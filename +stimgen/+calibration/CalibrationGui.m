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
    % All drawing is done by a stimgen.calibration.LiveMonitor attached to this
    % window's axes: during a run it renders the engine's LiveUpdate stream
    % (gated by the Show Engine Live Plots checkbox), and between runs the same
    % renderer draws the committed calibration and the last response.
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
        BackgroundViewMenu

        % Controls
        RefLevelField
        RefFreqField
        MicSensField
        NormativeField
        ExcitationField
        MaxOutputField
        ShowLivePlotsCheck
        TransferLogXCheck
        ToneSweptSineCheck
        SampleRateLabel
        StatusLabel

        % Buttons
        BtnReference
        BtnBackground
        BtnTones
        BtnClicks
        BtnSweptSine
        BtnTestTones
        BtnFilter
        BtnTestFilter
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
                Position=[120 80 1320 760], ...
                CloseRequestFcn=@(src,~) obj.on_close_(src));

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

            % The transfer panel serves one view at a time; this is how a user
            % gets back to the other one without re-running anything.
            viewMenu = uimenu(obj.Figure, Text='View');
            uimenu(viewMenu, Text='Calibration Transfer Curves', ...
                MenuSelectedFcn=@(~,~) obj.on_show_transfer_());
            obj.BackgroundViewMenu = uimenu(viewMenu, Text='Background Noise Analysis', ...
                Enable='off', ...
                MenuSelectedFcn=@(~,~) obj.on_show_background_());

            helpMenu = uimenu(obj.Figure, Text='Help');
            uimenu(helpMenu, Text='Calibration Quick Start', ...
                MenuSelectedFcn=@(~,~) obj.on_show_quick_start_());
        end

        function build_controls_panel_(obj)
            panel = uipanel(obj.Grid, Title='Controls');
            panel.Layout.Row = 1;
            panel.Layout.Column = 1;

            g = uigridlayout(panel, [22 2]);
            g.RowHeight = {24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 24, '1x'};
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

            maxOutputLabel = uilabel(g, Text='Max Output Voltage (V)', HorizontalAlignment='right');
            maxOutputLabel.Layout.Row = 6;
            maxOutputLabel.Layout.Column = 1;
            obj.MaxOutputField = uieditfield(g, 'numeric');
            obj.MaxOutputField.Layout.Row = 6;
            obj.MaxOutputField.Layout.Column = 2;
            obj.MaxOutputField.Limits = [eps, 1000];
            obj.MaxOutputField.ValueDisplayFormat = '%.1f';
            obj.MaxOutputField.Tooltip = stimgen.util.tooltip('CalibrationGui', 'MaxOutputVoltage');

            sampleRateLabelCaption = uilabel(g, Text='Hardware Sample Rate', HorizontalAlignment='right');
            sampleRateLabelCaption.Layout.Row = 7;
            sampleRateLabelCaption.Layout.Column = 1;
            obj.SampleRateLabel = uilabel(g, Text='No adapter', HorizontalAlignment='left');
            obj.SampleRateLabel.Layout.Row = 7;
            obj.SampleRateLabel.Layout.Column = 2;

            showPlotsLabel = uilabel(g, Text='Show Engine Live Plots', HorizontalAlignment='right');
            showPlotsLabel.Layout.Row = 8;
            showPlotsLabel.Layout.Column = 1;
            obj.ShowLivePlotsCheck = uicheckbox(g, Text='');
            obj.ShowLivePlotsCheck.Layout.Row = 8;
            obj.ShowLivePlotsCheck.Layout.Column = 2;
            obj.ShowLivePlotsCheck.Tooltip = stimgen.util.tooltip('CalibrationGui', 'ShowLivePlots');

            transferLogXLabel = uilabel(g, Text='Transfer Plot Log X-Axis', HorizontalAlignment='right');
            transferLogXLabel.Layout.Row = 9;
            transferLogXLabel.Layout.Column = 1;
            obj.TransferLogXCheck = uicheckbox(g, Text='', Value=true, ...
                ValueChangedFcn=@(~,~) obj.on_transfer_log_x_());
            obj.TransferLogXCheck.Layout.Row = 9;
            obj.TransferLogXCheck.Layout.Column = 2;

            toneSweptLabel = uilabel(g, Text='Tone Lookup From Swept Sine', HorizontalAlignment='right');
            toneSweptLabel.Layout.Row = 10;
            toneSweptLabel.Layout.Column = 1;
            obj.ToneSweptSineCheck = uicheckbox(g, Text='', ...
                ValueChangedFcn=@(~,~) obj.on_tone_lut_source_());
            obj.ToneSweptSineCheck.Layout.Row = 10;
            obj.ToneSweptSineCheck.Layout.Column = 2;
            obj.ToneSweptSineCheck.Tooltip = stimgen.util.tooltip('CalibrationGui', 'ToneLutFromSweptSine');

            obj.BtnReference = uibutton(g, Text='Measure Reference', ...
                ButtonPushedFcn=@(~,~) obj.on_measure_reference_());
            obj.BtnReference.Layout.Row = 11;
            obj.BtnReference.Layout.Column = [1 2];
            obj.BtnReference.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnReference');

            % Sits with the reference step, the other measurement that plays
            % nothing, and after it: the noise floor is only a level in dB SPL
            % once the reference has set the scale it is read on.
            obj.BtnBackground = uibutton(g, Text='Measure Background', ...
                ButtonPushedFcn=@(~,~) obj.on_measure_background_());
            obj.BtnBackground.Layout.Row = 12;
            obj.BtnBackground.Layout.Column = [1 2];
            obj.BtnBackground.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnBackground');

            obj.BtnTones = uibutton(g, Text='Calibrate Tones', ...
                ButtonPushedFcn=@(~,~) obj.on_calibrate_tones_());
            obj.BtnTones.Layout.Row = 13;
            obj.BtnTones.Layout.Column = [1 2];
            obj.BtnTones.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnTones');

            obj.BtnClicks = uibutton(g, Text='Calibrate Clicks', ...
                ButtonPushedFcn=@(~,~) obj.on_calibrate_clicks_());
            obj.BtnClicks.Layout.Row = 14;
            obj.BtnClicks.Layout.Column = [1 2];
            obj.BtnClicks.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnClicks');

            obj.BtnSweptSine = uibutton(g, Text='Calibrate Swept Sine', ...
                ButtonPushedFcn=@(~,~) obj.on_calibrate_swept_sine_());
            obj.BtnSweptSine.Layout.Row = 15;
            obj.BtnSweptSine.Layout.Column = [1 2];
            obj.BtnSweptSine.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnSweptSine');

            % Sits next to the sweep that builds the table it checks, ahead of
            % the equalizer: a filter designed on a table whose levels are
            % wrong inherits that error.
            obj.BtnTestTones = uibutton(g, Text='Test Tones', ...
                ButtonPushedFcn=@(~,~) obj.on_test_tones_());
            obj.BtnTestTones.Layout.Row = 16;
            obj.BtnTestTones.Layout.Column = [1 2];
            obj.BtnTestTones.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnTestTones');

            obj.BtnFilter = uibutton(g, Text='Design Filter', ...
                ButtonPushedFcn=@(~,~) obj.on_design_filter_());
            obj.BtnFilter.Layout.Row = 17;
            obj.BtnFilter.Layout.Column = [1 2];
            obj.BtnFilter.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnFilter');

            obj.BtnTestFilter = uibutton(g, Text='Test Filter', ...
                ButtonPushedFcn=@(~,~) obj.on_test_filter_());
            obj.BtnTestFilter.Layout.Row = 18;
            obj.BtnTestFilter.Layout.Column = [1 2];
            obj.BtnTestFilter.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnTestFilter');

            obj.BtnStop = uibutton(g, Text='Stop', ...
                BackgroundColor=[0.7 0.15 0.15], FontColor=[1 1 1], ...
                Enable='off', ...
                ButtonPushedFcn=@(~,~) obj.on_stop_());
            obj.BtnStop.Layout.Row = 19;
            obj.BtnStop.Layout.Column = [1 2];
            obj.BtnStop.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnStop');

            obj.BtnReset = uibutton(g, Text='Reset Calibration', ...
                ButtonPushedFcn=@(~,~) obj.on_reset_calibration_());
            obj.BtnReset.Layout.Row = 20;
            obj.BtnReset.Layout.Column = [1 2];
            obj.BtnReset.Tooltip = stimgen.util.tooltip('CalibrationGui', 'BtnReset');

            obj.StatusLabel = uilabel(g, Text='Ready.', HorizontalAlignment='left');
            obj.StatusLabel.Layout.Row = 21;
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
        end

        function on_transfer_log_x_(obj)
            % Toggle log/linear frequency on the transfer panel and redraw.
            obj.Monitor.LogX = obj.TransferLogXCheck.Value;
            obj.refresh_all_plots_();
        end

        function on_close_(obj, fig)
            % Release the monitor before the axes it draws into are deleted.
            % The engine may outlive this window -- it might be shared with a
            % host application -- and must not keep notifying a renderer whose
            % axes died with the figure.
            if ~isempty(obj.Monitor) && isvalid(obj.Monitor)
                obj.Monitor.detach();
                delete(obj.Monitor);
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
            % View > Calibration Transfer Curves brings the tables back.
            obj.Monitor.show_background(obj.Engine);
            obj.Monitor.show_engine_state(obj.Engine);

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

        function on_show_transfer_(obj)
            obj.refresh_all_plots_();
            obj.set_status_('Showing calibration transfer curves.', false);
        end

        function on_show_background_(obj)
            % show_background resets the monitor's whole graphics cache, not
            % just the transfer panel's share of it, so the response panels have
            % to be redrawn after it -- the same ordering refresh_all_plots_
            % depends on.
            obj.Monitor.show_background(obj.Engine);
            obj.Monitor.show_engine_state(obj.Engine);
            obj.set_status_('Showing background noise analysis.', false);
        end

        function update_background_menu_(obj)
            % The background view is only reachable once something has been
            % captured; there is nothing to draw before that.
            if isempty(obj.BackgroundViewMenu) || ~isvalid(obj.BackgroundViewMenu)
                return
            end
            C = obj.Engine.CalibrationData;
            hasBackground = isstruct(C) && isfield(C, 'background') && ~isempty(C.background);
            if hasBackground
                obj.BackgroundViewMenu.Enable = 'on';
            else
                obj.BackgroundViewMenu.Enable = 'off';
            end
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
                'Click durations (ms), e.g. 0.01 0.02 0.04 or 0.01.*2.^(0:9). Leave empty for the default 0.01..5.12 ms octave series. Durations below one sample at the current Fs are skipped.', ...
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
            msg = sprintf( ...
                'Equalization filter designed: %d taps, %.1f dB correction span, Fs = %g Hz.', ...
                D.numCoefficients, D.correctionDb, D.sampleRate);

            % A filter cut for a rate other than the one attached is a
            % legitimate thing to want, and a silent trap if it was not
            % intended -- test_filter is the only thing that refuses it, and
            % apply_calibration would happily run it at the wrong rate. Flag it
            % on the way out.
            fsHardware = obj.Engine.Fs;
            isOverride = fsHardware > 0 && abs(D.sampleRate - fsHardware) > 1e-6 * fsHardware;
            if isOverride
                msg = sprintf(['%s The attached hardware runs at %g Hz, so this filter is ' ...
                    'for another rig -- it cannot be tested or used here.'], msg, fsHardware);
            end
            obj.set_status_(msg, isOverride);
        end

        function on_test_filter_(obj)
            obj.with_busy_state_(@() obj.run_test_filter_(), 'Testing filter...', true);
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
            % rendering the discarded one.
            obj.Monitor.attach(eng);
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
                '3) Put an acoustic calibrator (e.g. PCB CAL150) on the microphone, switch it on, and click "Measure Reference" to update microphone sensitivity. This step records only -- nothing is played. Remove the calibrator afterwards.\n\n', ...
                '3b) Optional but recommended: with the calibrator removed and the rig running as it normally does, click "Measure Background" to record the noise floor every later measurement sits on. Nothing is played. The result is plotted as band levels and saved with the calibration; View > Background Noise Analysis brings it back.\n\n', ...
                '4) Click "Calibrate Tones" (required for tone lookup), or run "Calibrate Swept Sine" and check "Tone Lookup From Swept Sine" to serve tone lookups from the sweep instead (overrides any direct tone calibration while checked).\n\n', ...
                '5) Click "Test Tones" to check the table: tones are played at the levels the table says to use, and the levels that come back are compared to the ones requested. Do this before trusting the calibration in an experiment.\n\n', ...
                '6) Optional: run "Calibrate Clicks" and/or "Calibrate Swept Sine".\n\n', ...
                '7) Optional: click "Design Filter" (enabled after tone or swept sine calibration).\n\n', ...
                '8) Save calibration with File > Save .esgc.']);
            uialert(obj.Figure, msg, 'Calibration Quick Start', Icon='info');
        end

        function ok = apply_controls_to_engine_(obj)
            ok = false;
            try
                if obj.ToneSweptSineCheck.Value
                    toneLutSource = "swept_sine";
                else
                    toneLutSource = "tone";
                end
                obj.Engine.set_configuration( ...
                    ReferenceLevel=obj.RefLevelField.Value, ...
                    ReferenceFrequency=obj.RefFreqField.Value, ...
                    MicSensitivity=obj.MicSensField.Value, ...
                    NormativeValue=obj.NormativeField.Value, ...
                    ExcitationVoltage=obj.ExcitationField.Value, ...
                    MaxOutputVoltage=obj.MaxOutputField.Value, ...
                    ShowLivePlots=obj.ShowLivePlotsCheck.Value, ...
                    ToneLutSource=toneLutSource);
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
            obj.MaxOutputField.Value = obj.Engine.MaxOutputVoltage;
            obj.ShowLivePlotsCheck.Value = obj.Engine.ShowLivePlots;
            obj.ToneSweptSineCheck.Value = obj.Engine.ToneLutSource == "swept_sine";
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

            obj.update_background_menu_();

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
        end

        function refresh_sample_rate_label_(obj)
            fs = obj.Engine.Fs;
            if fs > 0
                txt = sprintf('%g Hz', fs);
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
                txt = sprintf('%s (filter designed at %g Hz)', txt, designFs);
                obj.SampleRateLabel.FontColor = [0.7 0 0];
            else
                obj.SampleRateLabel.FontColor = [0 0 0];
            end
            obj.SampleRateLabel.Text = txt;
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
            fsHardware = obj.Engine.Fs;
            if fsHardware > 0
                ratePrompt = sprintf( ...
                    'Design sample rate (Hz; empty or 0 = hardware rate, %g Hz):', fsHardware);
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
                obj.BtnFilter.Enable = 'off';
                obj.BtnTestFilter.Enable = 'off';
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
