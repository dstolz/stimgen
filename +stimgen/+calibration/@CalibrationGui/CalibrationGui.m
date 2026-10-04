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
    % The Microphone section holds everything about the microphone end of the
    % rig: what the acoustic calibrator produces, the sensitivity measured from
    % it, and the conduction delay probe. A probe draws its correlation curve on
    % the transfer panel -- the evidence one lag was chosen over another, which
    % the waveform cannot show -- and the View menu keeps it reachable
    % afterwards.
    %
    % The Options menu holds three settings windows. Hardware and Analysis
    % Settings is what is set once per rig rather than once per sweep: the
    % output ceiling, AC coupling of the acquired record, the ADC gain and
    % DAC attenuation the rig is set to, and the analysis window and FFT
    % length every spectral measurement is made with. The last two also
    % govern the spectrum panel, so the peak on screen is computed the same
    % way as the number written into the lookup table. The two gains are the
    % odd pair out: nothing reads them, since a sweep is measured through
    % whatever gain the rig is set to and applying it again would
    % double-count it. They are typed here so the .esgc records the knob
    % positions it was made at, which is the one thing a finished table
    % cannot be checked against.
    %
    % Conduction Delay Settings holds what the delay probe searches with and
    % the room's Ambient Temperature its result is read as a distance
    % through -- the probe runs straight from its button, asking nothing.
    % Temperature is entered and displayed in degrees Celsius, the unit the
    % Engine holds it in and an .esgc file records, as is every other
    % display of it. Excitation Settings holds the drive voltage every sweep
    % plays at and the per-edge rise/fall time every tone burst is gated with --
    % both apply to whichever sweep runs next, like the two windows above,
    % rather than to a step of their own.
    %
    % The Notes box at the bottom of the controls column is the operator's
    % own account of the calibration -- the speaker and microphone, where
    % they stood, whatever the tables cannot state for themselves. It is
    % kept on the Engine and written into the .esgc, so it comes back with
    % the calibration it describes; it is not a preference and does not
    % follow the window to the next file.
    %
    % The window itself can be captured as a record of the session: File >
    % Save Screenshot... writes the entire window -- controls column
    % included -- to an image file, and File > Copy Window to Clipboard
    % (also the toolbar's camera button) puts the same capture on the
    % system clipboard. The full-window clipboard copy is Windows-only;
    % elsewhere the plot area alone is copied. File > Print Calibration
    % Summary (also the toolbar's page-of-text button, beside the camera)
    % writes the same session as text instead: Engine.describe on the
    % command window, where it can be copied into a notebook.
    %
    % The Help menu, and the last two buttons of the toolbar's first group,
    % open the wiki page that documents this window: the question mark at
    % the top of the walkthrough, the open book at its tour of this GUI.
    %
    % Settings are remembered across MATLAB sessions as StimCalibrationGui
    % preferences (Notes excepted -- it belongs to the calibration, not to
    % this window): the controls-column fields and toggles, both settings
    % windows' fields, the display state (spectrum unit, weighting overlays,
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
    % The waveform and the spectrum are always on screen -- they are the record
    % being acquired -- and under them a tab per measurement: one for each
    % stimulus that can be calibrated (Tones, Clicks, Swept Sine), then the
    % equalization filter test, the background noise analysis and the
    % conduction delay probe. Each has its own axes, so every one keeps what
    % was last drawn on it and switching between them costs nothing and loses
    % nothing.
    %
    % The stimulus tabs are not one plot drawn three times. Each carries its
    % lookup table on the abscissa that table is keyed on -- frequency, or
    % click duration, which cannot share one axis honestly -- and under it
    % what only that stimulus measures: the per-frequency distortion and SNR
    % a tone sweep records, the same against duration for clicks, and for a
    % swept sine the deconvolved flatness, the group delay and the impulse
    % response, none of which a level-versus-x curve can show. A sweep and
    % the test that verifies its table both draw on that stimulus's tab, and
    % starting either brings it up.
    %
    % The Filter Test tab is the one that verifies no table. It measures the
    % rig twice -- once as it is and once through the equalizer -- so what it
    % has to show is a comparison: the two responses, and under them each
    % one's deviation from flat against the ripple tolerance it passes or
    % fails on. That is why it is not on the Tones tab, where one of the two
    % curves was always about to be overwritten by the other.
    %
    % How those panels draw -- the overlays -- is chosen from the toolbar's
    % second group, mirrored by the View menu and the Display section, since a
    % display choice is made while reading a plot rather than while setting a
    % sweep up. That state lives on the monitor; every control is a mirror of
    % it, written only by sync_display_controls_. WHICH measurement is being
    % read is the tab strip's own business: it selects and reports in one
    % place, and TransferView_ follows it.
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

        % Help > Guide to This Window opens the same page at its step-by-step
        % tour of this GUI. The same page deliberately: the workflow and
        % the window are documented together, because a control is only
        % explicable by the step it belongs to. The two entry points differ
        % in where they land -- the top for what calibration is, this anchor
        % for what to press -- so neither audience scrolls past the other's
        % half.
        GuiGuideURL = 'https://github.com/dstolz/stimgen/wiki/Calibrating-Your-Rig#gui-walkthrough-recommended'
    end

    properties (Constant, Access = private)
        % Accepted range of Engine.AmbientTemperature, in Celsius -- the unit
        % the Engine holds it in. Stated here rather than on the field because
        % a stored preference is validated against it before the field that
        % would enforce it exists (restore_engine_settings_).
        AmbientTempLimitsC = [-50, 60]
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
        WeightingMenus          % one checkable item per LiveMonitor.WeightingTypes
        SpectrumUnitMenus       % one checkable item per LiveMonitor.SpectrumUnitList
        GhostMenu
        VoltageMenu
        WaveformResMenu         % checked = every sample; see set_full_resolution_

        % Which measurement the lower plots area is showing. Follows the tab
        % strip rather than driving it -- the tabs are the selector, this is
        % the name the rest of the object and the saved preference use. The
        % three sweep names are also LiveMonitor's panel names and the
        % Engine's CalibrationData fields, which is what lets one string
        % carry a view from a tab callback through to the renderer.
        TransferView_ (1,1) string = "tone"

        % Diagnostics of the last conduction delay probe, kept so the panel
        % can be drawn again after another view has taken it. Session state,
        % not calibration data: nothing saves it, and a new probe replaces it.
        LastLatency_ = []

        % Display toolbar. Each of these mirrors a View menu item or the
        % Display section's checkbox rather than owning state of its own:
        % what a plot shows is changed while reading the plot, which is when
        % crossing the window to a menu is most in the way. sync_display_-
        % controls_ is the one writer that keeps every mirror in step.
        %
        % Overlays only. Choosing which measurement to look at is the tab
        % strip's job, so the two view-selecting tools that were here went
        % with the panel they switched.
        ToolGhost
        ToolVoltage
        ToolLogX

        % Controls
        RefLevelField
        RefFreqField
        MicSensField
        NormativeField
        ShowLivePlotsCheck
        TransferLogXCheck
        ToneSweptSineCheck
        IterativeCheck
        % Free text about this calibration, at the bottom of the controls
        % column. It belongs to the Engine and travels in the .esgc, unlike
        % every other control here, which is why it is neither remembered as
        % a preference nor cleared by a reset: it describes one calibration,
        % not this rig or this window.
        NotesArea
        StatusLabel
        LevelRefLabel
        ConductionDelayLabel

        % Hardware & Analysis Settings window (Options menu): a
        % stimgen.calibration.SettingsDialog made with this object, whose
        % figure is built on demand. The field handles below are empty until
        % it is first opened and dead once it is closed -- everything that
        % writes them guards on the dialog being open. The settings
        % themselves live on the Engine; the window is only a view of them.
        HardwareDialog_
        MaxOutputField
        AcCoupleCheck
        AdcGainField
        DacAttenField
        SpectralWindowDrop
        SpectralFftDrop
        SampleRateLabel

        % Excitation Settings window (Options menu), on demand and guarded
        % the same way. The drive voltage every sweep plays at and the
        % per-edge rise/fall time every tone burst is gated with -- neither
        % is a step of its own, and both apply to whichever sweep runs next
        % rather than to the one that made an already-committed table.
        ExcitationDialog_
        ExcitationField
        ToneRampField

        % Conduction Delay Settings window (Options menu), on demand and
        % guarded the same way. Unlike the settings above, the probe's two
        % parameters are not Engine properties -- nothing but this window
        % sets them -- so the values live here and the fields are a view of
        % them. Ambient Temperature is the exception on this window: it does
        % belong to the Engine, and is what the probe's delay is read as a
        % distance through.
        DelayDialog_
        DelayMaxField
        DelayClicksField
        AmbientTempField        % degrees Celsius, the unit the Engine holds
        DelayMaxMs_ (1,1) double = 50
        DelayNumClicks_ (1,1) double = 1

        % Run state. Busy_ is true while with_busy_state_ is running an
        % action; a close request that arrives then (the X, pumped in by the
        % engine's own drawnow between measurements) cancels the engine and
        % sets CloseRequested_ instead of deleting the window out from under
        % the run, and with_busy_state_ finishes the close once the run has
        % unwound. Dirty_ is set when a run changes the engine's calibration
        % (Engine.DataRevision moved, or the reference was re-measured) and
        % cleared by a save or a load; closing or loading over it asks first.
        Busy_ (1,1) logical = false
        BusyMessage_ (1,:) char = ''   % the running action's status line, which progress is appended to
        CloseRequested_ (1,1) logical = false
        Dirty_ (1,1) logical = false

        % Listener on the engine's ConductionDelay property, so the readout
        % updates the moment a click probe lands rather than waiting for the
        % run to finish. Rebound whenever the engine is swapped (run_load_).
        DelayListener_
        ProgressListener_   % on Engine.RunProgress; rebound with DelayListener_

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
        BtnDelay
        BtnStop
        BtnReset

        % Axes. The first two are always on screen; the rest belong to tabs.
        % A stimulus tab carries more than one: the lookup table on top and,
        % under it, what only that stimulus measures.
        AxTime
        AxSpectrum
        AxTone
        AxToneDetail
        AxClick
        AxClickDetail
        AxSwept
        AxSweptDetail
        AxSweptImpulse
        AxFilterTest
        AxFilterDetail
        AxBackground
        AxLatency

        % The plots panel's tab strip and its tabs. Each tab holds one
        % measurement, so switching between them costs nothing and loses
        % nothing -- every panel keeps whatever was last drawn on it.
        PlotTabs
        ToneTab
        ClickTab
        SweptTab
        FilterTestTab
        BackgroundTab
        LatencyTab
    end

    methods
        % One file each in this folder.
        show(obj)
        set_adapter(obj, adapter)

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

            obj.create_settings_dialogs_();
            obj.build_ui_();
            obj.restore_settings_prefs_();
            obj.bind_engine_listeners_();
            obj.sync_controls_();
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.show_startup_hint_();
        end

        function delete(obj)
            % A run still in progress is driving the speaker for a window
            % that no longer exists; stop it at the next measurement.
            if obj.Busy_ && ~isempty(obj.Engine) && isvalid(obj.Engine)
                obj.Engine.cancel();
            end
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
            delete(obj.ProgressListener_);
            % The settings windows are owned by this object, not by
            % the main figure, so they do not die with either on their own.
            if ~isempty(obj.HardwareDialog_) && isvalid(obj.HardwareDialog_)
                delete(obj.HardwareDialog_);
            end
            if ~isempty(obj.DelayDialog_) && isvalid(obj.DelayDialog_)
                delete(obj.DelayDialog_);
            end
            if ~isempty(obj.ExcitationDialog_) && isvalid(obj.ExcitationDialog_)
                delete(obj.ExcitationDialog_);
            end
        end
    end

    % Everything else is a helper: one file each in this folder, private.
    % The window's own callbacks reach them through handles made inside
    % the class. Utilities that need no object live in private/.
    methods (Access = private)
        build_ui_(obj)
        build_toolbar_(obj)
        build_display_tools_(obj, tb, tip)
        build_menu_(obj)
        build_controls_panel_(obj)
        [g, h] = add_section_(obj, parent, row, titleText, rowHeights)
        build_reference_section_(obj, g)
        create_settings_dialogs_(obj)
        on_hardware_settings_(obj)
        build_hardware_dialog_(obj, g)
        on_hardware_setting_changed_(obj)
        on_spectral_setting_changed_(obj)
        sync_hardware_dialog_(obj)
        on_delay_settings_(obj)
        build_delay_dialog_(obj, g)
        on_delay_setting_changed_(obj)
        on_ambient_temp_changed_(obj)
        sync_delay_dialog_(obj)
        on_excitation_settings_(obj)
        build_excitation_dialog_(obj, g)
        on_excitation_setting_changed_(obj)
        sync_excitation_dialog_(obj)
        build_calibration_section_(obj, g)
        build_verification_section_(obj, g)
        build_display_section_(obj, g)
        build_notes_section_(obj, g)
        commit_notes_(obj)
        on_print_summary_(obj)
        build_footer_(obj, col)
        build_plots_panel_(obj)
        build_tone_tab_(obj)
        build_click_tab_(obj)
        build_swept_tab_(obj)
        build_filter_test_tab_(obj)
        [tab, ax] = add_plot_tab_(obj, titleText, tooltipKey)
        [tab, tg] = add_stacked_tab_(obj, titleText, tooltipKey, rowHeights, colWidths)
        ax = tab_axes_(obj, tg, row, col)
        on_plot_tab_changed_(obj, evt)
        on_spectrum_units_(obj, src)
        sync_spectrum_units_menu_(obj)
        set_transfer_log_x_(obj, tf)
        set_show_ghost_(obj, tf)
        set_show_voltage_(obj, tf)
        set_full_resolution_(obj, tf)
        set_transfer_view_(obj, view)
        focus_sweep_panel_(obj, stage)
        redraw_transfer_panels_(obj)
        sync_display_controls_(obj)
        on_weighting_(obj, src)
        on_weighting_none_(obj)
        apply_weightings_(obj)
        on_close_(obj, fig)
        on_figure_deleted_(obj)
        proceed = confirm_discard_(obj, actionText)
        on_measure_reference_(obj)
        run_measure_reference_(obj)
        on_measure_background_(obj)
        run_measure_background_(obj, p)
        [p, wasCancelled] = prompt_background_parameters_(obj)
        on_measure_delay_(obj)
        run_measure_delay_(obj)
        s = lut_spec_(obj, kind)
        on_calibrate_lut_(obj, kind)
        run_calibrate_lut_(obj, kind, points, repeatCount, refine)
        on_test_lut_(obj, kind)
        run_test_lut_(obj, kind, points, levels, repeatCount)
        on_calibrate_swept_sine_(obj)
        run_calibrate_swept_sine_(obj, duration, freqs, repeatCount)
        on_tone_lut_source_(obj)
        on_design_filter_(obj)
        run_design_filter_(obj, source, opts)
        on_test_filter_(obj)
        run_test_filter_(obj)
        on_copy_filter_coefficients_(obj)
        on_save_screenshot_(obj)
        on_copy_window_(obj)
        on_save_(obj)
        ffn = run_save_(obj, ffn)
        on_load_(obj)
        run_load_(obj, ffn)
        on_attach_adapter_(obj)
        run_attach_adapter_(obj)
        on_initialize_runtime_(obj)
        run_initialize_runtime_(obj, protocolPath)
        on_disconnect_runtime_(obj)
        run_disconnect_runtime_(obj)
        refresh_recent_protocols_menu_(obj)
        refresh_recent_calibrations_menu_(obj)
        refresh_recent_menu_(obj, menu, prefName, openFcn)
        open_recent_protocol_(obj, filePath)
        open_recent_calibration_(obj, filePath)
        add_recent_protocol_(obj, filePath)
        remove_recent_protocol_(obj, filePath)
        add_recent_calibration_(obj, filePath)
        remove_recent_calibration_(obj, filePath)
        assert_host_(obj)
        on_show_quick_start_(obj)
        on_show_gui_guide_(obj)
        open_wiki_page_(obj, url, dlgTitle, what)
        ok = apply_controls_to_engine_(obj)
        sync_controls_(obj)
        refresh_all_plots_(obj)
        update_runtime_state_(obj)
        bind_engine_listeners_(obj)
        on_run_progress_(obj)
        refresh_conduction_delay_label_(obj)
        refresh_sample_rate_label_(obj)
        refresh_level_reference_label_(obj)
        fs = filter_design_rate_(obj)
        show_startup_hint_(obj)
        [values, repeatCount, refine, wasCancelled] = prompt_vector_parameter_(obj, prefName, repeatPrefName, label, tipKey, dlgTitle, includeRefinement)
        report_refinement_(obj, r, whatLabel)
        [duration, freqs, repeatCount, wasCancelled] = prompt_swept_sine_parameters_(obj)
        [points, levels, repeatCount, wasCancelled] = prompt_test_grid_(obj, dlgTitle, what, pointLabel, pointTip, levelLabel, levelTip, pointPref, levelPref, repeatPref)
        [source, opts, wasCancelled] = prompt_filter_parameters_(obj)
        value = get_pref_(obj, prefName, defaultValue)
        set_pref_(obj, prefName, value)
        restore_settings_prefs_(obj)
        restore_engine_settings_(obj)
        restore_display_settings_(obj)
        save_settings_prefs_(obj)
        on_stop_(obj)
        on_reset_calibration_(obj)
        set_busy_(obj, tf, cancellable)
        with_busy_state_(obj, fcn, busyMessage, cancellable)
        tf = ui_alive_(obj)
        set_status_(obj, msg, isError)
    end
end
