classdef StimPlayer < handle

    % obj = stimgen.StimPlayer
    % obj = stimgen.StimPlayer(HOST)
    % Standalone stimulus bank and playback peripheral.
    %
    % Developer guide: documentation/stimgen_StimPlayer.md
    %
    % Manages a named bank of stimgen.StimPlay objects, schedules them
    % using a serial or shuffle strategy at a configurable global ISI,
    % uploads audio buffers to hardware via a stimgen.HardwareHost, and
    % triggers playback from its own timer (independent of PsychTimer).
    %
    % When a host is not provided or required hardware parameters are not
    % found, hardware playback is disabled and only speaker preview is
    % available via Play and Play All.
    %
    % Play and Play All audition through the computer speakers by default
    % (normalized to unit peak, so calibrated levels are NOT reproduced).
    % When a host is attached, PlaybackOutput = "Hardware" routes them
    % through the host's calibration hardware instead, playing the
    % generated waveform verbatim so a loaded calibration is heard at its
    % calibrated voltage. The status bar reports whether a calibration is
    % loaded and whether the selected output actually applies it.
    %
    % Capture (capture_stim; Tools > Capture Selected Stimulus, or the
    % microphone toolbar button) plays the selected combination through
    % hardware that can also record -- CaptureAdapter, or the host's
    % calibration adapter -- records the microphone, and opens the recording
    % in its own stimgen.StimInspector. With a calibration loaded the
    % recording carries its microphone sensitivity, so the inspector reads it
    % in pascals and dB SPL: sound-level-meter readouts, band levels, the
    % noise floor it sat on, and the level the stimulus asked for against the
    % level that came back.
    %
    % Required parameter names (resolved from the host at Run time):
    %   BufferData_0, BufferData_1   - audio data buffers
    %   BufferSize_0, BufferSize_1   - buffer length in samples
    %   x_Trigger_0, x_Trigger_1    - playback trigger pulses
    %
    % Usage:
    %   sp = stimgen.StimPlayer;       % GUI only, speaker preview
    %   sp = stimgen.StimPlayer(HOST); % with host-provided hardware
    %
    % Properties (selected):
    %   StimPlayObjs  - Bank of stimgen.StimPlay objects
    %   Host          - Optional stimgen.HardwareHost for hardware playback
    %   Fs            - Bank-wide sample rate in Hz
    %   ISI           - Global ISI range [min max] in seconds
    %   SelectionType - "Serial" or "Shuffle"
    %
    % An interfacing application that drives the session itself can hide the
    % Reps/ISI/PlayMode/Run/Pause controls (see set_control_visibility) and
    % run playback through playback_control("Run"|"Stop"|"Pause"|"Resume").

    % --- External method declarations ---
    methods
        create(obj)
        open_stim(obj, stimObj, varargin)
        add_stim(obj, src, event)
        duplicate_stim(obj, src, event)
        remove_stim(obj, src, event)
        on_bank_selection_changed(obj, src, event)
        update_signal_plot(obj, stimObj, label)
        playback_control(obj, src, event)
        timer_startfcn(obj, src, event)
        timer_runtimefcn(obj, src, event)
        timer_stopfcn(obj, src, event)
        update_buffer(obj)
        trigger_stim_playback(obj)
        play_preview(obj, src, event)
        play_all(obj, src, event)
        step_combination(obj, step)
        open_calibration_gui(obj)
        open_stim_inspector(obj)
        viewer = show_all_combinations(obj, src, event)
        rec = capture_stim(obj, src, event)
        dlg = edit_capture_settings(obj)
        save_bank(obj, ffn)
        save_bank_as(obj)
        load_bank(obj, ffn)
        set_control_visibility(obj, options)
        idx = select_next_idx(obj)
    end

    % --- Private helpers (one file each; trailing underscore) ---
    % Callbacks reach them through handles made inside the class, and
    % local functions in this folder's method files share the class's
    % access, so nothing outside @StimPlayer needs them.
    methods (Access = private)
        set_computing_(obj, tf)
        sp = selected_or_current_spobj_(obj)
        [stimObj, label] = inspector_source_(obj)
        refresh_inspector_(obj)
        adapter = resolve_capture_adapter_(obj)
        [calObj, source] = capture_calibration_(obj, stimObj)
        show_capture_inspector_(obj, rec, label)
        sync_capture_controls_(obj)
        capture_finished_(obj)
        load_capture_settings_(obj)
        save_capture_settings_(obj)
        resolve_params_(obj)
        reason = hardware_unavailable_reason_(obj)
        require_run_hardware_(obj)
        load_protocol_(obj, protocolInput)
        initialize_runtime_from_protocol_(obj)
        disconnect_interfaces_(obj)
        require_hardware_host_(obj)
        tf = has_hardware_route_(obj)
        require_hardware_route_(obj)
        on_playback_output_changed_(obj)
        adapter = resolve_preview_adapter_(obj)
        play_via_hardware_(obj, stimObj)
        ensure_host_connected_(obj)
        check_preview_rate_(obj, hwFs, stimFs)
        tf = stim_has_calibration_(obj, stimObj)
        update_calibration_status_(obj)
        lock_bank_controls_(obj, lockState)
        idx = selected_bank_index_(obj)
        sync_control_enable_(obj)
        apply_control_visibility_(obj)
        set_widgets_visible_(obj, fieldNames, show)
        update_protocol_status_(obj)
        mark_bank_dirty_(obj)
        mark_bank_clean_(obj, ffn)
        update_title_(obj)
        tf = confirm_discard_changes_(obj, actionText)
        on_close_request_(obj)
        failures = apply_fs_to_bank_(obj)
        sync_fs_field_(obj)
        adopt_host_fs_(obj)
        load_calibration_(obj, ffn)
        refresh_recent_menus_(obj)
        refresh_recent_menu_(obj, handleField, prefName, openFcn)
        remember_recent_protocol_(obj, filePath)
        forget_recent_protocol_(obj, filePath)
        remember_recent_bank_(obj, filePath)
        forget_recent_bank_(obj, filePath)
        remember_recent_calibration_(obj, filePath)
        forget_recent_calibration_(obj, filePath)
        remember_recent_(obj, prefName, action, filePath)
        names = remembered_setting_names_(obj, stimObj)
        remember_stim_settings_(obj, stimObj)
        stored = get_remembered_settings_(obj)
        apply_remembered_settings_(obj, stimObj)
        get_isi_(obj)
        update_counter_(obj)
        n = presented_count_(obj)
        n = total_count_(obj)
        refresh_listbox_(obj)
        refresh_combo_controls_(obj)
        [txt, uneven, detail] = reps_per_combination_(obj, reps, stimObj)
        lines = uneven_reps_report_(obj)
        proceed = confirm_run_(obj)
        initialize_variants_(obj)
        advance_variant_(obj, stimObj)
        sgn = claim_polarity_(obj)
        report_gui_error_(obj, ME, titleText, userMessage)
        show_gui_message_(obj, messageText, titleText, iconName)
        set_status_(obj, messageText, options)
        messageText = format_gui_error_message_(obj, ME, fallbackText)
    end

    % --- Public properties ---
    properties
        StimPlayObjs (:,1) stimgen.StimPlay   % Bank of stimulus playback objects

        % Sample rate applied to every stimulus in the bank, in Hz. One rate
        % is held for the whole bank because the hardware plays them all
        % through the same converter; assigning it rewrites Fs on every bank
        % item and regenerates their signals. Run adopts the hardware rate
        % when the attached host reports one.
        Fs (1,1) double {mustBePositive,mustBeFinite} = 97656.25

        ISI (1,2) double {mustBePositive,mustBeFinite} = [1.0 1.0] % Global ISI range [min max] in seconds

        SelectionType (1,1) string {mustBeMember(SelectionType,["Serial","Shuffle"])} = "Shuffle" % Playback order

        % Where Play / Play All audition the selected stimulus.
        %   "Speakers" - computer sound card; the signal is normalized to
        %                unit peak, so a calibration sets spectrum shape at
        %                most and calibrated levels are NOT reproduced.
        %   "Hardware" - the attached host's calibration hardware route
        %                (stimgen.HardwareHost.calibrationAdapter), or, with
        %                no host, CaptureAdapter; the generated waveform is
        %                played verbatim, so a loaded calibration is heard at
        %                its calibrated voltage.
        % Selecting "Hardware" requires a host or a CaptureAdapter and errors
        % with neither.
        % Hardware Run sessions always play the generated waveform and are
        % unaffected by this setting.
        PlaybackOutput (1,1) string {mustBeMember(PlaybackOutput,["Speakers","Hardware"])} = "Speakers"

        DataPath (1,1) string = string(fullfile('C:\Users', getenv('USERNAME'))) % Default save path

        % Visibility of the session controls an interfacing application may
        % want to own itself.  Scalar struct of logicals; assign whole or by
        % field (sp.ControlVisibility.ISI = false), or use
        % set_control_visibility for name-value syntax.  Hidden controls are
        % collapsed out of the layout but remain settable programmatically.
        ControlVisibility (1,1) struct = struct( ...
            'Reps',       true, ... % Per-stimulus repetition count field
            'ISI',        true, ... % Inter-stimulus interval field
            'SampleRate', true, ... % Bank-wide sample rate field
            'PlayMode',   true, ... % Playback order dropdown (Shuffle/Serial)
            'Output',     true, ... % Preview output dropdown (Speakers/Hardware)
            'Run',        true, ... % Run/Stop button
            'Pause',      true)     % Pause/Resume button

        % Where capture_stim plays and records: a stimgen.calibration.HwAdapter,
        % or a function handle returning one. A handle is called at each
        % capture, so a host can build the adapter from whatever its device
        % settings are at that moment rather than when the player opened.
        % Empty falls back to the attached host's calibration adapter; with
        % neither, capture is unavailable and its controls are disabled.
        % With no host attached it is also the "Hardware" preview route
        % (PlaybackOutput): hardware that can capture a stimulus can play one,
        % and an application that owns its own audio path supplies this
        % rather than a HardwareHost.
        CaptureAdapter = []

        % Silence played before the stimulus in a capture, in seconds. The
        % noise floor the recording is judged against is measured over it.
        CapturePreDelay  (1,1) double {mustBeNonnegative, mustBeFinite} = 0.05

        % Silence after the stimulus, in seconds. It bounds the search for
        % the response delay, so it must be longer than the rig's round trip
        % -- converter latency plus the acoustic path -- or the response is
        % cut in the wrong place. A sound card's round trip alone can pass
        % 50 ms, hence the longer default than the lead-in.
        CapturePostDelay (1,1) double {mustBeNonnegative, mustBeFinite} = 0.1

        % Acquisitions averaged per capture, each aligned on its own delay.
        CaptureRepeats   (1,1) double {mustBeInteger, mustBePositive, mustBeFinite} = 1
    end

    % --- Capture results ---
    properties (SetAccess = protected)
        % stimgen.CapturedSignal from the most recent capture_stim, or [].
        LastCapture = []
    end

    % --- Bank file ---
    properties (SetAccess = protected)
        % The .spl file the bank was last loaded from or saved to ("" = none
        % yet). save_bank writes here without asking; save_bank_as asks,
        % offering it as the default.
        BankFile (1,1) string = ""
    end

    % --- Calibration state ---
    properties (SetAccess = protected)
        % stimgen.StimCalibration loaded via the Calibration menu, or [].
        % Shared by handle with every bank item (including ones added after
        % the load), so the status label can speak for the whole bank.
        Calibration = []

        CalibrationFile (1,1) string = "" % Source path of the loaded calibration ("" = none/embedded)
    end

    % --- Protected runtime state ---
    properties (SetAccess = protected, SetObservable)
        Timer                                          % MATLAB timer object
        TrigBufferID (1,1) double = 0                  % Alternates 0/1 for double-buffering
        firstTrigTime (1,1) double = 0                 % Absolute time at first trigger
        lastTrigTime (1,1) double = 0                  % Absolute time at last trigger
        currentISI (1,1) double = 1                    % Current ISI value (drawn from ISI range)
        nextSPOIdx (1,1) double = 1                    % Index of next StimPlayObj to present
        trialCount_ (1,1) double = 0                   % Internal trial counter for TrigBufferID

        StimOrder (:,1) double = double.empty(0,1)     % Presentation log: index into StimPlayObjs
        StimOrderTime (:,1) double = double.empty(0,1) % Presentation log: time since start (s)
        StimPolarity (:,1) double = double.empty(0,1)  % Presentation log: sign played (+1/-1)
        StimVariant (:,1) double = double.empty(0,1)   % Presentation log: variant combination index played

        nextPolarity_ (1,1) double = 1                 % Sign applied to the buffered (next) presentation
    end

    % --- Private ---
    properties (Access = private)
        Host                       % stimgen.HardwareHost | [] ([] = offline preview only)
        PARAMS struct = struct()   % Cached parameter handles keyed by validName
        els                        % Event listeners
        hFig                       % uifigure handle
        handles struct = struct()  % UI component handles

        PlayAllActive_ (1,1) logical = false % True while a Play All cycle is running
        PlayAllStimObj_                      % stimgen.StimType currently being previewed by Play All

        PreviewAdapter_                      % Cached stimgen.calibration.HwAdapter for hardware preview | []

        Inspector                            % stimgen.StimInspector | [] (detail window)

        CombinationViewers_ = {}             % stimgen.CombinationViewer windows opened from here

        CaptureInspector_                    % stimgen.StimInspector | [] showing the last capture
        Capturing_ (1,1) logical = false     % True while capture_stim is acquiring
        CaptureLocked_ (1,1) logical = false % True while a session holds the bank (lock_bank_controls_)

        PolarityCount_ = {}                  % Per bank item: presentations so far of each variant

        Paused_ (1,1) logical = false        % True while a running session is held by Pause
        HardwareRun_ (1,1) logical = false   % True when the current run started with hardware output

        Dirty_ (1,1) logical = false         % Bank edited since it was last loaded or saved
        PauseStartedAt_ (1,1) double = 0     % timeSinceStart when the current pause began
    end

    % --- Hardware parameter contract ---
    properties (Constant, Access = private)
        % Names a host circuit must expose for a hardware Run (StimGenCircuit.rcx).
        RequiredParams_ = {'BufferData_0','BufferData_1','BufferSize_0','BufferSize_1', ...
                           'x_Trigger_0','x_Trigger_1'}
    end

    % --- Dependent ---
    properties (Dependent)
        CurrentSPObj          % stimgen.StimPlay currently selected for playback
        HardwareAvailable     % true if the host exposes the required buffer/trigger parameters
        timeSinceStart        % Elapsed seconds since firstTrigTime
    end

    % =====================================================================
    methods

        function obj = StimPlayer(host)
            % obj = stimgen.StimPlayer
            % obj = stimgen.StimPlayer(host)
            % Construct StimPlayer, optionally attached to a hardware host.
            %
            % Parameters:
            %   host - stimgen.HardwareHost providing protocol and hardware
            %          access (optional; omit for offline speaker preview)

            obj.create;

            if nargin > 0 && ~isempty(host)
                mustBeA(host, 'stimgen.HardwareHost');
                obj.Host = host;
            end
            obj.update_protocol_status_;
            obj.load_capture_settings_;
            obj.sync_capture_controls_;
            obj.sync_control_enable_;  % Load Protocol needs the host set above

            if nargout == 0, clear obj; end
        end

        % -----------------------------------------------------------------
        function delete(obj)
            % Destructor: stop and clean up timer, listeners and child windows.
            obj.disconnect_interfaces_;
            if ~isempty(obj.Inspector) && isvalid(obj.Inspector)
                delete(obj.Inspector);
            end
            if ~isempty(obj.CaptureInspector_) && isvalid(obj.CaptureInspector_)
                delete(obj.CaptureInspector_);
            end
            for k = 1:numel(obj.CombinationViewers_)
                v = obj.CombinationViewers_{k};
                if ~isempty(v) && isvalid(v)
                    delete(v);
                end
            end
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
                delete(obj.Timer);
            end
            if ~isempty(obj.els)
                delete(obj.els);
            end
        end

        % -----------------------------------------------------------------
        function sp = get.CurrentSPObj(obj)
            if isempty(obj.StimPlayObjs) || obj.nextSPOIdx < 1
                sp = [];
                return
            end
            sp = obj.StimPlayObjs(min(obj.nextSPOIdx, numel(obj.StimPlayObjs)));
        end

        % -----------------------------------------------------------------
        function tf = get.HardwareAvailable(obj)
            tf = false;
            if isempty(obj.Host) || obj.Host.connectionState() == "None"
                return
            end
            tf = all(isfield(obj.PARAMS, obj.RequiredParams_));
        end

        % -----------------------------------------------------------------
        function set.ControlVisibility(obj, value)
            % Merge the incoming struct over the current state so callers may
            % pass only the controls they care about.
            merged = obj.ControlVisibility;
            names  = fieldnames(value);
            for i = 1:numel(names)
                if ~isfield(merged, names{i})
                    error('stimgen:StimPlayer:InvalidControlVisibility', ...
                        '"%s" is not a hideable StimPlayer control. Valid controls: %s.', ...
                        names{i}, strjoin(fieldnames(merged)', ', '));
                end
                v = value.(names{i});
                if ~isscalar(v) || ~(islogical(v) || isnumeric(v) || isa(v, 'matlab.lang.OnOffSwitchState'))
                    error('stimgen:StimPlayer:InvalidControlVisibility', ...
                        'ControlVisibility.%s must be a logical scalar.', names{i});
                end
                merged.(names{i}) = logical(v);
            end

            obj.ControlVisibility = merged;
            obj.apply_control_visibility_;
        end

        % -----------------------------------------------------------------
        function set.PlaybackOutput(obj, value)
            % Route Play / Play All to speakers or to hardware (the host's
            % calibration route, else CaptureAdapter). Everything that can
            % refuse the switch runs BEFORE the value is committed -- no
            % route at all, or a bank that cannot be regenerated at the
            % hardware's sample rate -- so a refused switch leaves the
            % property, and the dropdown reverted from it, on the old route.
            if value == "Hardware"
                obj.require_hardware_route_;
                % Generate at the rate the converters run at, so the bank is
                % ready for hardware. Throws (and rolls the rate back) when
                % an item cannot be generated at that rate.
                obj.adopt_host_fs_;
            end
            obj.PlaybackOutput = value;
            obj.on_playback_output_changed_;
        end

        % -----------------------------------------------------------------
        function set.CaptureAdapter(obj, value)
            % Accept an adapter, a function returning one, or empty, and
            % bring the capture controls into line with whether there is now
            % a route to record through. A handle is checked when it is
            % called, not here: calling it now would build the adapter before
            % anything asked for a capture.
            ok = isempty(value) || isa(value, 'function_handle') || ...
                (isa(value, 'stimgen.calibration.HwAdapter') && isscalar(value));
            if ~ok
                error('stimgen:StimPlayer:BadCaptureAdapter', ...
                    ['CaptureAdapter must be a stimgen.calibration.HwAdapter, a ' ...
                     'function handle returning one, or empty; got a %s.'], class(value));
            end
            if isempty(value)
                value = [];
            end
            obj.CaptureAdapter = value;
            obj.sync_capture_controls_;
            % Without a host the adapter was the hardware preview route too;
            % taking it away must not leave the output naming one.
            if isempty(value) && isempty(obj.Host) && obj.PlaybackOutput == "Hardware"
                obj.PlaybackOutput = "Speakers";
            end
            obj.update_protocol_status_;
            obj.sync_control_enable_;  % the Output dropdown follows the route
        end

        % -----------------------------------------------------------------
        function set.Fs(obj, value)
            % Push the new rate onto every bank item, then resync the GUI.
            %
            % A rate change moves Nyquist, so a stimulus whose content no
            % longer fits below it (a noise band, an FM sweep) fails to
            % regenerate. Rather than leave the bank half converted with stale
            % signals, the whole change is rolled back and the caller is told
            % which items refused it.
            previousFs = obj.Fs;
            obj.Fs = value;

            failures = obj.apply_fs_to_bank_;
            if ~isempty(failures)
                obj.Fs = previousFs;
                obj.apply_fs_to_bank_;
                obj.sync_fs_field_;
                obj.update_signal_plot;
                detail = char(strjoin("  " + failures, newline));
                error('stimgen:StimPlayer:SampleRateNotSupported', ...
                    'These bank items cannot be generated at %g Hz:%s%s', ...
                    value, newline, detail);
            end

            obj.sync_fs_field_;
            obj.update_signal_plot;

            % Every bank item stores its rate, so a changed rate is an edit
            % of the bank -- including one adopted from the hardware.
            if value ~= previousFs && ~isempty(obj.StimPlayObjs)
                obj.mark_bank_dirty_;
            end
        end

        % -----------------------------------------------------------------
        function s = get.timeSinceStart(obj)
            a = (now - 719529) * 86400;
            b = (obj.firstTrigTime - 719529) * 86400;
            s = a - b;
        end

    end % methods (public)

end
