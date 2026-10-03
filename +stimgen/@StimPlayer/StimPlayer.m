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
        update_signal_plot(obj)
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
        load_bank(obj, ffn)
        set_control_visibility(obj, options)
        set_computing_(obj, tf)
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
        end

        % -----------------------------------------------------------------
        function s = get.timeSinceStart(obj)
            a = (now - 719529) * 86400;
            b = (obj.firstTrigTime - 719529) * 86400;
            s = a - b;
        end

        % -----------------------------------------------------------------
        function idx = select_next_idx(obj)
            % select_next_idx() - Pick the next bank index using SerialType scheduling.
            % Returns -1 when all bank items have reached their rep target.
            %
            % Returns:
            %   idx - index into StimPlayObjs, or -1 if session complete

            if isempty(obj.StimPlayObjs)
                idx = -1;
                return
            end

            presented = arrayfun(@(sp) sp.StimPresented, obj.StimPlayObjs);
            totals    = arrayfun(@(sp) sp.StimTotal,     obj.StimPlayObjs);
            remaining = totals - presented;

            if all(remaining <= 0)
                idx = -1;
                return
            end

            candidates = find(remaining > 0);

            switch obj.SelectionType
                case "Serial"
                    idx = candidates(1);
                case "Shuffle"
                    idx = candidates(randperm(numel(candidates), 1));
            end
        end

        % -----------------------------------------------------------------
        function sp = selected_or_current_spobj_(obj)
            % sp = selected_or_current_spobj_() - Bank item the GUI is showing.
            % Prefers the listbox selection when idle and falls back to the
            % playback cursor, so every view of "the current stimulus" (signal
            % plot, inspector) agrees.
            %
            % Returns:
            %   sp - stimgen.StimPlay, or [] when the bank is empty

            sp = [];
            h  = obj.handles;
            if isfield(h, 'BankList') && ~isempty(h.BankList) && isvalid(h.BankList) && ...
                    ~isempty(h.BankList.Value)
                idx = h.BankList.Value;
                if idx >= 1 && idx <= numel(obj.StimPlayObjs)
                    sp = obj.StimPlayObjs(idx);
                end
            end
            if isempty(sp)
                sp = obj.CurrentSPObj;
            end
        end

        % -----------------------------------------------------------------
        function [stimObj, label] = inspector_source_(obj)
            % [stimObj, label] = inspector_source_() - Source provider for StimInspector.
            % Handed to stimgen.StimInspector.set_source_provider so the
            % inspector re-resolves the selection on every refresh instead of
            % holding a stale stimulus handle.

            stimObj = [];
            label   = "";

            sp = obj.selected_or_current_spobj_();
            if isempty(sp)
                return
            end

            stimObj = sp.CurrentStimObj;
            label   = sp.Name;
        end

        % -----------------------------------------------------------------
        function refresh_inspector_(obj)
            % refresh_inspector_() - Push the current selection to the inspector.
            % No-op when the inspector window is closed. Failures are logged
            % rather than raised: an inspector problem must not break editing.

            if isempty(obj.Inspector) || ~isvalid(obj.Inspector) || ~obj.Inspector.is_open()
                return
            end
            try
                obj.Inspector.refresh();
            catch ME
                stimgen.util.vprintf(1, 1, ...
                    'StimPlayer: stimulus inspector refresh failed: %s', ME.message);
            end
        end

        % -----------------------------------------------------------------
        function adapter = resolve_capture_adapter_(obj)
            % adapter = resolve_capture_adapter_() - The hardware capture_stim records through.
            % CaptureAdapter when one is set (calling it when it is a
            % function), else the host's calibration adapter -- the same one
            % hardware preview uses, connected on demand. Errors when there
            % is neither, since a capture through nothing is not a capture.
            adapter = obj.CaptureAdapter;
            if isa(adapter, 'function_handle')
                adapter = adapter();
                if ~(isa(adapter, 'stimgen.calibration.HwAdapter') && isscalar(adapter))
                    error('stimgen:StimPlayer:BadCaptureAdapter', ...
                        ['The CaptureAdapter function returned a %s, not a ' ...
                         'stimgen.calibration.HwAdapter.'], class(adapter));
                end
            end
            if ~isempty(adapter)
                return
            end
            if ~isempty(obj.Host)
                adapter = obj.resolve_preview_adapter_;
                return
            end
            error('stimgen:StimPlayer:NoCaptureHardware', ...
                ['No capture hardware: set CaptureAdapter to a ' ...
                 'stimgen.calibration.HwAdapter (or a function returning one), ' ...
                 'or open StimPlayer from a host that supplies a calibration adapter.']);
        end

        % -----------------------------------------------------------------
        function [calObj, source] = capture_calibration_(obj, stimObj)
            % [calObj, source] = capture_calibration_(stimObj) - The scale a capture is read on.
            % The stimulus's own calibration first -- it is the one that set
            % the level being checked -- then the one loaded into the player.
            % Only a calibration with measured tables counts: an empty one
            % (the default every stimulus is born with) carries the 1 V/Pa
            % placeholder sensitivity, and reading a recording through that
            % would print numbers that look like dB SPL and are not.
            %
            % Returns:
            %   calObj - stimgen.StimCalibration, or [] when there is none
            %   source - (1,1) string, the file it came from, "embedded" for
            %            one carried in the bank, "" when there is none
            calObj = [];
            source = "";
            candidates = {stimObj.Calibration, obj.Calibration};
            for k = 1:numel(candidates)
                C = candidates{k};
                if isa(C, 'stimgen.StimCalibration') && isscalar(C) && isvalid(C) ...
                        && C.Engine.IsCalibrated
                    calObj = C;
                    break
                end
            end
            if isempty(calObj)
                return
            end
            fromPlayer = isa(obj.Calibration, 'stimgen.StimCalibration') ...
                && isscalar(obj.Calibration) && calObj == obj.Calibration;
            if fromPlayer && strlength(obj.CalibrationFile) > 0
                source = obj.CalibrationFile;
            else
                source = "embedded";
            end
        end

        % -----------------------------------------------------------------
        function show_capture_inspector_(obj, rec, label)
            % show_capture_inspector_(rec, label) - Show a capture in its own inspector.
            % One per player, reused for each new capture and kept apart from
            % the inspector that follows the bank selection: that one shows
            % what will be played, this one what came back.
            insp = obj.CaptureInspector_;
            if isempty(insp) || ~isvalid(insp) || ~insp.is_open()
                insp = stimgen.StimInspector();
                obj.CaptureInspector_ = insp;
            end
            insp.set_source(rec, label);
            insp.show();
        end

        % -----------------------------------------------------------------
        function sync_capture_controls_(obj)
            % sync_capture_controls_() - Enable capture only when it can run.
            % It needs a route to record through, no session holding the
            % hardware (running or paused), and no capture already in
            % progress. The tooltip says when the route is what is missing,
            % since a greyed button cannot.
            h = obj.handles;
            hasRoute = ~isempty(obj.CaptureAdapter) || ~isempty(obj.Host);
            enable   = hasRoute && ~obj.CaptureLocked_ && ~obj.Capturing_;

            if hasRoute
                tipText = stimgen.util.tooltip('StimPlayer', 'CaptureStimTool');
            else
                tipText = stimgen.util.tooltip('StimPlayer', 'CaptureNoHardware');
            end

            for f = ["CaptureStimTool", "CaptureStimMenu"]
                if isfield(h, f) && ~isempty(h.(f)) && isvalid(h.(f))
                    h.(f).Enable = matlab.lang.OnOffSwitchState(enable);
                end
            end
            if isfield(h, 'CaptureStimTool') && ~isempty(h.CaptureStimTool) && isvalid(h.CaptureStimTool)
                h.CaptureStimTool.Tooltip = tipText;
            end
        end

        % -----------------------------------------------------------------
        function capture_finished_(obj)
            % capture_finished_() - Clear the in-progress flag after a capture.
            % Called from capture_stim's onCleanup, so an error or an
            % interrupted acquisition cannot leave capture disabled for good.
            obj.Capturing_ = false;
            obj.sync_capture_controls_;
        end

        % -----------------------------------------------------------------
        function load_capture_settings_(obj)
            % load_capture_settings_() - Restore the capture timing last chosen.
            % Round-trip latency is a property of the rig, so the lead-in and
            % tail that suit one are kept between sessions. Each value is
            % applied on its own: one that no longer validates leaves that
            % setting at its default rather than costing the rest.
            try
                if ~ispref('StimPlayer', 'CaptureSettings')
                    return
                end
                s = getpref('StimPlayer', 'CaptureSettings');
            catch
                return
            end
            if ~isstruct(s) || ~isscalar(s)
                return
            end
            map = {'PreDelay', 'CapturePreDelay'; 'PostDelay', 'CapturePostDelay'; ...
                   'Repeats', 'CaptureRepeats'};
            for k = 1:size(map, 1)
                if isfield(s, map{k, 1})
                    try
                        obj.(map{k, 2}) = s.(map{k, 1});
                    catch ME
                        stimgen.util.vprintf(3, 'StimPlayer: not restoring %s: %s', ...
                            map{k, 2}, ME.message);
                    end
                end
            end
        end

        % -----------------------------------------------------------------
        function save_capture_settings_(obj)
            % save_capture_settings_() - Remember the capture timing for the next session.
            % Written only when the user changes it in the settings dialog,
            % never from the property setters, so a script driving the player
            % does not rewrite somebody's preferences.
            try
                setpref('StimPlayer', 'CaptureSettings', struct( ...
                    'PreDelay',  obj.CapturePreDelay, ...
                    'PostDelay', obj.CapturePostDelay, ...
                    'Repeats',   obj.CaptureRepeats));
            catch ME
                stimgen.util.vprintf(1, 1, 'StimPlayer: could not save capture settings: %s', ME.message);
            end
        end

        % -----------------------------------------------------------------
        function resolve_params_(obj)
            % resolve_params_() - Populate PARAMS from the host.
            % Called at Run time. Silently skips missing parameters.
            obj.PARAMS = struct;
            if isempty(obj.Host)
                return
            end
            names = obj.RequiredParams_;
            for k = 1:numel(names)
                P = obj.Host.findParameter(names{k});
                if ~isempty(P)
                    obj.PARAMS.(names{k}) = P;
                end
            end
        end

        % -----------------------------------------------------------------
        function reason = hardware_unavailable_reason_(obj)
            % reason = hardware_unavailable_reason_() - Why a Run would have no hardware output.
            % "" when HardwareAvailable is true or no host is attached.
            reason = "";
            if isempty(obj.Host) || obj.HardwareAvailable
                return
            end
            if ~obj.Host.hasProtocol()
                reason = "No protocol is loaded, so no hardware is connected.";
            elseif obj.Host.connectionState() == "None"
                reason = "The hardware is not connected.";
            else
                missing = string(obj.RequiredParams_(~isfield(obj.PARAMS, obj.RequiredParams_)));
                reason = "The loaded circuit does not expose these parameters: " + ...
                    strjoin(missing, ", ") + ".";
            end
        end

        % -----------------------------------------------------------------
        function require_run_hardware_(obj)
            % require_run_hardware_() - Error when a hardware run has lost its hardware.
            % A run that started with hardware output must not carry on as a
            % silent dry run because a parameter or the connection went
            % away: the presentation log would record trials nobody heard.
            % No-op for a run that started without hardware (confirmed as
            % a dry run, or offline).
            if obj.HardwareRun_ && ~obj.HardwareAvailable
                error('stimgen:StimPlayer:HardwareLost', ...
                    'Hardware output was lost during the run after %d of %d presentations. %s', ...
                    obj.presented_count_(), obj.total_count_(), char(obj.hardware_unavailable_reason_()));
            end
        end

        % -----------------------------------------------------------------
        function load_protocol_(obj, protocolInput)
            % load_protocol_(obj) - Prompt for a protocol file and load it.
            % load_protocol_(obj, protocolInput) - Load a protocol object or file.
            % Protocol handling is delegated entirely to the attached host.

            if ~isempty(obj.Timer) && isvalid(obj.Timer) && strcmp(obj.Timer.Running, 'on')
                obj.show_gui_message_("Stop playback before loading a new protocol.", ...
                    "Protocol In Use", "warning");
                return
            end

            if isempty(obj.Host)
                obj.show_gui_message_("No hardware host is attached; speaker preview only.", ...
                    "No Hardware Host", "warning");
                return
            end

            if nargin < 2 || isempty(protocolInput)
                [fn, pn] = uigetfile({'*.eprot;*.prot;*.json', 'Protocol files (*.eprot,*.prot,*.json)'}, ...
                    'Load Protocol', obj.DataPath);
                if isequal(fn, 0)
                    return
                end
                protocolInput = fullfile(pn, fn);
            elseif (ischar(protocolInput) || isstring(protocolInput)) && ~isfile(protocolInput)
                % A remembered path whose file has since moved or been deleted.
                obj.forget_recent_protocol_(protocolInput);
                obj.set_status_("Protocol file not found: " + string(protocolInput), isError=true);
                return
            end

            obj.disconnect_interfaces_;

            try
                obj.Host.loadProtocol(protocolInput);

                % Track the containing folder so later file dialogs open there.
                if (ischar(protocolInput) || isstring(protocolInput)) && isfile(protocolInput)
                    obj.DataPath = string(fileparts(char(protocolInput)));
                    obj.remember_recent_protocol_(protocolInput);
                end

                obj.set_status_("Protocol loaded.");
            catch ME
                obj.report_gui_error_(ME, "Load Protocol Error", ...
                    "StimPlayer could not load the selected protocol.");
            end

            obj.update_protocol_status_;
        end

        % -----------------------------------------------------------------
        function initialize_runtime_from_protocol_(obj)
            % initialize_runtime_from_protocol_() - Connect host hardware for playback.

            obj.disconnect_interfaces_;

            if isempty(obj.Host) || ~obj.Host.hasProtocol()
                return
            end

            obj.Host.connect();
            obj.Host.setMode("Preview");
        end

        % -----------------------------------------------------------------
        function disconnect_interfaces_(obj)
            % disconnect_interfaces_() - Return hardware to Idle and clear parameter cache.

            obj.PARAMS = struct();
            obj.PreviewAdapter_ = [];  % its parameter handles die with the interfaces

            if isempty(obj.Host) || obj.Host.connectionState() == "None"
                return
            end

            try
                obj.Host.setMode("Idle");
            catch ME
                stimgen.util.vprintf(0, 1, 'StimPlayer: failed to return interface mode to Idle.');
                stimgen.util.vprintf(0, 1, ME);
            end

            obj.Host.release();
        end

        % -----------------------------------------------------------------
        function require_hardware_host_(obj)
            % require_hardware_host_() - Error unless a hardware host is attached.
            if isempty(obj.Host)
                error('stimgen:StimPlayer:NoHardwareHost', ...
                    ['No hardware host is attached, so only speaker preview ' ...
                    'is available.']);
            end
        end

        % -----------------------------------------------------------------
        function tf = has_hardware_route_(obj)
            % tf = has_hardware_route_() - True when hardware preview can play:
            % an attached host, or a CaptureAdapter to play through instead.
            tf = ~isempty(obj.Host) || ~isempty(obj.CaptureAdapter);
        end

        % -----------------------------------------------------------------
        function require_hardware_route_(obj)
            % require_hardware_route_() - Error unless hardware preview can play.
            if ~obj.has_hardware_route_
                error('stimgen:StimPlayer:NoHardwareHost', ...
                    ['No hardware host or CaptureAdapter is attached, so only ' ...
                    'speaker preview is available.']);
            end
        end

        % -----------------------------------------------------------------
        function on_playback_output_changed_(obj)
            % on_playback_output_changed_() - React to a committed preview-output switch.
            % Syncs the dropdown (for programmatic assignment) and refreshes
            % the calibration status label, whose meaning depends on the
            % route. Nothing here may throw: the value is already committed.
            % (The hardware rate is adopted by set.PlaybackOutput, before.)

            h = obj.handles;
            if isfield(h, 'OutputDD') && ~isempty(h.OutputDD) && isvalid(h.OutputDD)
                h.OutputDD.Value = obj.PlaybackOutput;
            end

            if obj.PlaybackOutput == "Hardware"
                obj.set_status_("Preview output: calibrated hardware.");
            else
                obj.set_status_("Preview output: computer speakers.");
            end

            obj.update_calibration_status_;
        end

        % -----------------------------------------------------------------
        function adapter = resolve_preview_adapter_(obj)
            % adapter = resolve_preview_adapter_() - Hardware route for preview.
            % Returns the cached stimgen.calibration.HwAdapter, building one
            % from the host when needed. If the host has a protocol loaded
            % but nothing connected yet, it is connected and put in Preview
            % mode first — the same steps a Run performs.
            %
            % Errors (with the host's own diagnostic) when no interface
            % exposes the calibration playback tags.
            %
            % With no host, the route is CaptureAdapter -- resolved afresh
            % each time and never cached here, since a function handle is
            % there precisely so the adapter follows the application's
            % current device settings.

            if isempty(obj.Host)
                obj.require_hardware_route_;
                adapter = obj.resolve_capture_adapter_;
                return
            end

            if ~isempty(obj.PreviewAdapter_) && isvalid(obj.PreviewAdapter_)
                adapter = obj.PreviewAdapter_;
                return
            end

            try
                adapter = obj.Host.calibrationAdapter();
            catch firstME
                if obj.Host.hasProtocol() && obj.Host.connectionState() == "None"
                    obj.Host.connect();
                    obj.Host.setMode("Preview");
                    obj.update_protocol_status_;
                    adapter = obj.Host.calibrationAdapter();
                else
                    rethrow(firstME);
                end
            end

            obj.PreviewAdapter_ = adapter;
        end

        % -----------------------------------------------------------------
        function play_via_hardware_(obj, stimObj)
            % play_via_hardware_(obj, stimObj) - Play Signal through host hardware.
            % The waveform is played verbatim — no normalization — so a
            % calibrated stimulus drives the output at its calibrated
            % voltage. Blocks until the hardware finishes so Play All can
            % pace combinations and Stop takes effect between them.
            %
            % Two hardware contracts can carry a preview, and a circuit
            % typically exposes only one of them. The player's own playback
            % tags (BufferData_0, BufferSize_0, x_Trigger_0 — the Run
            % contract) are preferred, so a preview exercises the exact
            % route a Run will use. When they are absent, playback falls
            % back to the host's calibration adapter (BufferOut/BufferIn
            % circuits), whose play_and_record return is discarded. With no
            % host, CaptureAdapter is played through the same way.

            if ~isempty(obj.Timer) && isvalid(obj.Timer) && strcmp(obj.Timer.Running, 'on')
                error('stimgen:StimPlayer:PreviewDuringRun', ...
                    'Stop the running session before previewing through hardware.');
            end

            obj.require_hardware_route_;
            if ~isempty(obj.Host)
                obj.ensure_host_connected_;
            end

            signal = double(stimObj.Signal);
            peak = max(abs(signal));
            if peak > 10
                error('stimgen:StimPlayer:PreviewVoltageOutOfRange', ...
                    'The waveform peaks at %.2f V, beyond the +/-10 V output range.', peak);
            end

            if isempty(fieldnames(obj.PARAMS)) && ~isempty(obj.Host)
                obj.resolve_params_;
            end

            if obj.HardwareAvailable
                obj.check_preview_rate_(double(obj.Host.sampleRate()), stimObj.Fs);

                % Same write sequence as update_buffer/trigger_stim_playback,
                % pinned to slot 0: the Run timer is stopped, so the
                % double-buffer cursor is not in play.
                buffer = [0, signal(:).', 0];
                obj.PARAMS.BufferSize_0.Value = numel(buffer);
                obj.PARAMS.BufferData_0.Value = buffer;
                obj.PARAMS.x_Trigger_0.Value = 1;
                obj.PARAMS.x_Trigger_0.Value = 0;

                % The trigger returns immediately; hold here for the signal
                % duration to keep the blocking contract stated above.
                pause(numel(signal) / stimObj.Fs);
                return
            end

            adapter = obj.resolve_preview_adapter_;
            obj.check_preview_rate_(double(adapter.sample_rate()), stimObj.Fs);
            adapter.play_and_record(signal(:).');
        end

        % -----------------------------------------------------------------
        function ensure_host_connected_(obj)
            % ensure_host_connected_() - Connect a loaded-but-idle host.
            % The same steps a Run performs: connect the interfaces and put
            % them in Preview mode. No-op without a protocol or when
            % already connected.
            if obj.Host.hasProtocol() && obj.Host.connectionState() == "None"
                obj.Host.connect();
                obj.Host.setMode("Preview");
                obj.update_protocol_status_;
            end
        end

        % -----------------------------------------------------------------
        function check_preview_rate_(~, hwFs, stimFs)
            % check_preview_rate_(hwFs, stimFs) - Refuse a rate-mismatched preview.
            if isfinite(hwFs) && hwFs > 0 && abs(hwFs - stimFs) > 0.5
                error('stimgen:StimPlayer:HardwareRateMismatch', ...
                    'The hardware plays at %.2f Hz but this stimulus was generated at %.2f Hz.', ...
                    hwFs, stimFs);
            end
        end

        % -----------------------------------------------------------------
        function tf = stim_has_calibration_(~, stimObj)
            % tf = stim_has_calibration_(stimObj) - True when the stimulus
            % carries usable calibration data that it is set to apply.
            C  = stimObj.Calibration;
            tf = stimObj.ApplyCalibration && ...
                isa(C, 'stimgen.StimCalibration') && ~isempty(C.CalibrationData);
        end

        % -----------------------------------------------------------------
        function update_calibration_status_(obj)
            % update_calibration_status_() - Refresh the calibration status label.
            % The label answers two questions at once: is a calibration in
            % use, and does the selected preview output actually reproduce
            % it. Speaker preview normalizes to unit peak, so a loaded
            % calibration shapes hardware output only — the label goes
            % amber, not green, while speakers are selected.

            h = obj.handles;
            if ~isfield(h, 'CalibrationStatusLabel') || isempty(h.CalibrationStatusLabel) ...
                    || ~isvalid(h.CalibrationStatusLabel)
                return
            end

            nItems  = numel(obj.StimPlayObjs);
            nActive = 0;
            for i = 1:nItems
                if obj.stim_has_calibration_(obj.StimPlayObjs(i).StimObj)
                    nActive = nActive + 1;
                end
            end

            COLOR_ACTIVE   = [0.00 0.55 0.20];  % calibration reproduced by current output
            COLOR_BYPASSED = [0.80 0.50 0.05];  % calibration present but output ignores levels
            COLOR_NONE     = [0.75 0.15 0.15];  % no calibration at all

            loaded = isa(obj.Calibration, 'stimgen.StimCalibration') && ...
                ~isempty(obj.Calibration.CalibrationData);

            if loaded || nActive > 0
                if loaded && strlength(obj.CalibrationFile) > 0
                    [~, fn, ext] = fileparts(char(obj.CalibrationFile));
                    srcName = string([fn ext]);
                else
                    srcName = "embedded";
                end
                displayName = srcName;
                if strlength(displayName) > 22
                    displayName = extractBefore(displayName, 21) + "...";
                end

                tipText = "Calibration: " + srcName;
                if strlength(obj.CalibrationFile) > 0
                    tipText = tipText + newline + obj.CalibrationFile;
                end
                if loaded
                    ts = obj.Calibration.CalibrationTimestamp;
                    if ~isempty(ts)
                        tipText = tipText + newline + "Measured: " + string(ts);
                    end
                    calFs = obj.Calibration.Fs;
                    if isscalar(calFs) && isfinite(calFs) && calFs > 0 && abs(calFs - obj.Fs) > 0.5
                        tipText = tipText + newline + sprintf( ...
                            'WARNING: calibration was measured at %g Hz but the bank plays at %g Hz.', ...
                            calFs, obj.Fs);
                    end
                end
                tipText = tipText + newline + ...
                    sprintf('Applied by %d of %d bank item(s).', nActive, nItems);

                if obj.PlaybackOutput == "Hardware"
                    h.CalibrationStatusLabel.Text      = char("Cal: " + displayName + " > HW");
                    h.CalibrationStatusLabel.FontColor = COLOR_ACTIVE;
                    tipText = tipText + newline + ...
                        "Preview output is the calibrated hardware: calibrated levels are reproduced.";
                else
                    h.CalibrationStatusLabel.Text      = char("Cal: " + displayName + " (speakers)");
                    h.CalibrationStatusLabel.FontColor = COLOR_BYPASSED;
                    tipText = tipText + newline + ...
                        "Preview output is the computer speakers: the signal is normalized " + ...
                        "for audition, so calibrated levels are NOT reproduced. Set Output to " + ...
                        "Calibrated Hardware to hear the calibrated signal.";
                end
                tipText = tipText + newline + ...
                    "A hardware Run always plays the generated (calibrated) waveform.";
            else
                h.CalibrationStatusLabel.Text      = 'No calibration';
                h.CalibrationStatusLabel.FontColor = COLOR_NONE;
                tipText = "No calibration is loaded: stimulus levels are arbitrary. " + ...
                    "Load one from the Calibration menu, or create one with the Calibration GUI.";
            end

            h.CalibrationStatusLabel.Tooltip = char(tipText);
        end

        % -----------------------------------------------------------------
        function lock_bank_controls_(obj, lockState)
            % lock_bank_controls_(obj, lockState) - Enable/disable bank-editing controls.

            h = obj.handles;
            targetState = 'on';
            if lockState
                targetState = 'off';
            end

            fields = {'AddBtn','DuplicateBtn','RemoveBtn','TypeDropdown','BankList','RepsField', ...
                'ISIField','FsField','OrderDD','OutputDD','ComboPrevBtn','ComboNextBtn','LoadProtocolMenu', ...
                'LoadBankMenu','SaveBankMenu','CalibrationMenu','CalibrationGuiMenu', ...
                'RecentProtocolsMenu','RecentBanksMenu','RecentCalibrationsMenu', ...
                'LoadProtocolTool','LoadBankTool','SaveBankTool','CalibrationGuiTool', ...
                'AddStimTool','DuplicateStimTool','RemoveStimTool', ...
                'CombinationsMenu','CombinationsTool', ...
                ... % These step or regenerate the bank items the timer is playing.
                'PlayBtn','PlayAllBtn','PlayTool', ...
                'ExportSignalMenu','ExportAllMenu','ExportObjsMenu'};
            for i = 1:numel(fields)
                f = fields{i};
                if isfield(h, f) && ~isempty(h.(f)) && isvalid(h.(f))
                    h.(f).Enable = targetState;
                end
            end

            if isfield(h, 'ParamPanel') && ~isempty(h.ParamPanel) && isvalid(h.ParamPanel)
                children = findall(h.ParamPanel);
                for i = 1:numel(children)
                    if isprop(children(i), 'Enable')
                        children(i).Enable = targetState;
                    end
                end
            end

            % Capture follows the same lock -- a session paused is still a
            % session holding the hardware -- but decides the rest for
            % itself: unlocking must not enable it on a player with nothing
            % to record through.
            obj.CaptureLocked_ = lockState;
            obj.sync_capture_controls_;
        end

        % -----------------------------------------------------------------
        function apply_control_visibility_(obj)
            % apply_control_visibility_() - Push ControlVisibility onto the GUI.
            % Hidden widgets are made invisible and their grid row/column is
            % collapsed to zero so no empty space is left behind.

            h   = obj.handles;
            vis = obj.ControlVisibility;

            % Bank panel rows: {visibility field, widgets, row index field}
            rows = { ...
                'Reps',       {'RepsLabel','RepsField'},     'RepsRow'; ...
                'ISI',        {'ISILabel','ISIField'},       'ISIRow'; ...
                'SampleRate', {'FsLabel','FsField'},         'FsRow'; ...
                'PlayMode',   {'OrderDD'},                   'OrderRow'; ...
                'Output',     {'OutputLabel','OutputDD'},    'OutputRow'};

            if isfield(h,'BankGrid') && ~isempty(h.BankGrid) && isvalid(h.BankGrid)
                heights = h.BankGrid.RowHeight;
                for i = 1:size(rows,1)
                    show = vis.(rows{i,1});
                    obj.set_widgets_visible_(rows{i,2}, show);
                    if ~isfield(h, rows{i,3}), continue; end
                    r = h.(rows{i,3});
                    if show
                        heights{r} = h.BankGridRowHeight{r};
                    else
                        heights{r} = 0;
                    end
                end
                h.BankGrid.RowHeight = heights;
            end

            % Playback bar columns: {visibility field, widget, column index field}
            cols = { ...
                'Run',   'RunBtn',   'RunCol'; ...
                'Pause', 'PauseBtn', 'PauseCol'};

            if isfield(h,'ControlGrid') && ~isempty(h.ControlGrid) && isvalid(h.ControlGrid)
                widths = h.ControlGrid.ColumnWidth;
                for i = 1:size(cols,1)
                    show = vis.(cols{i,1});
                    obj.set_widgets_visible_(cols(i,2), show);
                    if ~isfield(h, cols{i,3}), continue; end
                    c = h.(cols{i,3});
                    if show
                        widths{c} = h.ControlGridColumnWidth{c};
                    else
                        widths{c} = 0;
                    end
                end
                h.ControlGrid.ColumnWidth = widths;
            end
        end

        % -----------------------------------------------------------------
        function set_widgets_visible_(obj, fieldNames, show)
            % set_widgets_visible_(fieldNames, show) - Toggle Visible on handles.
            state = 'off';
            if show
                state = 'on';
            end
            for i = 1:numel(fieldNames)
                f = fieldNames{i};
                if isfield(obj.handles, f) && ~isempty(obj.handles.(f)) && isvalid(obj.handles.(f))
                    obj.handles.(f).Visible = state;
                end
            end
        end

        % -----------------------------------------------------------------
        function update_protocol_status_(obj)
            % update_protocol_status_() - Refresh protocol/hardware status label.

            h = obj.handles;
            if ~isfield(h, 'ProtocolStatusLabel') || isempty(h.ProtocolStatusLabel) || ~isvalid(h.ProtocolStatusLabel)
                return
            end

            if isempty(obj.Host) || ~obj.Host.hasProtocol()
                if isempty(obj.Host) && ~isempty(obj.CaptureAdapter)
                    h.ProtocolStatusLabel.Text = 'Protocol: none | HW: capture adapter';
                else
                    h.ProtocolStatusLabel.Text = 'Protocol: none | HW: speaker preview only';
                end
                return
            end

            switch obj.Host.connectionState()
                case "Ready",    hwState = "Ready";
                case "Partial",  hwState = "Partial";
                otherwise,       hwState = "Not Connected";
            end

            h.ProtocolStatusLabel.Text = sprintf('Protocol: %s | HW: %s', ...
                obj.Host.protocolName(), hwState);
        end

        % -----------------------------------------------------------------
        function failures = apply_fs_to_bank_(obj)
            % failures = apply_fs_to_bank_() - Write obj.Fs onto every bank item.
            % StimType.Fs is AbortSet, so items already at this rate are left
            % alone and only the rest pay for a signal regeneration.
            %
            % The regeneration triggered by the assignment runs inside a
            % PostSet listener, where MATLAB downgrades an error to a warning
            % and leaves the old signal in place. update_signal is therefore
            % called again here, where a failure is catchable — the same
            % assign-then-rebuild pattern the parameter editor uses.
            %
            % Returns:
            %   failures - (:,1) string, one "Name: reason" per item that
            %              could not be generated at the new rate

            failures = string.empty(0,1);
            if isempty(obj.StimPlayObjs)
                return
            end

            obj.set_computing_(true);
            computingCleanup = onCleanup(@() obj.set_computing_(false));

            % Silence the listener's own stack dump for the assignment below:
            % the rebuild that follows it raises the same failure where it can
            % be caught and reported as one readable message.
            warnState   = warning('off', 'MATLAB:callback:PropertyEventError');
            warnCleanup = onCleanup(@() warning(warnState));

            for i = 1:numel(obj.StimPlayObjs)
                sp = obj.StimPlayObjs(i);
                try
                    sp.Fs = obj.Fs;
                    sp.update_signal;
                catch ME
                    failures(end+1,1) = sp.Name + ": " + string(ME.message);
                end
            end
            clear computingCleanup warnCleanup;
        end

        % -----------------------------------------------------------------
        function sync_fs_field_(obj)
            % sync_fs_field_() - Show the current rate in the sample rate field.
            h = obj.handles;
            if ~isfield(h, 'FsField') || isempty(h.FsField) || ~isvalid(h.FsField)
                return
            end
            h.FsField.Value = obj.Fs;
        end

        % -----------------------------------------------------------------
        function adopt_host_fs_(obj)
            % adopt_host_fs_() - Take the sample rate from the attached host.
            % Called at Run time: the converter rate is the hardware's to
            % decide, so a host that knows it overrides whatever was typed.
            % Hosts predating stimgen.HardwareHost.sampleRate, or that cannot
            % determine a rate, leave the bank untouched.

            if isempty(obj.Host)
                return
            end

            try
                hostFs = double(obj.Host.sampleRate());
            catch ME
                stimgen.util.vprintf(1, 1, ...
                    'StimPlayer: host could not report a sample rate: %s', ME.message);
                return
            end

            if ~isscalar(hostFs) || ~isfinite(hostFs) || hostFs <= 0 || hostFs == obj.Fs
                return
            end

            previousFs = obj.Fs;
            obj.Fs = hostFs;
            stimgen.util.vprintf(1, 'StimPlayer: sample rate set from hardware: %g Hz (was %g Hz).', ...
                hostFs, previousFs);
            obj.set_status_(sprintf('Sample rate set from hardware: %g Hz.', hostFs));
        end

        % -----------------------------------------------------------------
        function load_calibration_(obj, ffn)
            % load_calibration_(obj) - Prompt for a calibration file and apply it.
            % load_calibration_(obj, ffn) - Apply a calibration file by path.
            % The calibration is applied to every item currently in the bank.

            if nargin < 2 || isempty(ffn)
                [fn, pn] = uigetfile( ...
                    {'*.esgc;*.sgc','Calibration Files (*.esgc, *.sgc)'; ...
                     '*.esgc','EPsych Stim Calibration (*.esgc)'; ...
                     '*.sgc','Legacy Calibration (*.sgc)'}, ...
                    'Select Calibration File', obj.DataPath);
                if isequal(fn, 0), return; end
                ffn = fullfile(pn, fn);
            elseif ~isfile(ffn)
                obj.forget_recent_calibration_(ffn);
                obj.set_status_("Calibration file not found: " + string(ffn), isError=true);
                return
            end

            ffn = char(ffn);
            try
                [~, ~, ext] = fileparts(ffn);

                if strcmpi(ext, '.esgc')
                    calObj = stimgen.StimCalibration();
                    calObj.load_calibration(ffn);
                else
                    cal = load(ffn, '-mat');
                    fields = fieldnames(cal);
                    if isempty(fields)
                        error('StimPlayer:InvalidCalibrationFile', ...
                            'The selected calibration file did not contain any variables.');
                    end

                    raw = cal.(fields{1});
                    if isa(raw, 'stimgen.StimCalibration')
                        calObj = raw;
                    elseif isstruct(raw)
                        calObj = stimgen.StimCalibration.loadobj(raw);
                    else
                        error('StimPlayer:InvalidCalibrationFile', ...
                            'The selected calibration file did not contain a usable calibration object.');
                    end
                end

                for i = 1:numel(obj.StimPlayObjs)
                    obj.StimPlayObjs(i).StimObj.Calibration = calObj;
                end
                obj.Calibration     = calObj;
                obj.CalibrationFile = string(ffn);
                obj.remember_recent_calibration_(ffn);
                stimgen.util.vprintf(1, 'Calibration applied to %d bank items.', numel(obj.StimPlayObjs));
                statusText = "Calibration applied to " + string(numel(obj.StimPlayObjs)) + " bank item(s).";
                if obj.PlaybackOutput == "Speakers" && obj.has_hardware_route_
                    statusText = statusText + " Set Output to Calibrated Hardware to preview at calibrated levels.";
                end
                obj.set_status_(statusText);
            catch ME
                obj.report_gui_error_(ME, "Calibration Error", ...
                    "StimPlayer could not load or apply the selected calibration file.");
            end
            obj.update_calibration_status_;
        end

        % -----------------------------------------------------------------
        function refresh_recent_menus_(obj)
            % refresh_recent_menus_() - Rebuild all three Recent submenus.
            obj.refresh_recent_menu_('RecentProtocolsMenu', 'RecentProtocols', ...
                @(p) obj.load_protocol_(p));
            obj.refresh_recent_menu_('RecentBanksMenu', 'RecentBanks', ...
                @(p) obj.load_bank(p));
            obj.refresh_recent_menu_('RecentCalibrationsMenu', 'RecentCalibrations', ...
                @(p) obj.load_calibration_(p));
        end

        % -----------------------------------------------------------------
        function refresh_recent_menu_(obj, handleField, prefName, openFcn)
            % refresh_recent_menu_() - Rebuild one Recent submenu, most recent first.
            if ~isfield(obj.handles, handleField)
                return
            end
            menu = obj.handles.(handleField);
            if isempty(menu) || ~isvalid(menu)
                return
            end
            delete(allchild(menu));

            paths = obj.get_recent_paths_(prefName);
            if isempty(paths)
                uimenu(menu, 'Text', '(None)', 'Enable', 'off');
                return
            end

            for idx = 1:numel(paths)
                filePath = paths{idx};
                [~, fn, ext] = fileparts(filePath);
                uimenu(menu, ...
                    'Text', sprintf('%d. %s%s | %s', idx, fn, ext, filePath), ...
                    'MenuSelectedFcn', @(~,~) openFcn(filePath));
            end
        end

        % -----------------------------------------------------------------
        function remember_recent_protocol_(obj, filePath)
            obj.add_recent_path_('RecentProtocols', filePath);
        end

        function forget_recent_protocol_(obj, filePath)
            obj.remove_recent_path_('RecentProtocols', filePath);
        end

        function remember_recent_bank_(obj, filePath)
            obj.add_recent_path_('RecentBanks', filePath);
        end

        function forget_recent_bank_(obj, filePath)
            obj.remove_recent_path_('RecentBanks', filePath);
        end

        function remember_recent_calibration_(obj, filePath)
            obj.add_recent_path_('RecentCalibrations', filePath);
        end

        function forget_recent_calibration_(obj, filePath)
            obj.remove_recent_path_('RecentCalibrations', filePath);
        end

        % -----------------------------------------------------------------
        function paths = get_recent_paths_(~, prefName)
            % get_recent_paths_() - Read one recent list from stored preferences.
            groupName = 'StimPlayer';
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

        % -----------------------------------------------------------------
        function add_recent_path_(obj, prefName, filePath)
            % add_recent_path_() - Promote a path to the head of a recent list.
            filePath = strtrim(char(filePath));
            if isempty(filePath)
                return
            end
            paths = obj.get_recent_paths_(prefName);
            paths(strcmpi(paths, filePath)) = [];
            paths = [{filePath}, paths];
            paths = paths(1:min(9, numel(paths)));
            setpref('StimPlayer', prefName, paths);
            obj.refresh_recent_menus_;
        end

        % -----------------------------------------------------------------
        function remove_recent_path_(obj, prefName, filePath)
            % remove_recent_path_() - Drop a stale path from a recent list.
            paths = obj.get_recent_paths_(prefName);
            paths(strcmpi(paths, strtrim(char(filePath)))) = [];
            setpref('StimPlayer', prefName, paths);
            obj.refresh_recent_menus_;
        end

        % -----------------------------------------------------------------
        function names = remembered_setting_names_(~, stimObj)
            % remembered_setting_names_() - Properties worth carrying to the next stimulus of a type.
            % The settings a user tunes: level, timing, window, variant
            % policy, and the type's own parameters. Not Fs (the bank owns
            % the rate) and not Catalog / FileIndex (a file list and indices
            % into it mean nothing to a new item that has no files yet).
            base = ["SoundLevel","Duration","WindowDuration","WindowFcn", ...
                    "ApplyCalibration","ApplyWindow", ...
                    "VariantSelectionMode","VariantCombinationMode", ...
                    "VariantSelectorClass","VariantSelectorConfig", ...
                    "VariantReselectOnUpdate"];
            names = unique([base, stimObj.UserProperties], 'stable');
            names = names(~ismember(names, ["Catalog","FileIndex"]));
            has = false(size(names));
            for k = 1:numel(names)
                has(k) = isprop(stimObj, char(names(k)));
            end
            names = names(has);
        end

        % -----------------------------------------------------------------
        function remember_stim_settings_(obj, stimObj)
            % remember_stim_settings_(stimObj) - Keep this stimulus's settings for its type.
            % The whole set is snapshotted, not just the property edited:
            % some properties change the meaning of others (Tone's
            % WindowMethod sets the units of WindowDuration), so a value
            % remembered alone can come back describing something else.
            % Stored per type in the StimPlayer pref group, so it applies to
            % the next Add Stim in this window and to later sessions alike.
            % Remembering is a convenience and never interrupts an edit.
            try
                key = matlab.lang.makeValidName(class(stimObj));
                S = struct();
                names = obj.remembered_setting_names_(stimObj);
                for k = 1:numel(names)
                    v = stimObj.(names(k));
                    % Plain values only: handles and objects do not survive
                    % a pref round trip meaningfully.
                    if isnumeric(v) || islogical(v) || ischar(v) || isstring(v)
                        S.(names(k)) = v;
                    end
                end
                stored = obj.get_remembered_settings_();
                stored.(key) = S;
                setpref('StimPlayer', 'StimSettings', stored);
            catch ME
                stimgen.util.vprintf(3, 'StimPlayer: could not remember settings: %s', ME.message);
            end
        end

        % -----------------------------------------------------------------
        function stored = get_remembered_settings_(~)
            % get_remembered_settings_() - Every type's remembered settings, keyed by class.
            stored = struct();
            try
                if ispref('StimPlayer', 'StimSettings')
                    s = getpref('StimPlayer', 'StimSettings');
                    if isstruct(s) && isscalar(s)
                        stored = s;
                    end
                end
            catch
                % A pref from another version, or an unreadable one, is the
                % same as none.
            end
        end

        % -----------------------------------------------------------------
        function apply_remembered_settings_(obj, stimObj)
            % apply_remembered_settings_(stimObj) - Start a new stimulus from its type's last settings.
            % Each property is applied on its own, so a value that no longer
            % validates (a limit that has since changed, a property a newer
            % version dropped) leaves that property at its default rather
            % than costing the stimulus the rest.
            stored = obj.get_remembered_settings_();
            key = matlab.lang.makeValidName(class(stimObj));
            if ~isfield(stored, key) || ~isstruct(stored.(key))
                return
            end
            S = stored.(key);
            names = obj.remembered_setting_names_(stimObj);
            for k = 1:numel(names)
                p = char(names(k));
                if ~isfield(S, p)
                    continue
                end
                try
                    stimObj.(p) = S.(p);
                catch ME
                    stimgen.util.vprintf(3, 'StimPlayer: not applying remembered %s: %s', p, ME.message);
                end
            end
        end

        % -----------------------------------------------------------------
        function get_isi_(obj)
            % get_isi_() - Sample a scalar ISI from obj.ISI range.
            % Updates obj.currentISI.
            lo = obj.ISI(1);
            hi = obj.ISI(2);
            if hi > lo
                obj.currentISI = lo + rand * (hi - lo);
            else
                obj.currentISI = lo;
            end
        end

        % -----------------------------------------------------------------
        function update_counter_(obj)
            % update_counter_() - Refresh the stimulus counter label in the GUI.
            h = obj.handles;
            if ~isfield(h,'Counter') || ~isvalid(h.Counter)
                return
            end
            h.Counter.Text = sprintf('%d / %d', obj.presented_count_(), obj.total_count_());
        end

        % -----------------------------------------------------------------
        function n = presented_count_(obj)
            % n = presented_count_() - Presentations so far, summed over the bank.
            n = 0;
            if ~isempty(obj.StimPlayObjs)
                n = sum(arrayfun(@(sp) sp.StimPresented, obj.StimPlayObjs));
            end
        end

        % -----------------------------------------------------------------
        function n = total_count_(obj)
            % n = total_count_() - Presentations a full run makes, summed over the bank.
            n = 0;
            if ~isempty(obj.StimPlayObjs)
                n = sum(arrayfun(@(sp) sp.StimTotal, obj.StimPlayObjs));
            end
        end

        % -----------------------------------------------------------------
        function refresh_listbox_(obj)
            % refresh_listbox_() - Rebuild listbox items from current StimPlayObjs.
            h = obj.handles;
            if ~isfield(h,'BankList') || ~isvalid(h.BankList)
                return
            end
            if isempty(obj.StimPlayObjs)
                h.BankList.Items = {};
                h.BankList.ItemsData = {};
                return
            end
            items = arrayfun(@(sp) sprintf('%s  [%s]', char(sp.Name), sp.Type), ...
                obj.StimPlayObjs, 'uni', false);
            h.BankList.Items = items;
            h.BankList.ItemsData = num2cell(1:numel(obj.StimPlayObjs));
        end

        % -----------------------------------------------------------------
        function refresh_combo_controls_(obj)
            % refresh_combo_controls_() - Update combo-step button state and label.
            h = obj.handles;
            required = {'ComboPrevBtn','ComboNextBtn','ComboStatusLbl','BankList'};
            if ~all(isfield(h, required))
                return
            end
            if ~isvalid(h.ComboPrevBtn) || ~isvalid(h.ComboNextBtn) || ...
                    ~isvalid(h.ComboStatusLbl) || ~isvalid(h.BankList)
                return
            end

            idx = [];
            if ~isempty(h.BankList.Value) && h.BankList.Value >= 1 && h.BankList.Value <= numel(obj.StimPlayObjs)
                idx = h.BankList.Value;
            end

            COLOR_NORMAL = [0 0 0];
            COLOR_UNEVEN = [0.80 0.50 0.05];

            if isempty(idx)
                h.ComboPrevBtn.Enable = 'off';
                h.ComboNextBtn.Enable = 'off';
                h.ComboStatusLbl.Text = 'Combo: - / -';
                h.ComboStatusLbl.FontColor = COLOR_NORMAL;
                h.ComboStatusLbl.Tooltip   = stimgen.util.tooltip('StimPlayer', 'ComboStatusLbl');
                return
            end

            sp      = obj.StimPlayObjs(idx);
            stimObj = sp.CurrentStimObj;
            info    = stimObj.get_variant_info();

            % How Reps divides over the combinations, so an uneven split is
            % visible while the bank is edited, not only when Run warns.
            [repsText, uneven] = obj.reps_per_combination_(sp.Reps, stimObj);
            if strlength(repsText) > 0
                h.ComboStatusLbl.Text = char(sprintf('Combo: %d / %d | %s', ...
                    info.ActiveIndex, info.NumCombinations, repsText));
            else
                h.ComboStatusLbl.Text = sprintf('Combo: %d / %d', info.ActiveIndex, info.NumCombinations);
            end
            if uneven
                h.ComboStatusLbl.FontColor = COLOR_UNEVEN;
                h.ComboStatusLbl.Tooltip   = stimgen.util.tooltip('StimPlayer', 'ComboStatusLblUneven');
            else
                h.ComboStatusLbl.FontColor = COLOR_NORMAL;
                h.ComboStatusLbl.Tooltip   = stimgen.util.tooltip('StimPlayer', 'ComboStatusLbl');
            end

            % Stepping changes the combination a bank item will present
            % next, so it is closed while a session holds the bank: the
            % buffer for the next trial is already loaded, and the
            % presentation log records the combination it was made from.
            if info.NumCombinations > 1 && ~obj.CaptureLocked_
                h.ComboPrevBtn.Enable = 'on';
                h.ComboNextBtn.Enable = 'on';
            else
                h.ComboPrevBtn.Enable = 'off';
                h.ComboNextBtn.Enable = 'off';
            end
        end

        % -----------------------------------------------------------------
        function [txt, uneven, detail] = reps_per_combination_(~, reps, stimObj)
            % [txt, uneven, detail] = reps_per_combination_(reps, stimObj)
            % How a bank item's Reps divides over its variant combinations.
            %
            % Reps counts presentations of the bank item (of each stimulus
            % object it holds), not of each combination, and a Run makes
            % exactly that many; it is never rounded to a multiple of the
            % combination count. How the presentations fall on combinations
            % depends on the stimulus's VariantSelectionMode:
            %   Serial, ShuffleLeastUsed - balanced: every combination gets
            %       floor(Reps/n) or ceil(Reps/n); uneven when n does not
            %       divide Reps (Serial gives the extra one to 1..mod(Reps,n))
            %   ShuffleUniform - drawn with replacement; counts are random
            %   CustomSelector - whatever the selector decides
            %
            % Returns:
            %   txt    - short label text ("" for a single combination)
            %   uneven - true when a balanced mode cannot balance Reps
            %   detail - one sentence for the Run warning ("" unless uneven)
            txt = "";
            uneven = false;
            detail = "";
            info  = stimObj.get_variant_info();
            nComb = info.NumCombinations;
            if nComb <= 1
                return
            end
            mode = string(stimObj.VariantSelectionMode);
            switch mode
                case {"Serial", "ShuffleLeastUsed"}
                    lo = floor(reps / nComb);
                    hi = ceil(reps / nComb);
                    if lo == hi
                        txt = sprintf("%d reps each", lo);
                    else
                        txt = sprintf("%d-%d reps each", lo, hi);
                        uneven = true;
                        nHi = mod(reps, nComb);
                        detail = sprintf("%d reps over %d combinations (%s): %d combination(s) get %d, %d get %d.", ...
                            reps, nComb, mode, nHi, hi, nComb - nHi, lo);
                        if mode == "Serial"
                            detail = detail + sprintf(" Serial order gives the extra presentation to combinations 1-%d.", nHi);
                        end
                    end
                case "ShuffleUniform"
                    txt = sprintf("~%.3g reps each (random)", reps / nComb);
                otherwise
                    txt = "reps set by selector";
            end
        end

        % -----------------------------------------------------------------
        function lines = uneven_reps_report_(obj)
            % lines = uneven_reps_report_() - Bank items whose Reps a balanced mode cannot split evenly.
            % One "<name>: <detail>" line per affected stimulus, logged as a
            % warning too. Empty when every item divides evenly.
            lines = strings(0, 1);
            for i = 1:numel(obj.StimPlayObjs)
                sp = obj.StimPlayObjs(i);
                for k = 1:numel(sp.StimObj)
                    [~, uneven, detail] = obj.reps_per_combination_(sp.Reps, sp.StimObj(k));
                    if uneven
                        lines(end+1, 1) = string(sp.Name) + ": " + detail; %#ok<AGROW>
                    end
                end
            end
            for i = 1:numel(lines)
                stimgen.util.vprintf(1, 1, 'StimPlayer: uneven reps: %s', char(lines(i)));
            end
        end

        % -----------------------------------------------------------------
        function proceed = confirm_run_(obj)
            % proceed = confirm_run_() - Say what a run will do that may be unexpected; allow a cancel.
            % Called by Run after the hardware is resolved and before the
            % timer exists. Each finding is logged; when there is any, one
            % confirmation dialog lists them all and Cancel (the default)
            % abandons the run. Nothing is changed to make a finding go
            % away -- in particular a run always presents exactly the Reps
            % each bank item asks for.
            %
            % Returns:
            %   proceed - false when the operator cancelled
            issues = strings(0, 1);

            % A host is attached but the run would drive nothing. Without a
            % host the player is offline by construction and says so in its
            % status bar, so that case is not asked about.
            reason = obj.hardware_unavailable_reason_();
            if strlength(reason) > 0
                stimgen.util.vprintf(0, 1, 'StimPlayer: Run has no hardware output: %s', char(reason));
                issues(end+1, 1) = "No hardware output. " + reason + newline + ...
                    "This would be a dry run: the timer runs and the presentation log fills, " + ...
                    "but nothing is played. A hardware Run needs " + ...
                    strjoin(string(obj.RequiredParams_), ", ") + ".";
            end

            uneven = obj.uneven_reps_report_();
            if ~isempty(uneven)
                issues(end+1, 1) = "Reps does not divide evenly over the variant combinations:" + newline + ...
                    strjoin(("  - " + uneven).', newline) + newline + ...
                    "A run presents exactly Reps per bank item, so these combinations will be " + ...
                    "presented unequal numbers of times. Set Reps to a multiple of the " + ...
                    "combination count for equal counts.";
            end

            proceed = true;
            if isempty(issues) || isempty(obj.hFig) || ~isvalid(obj.hFig)
                return
            end
            msg = strjoin(issues.', string(newline) + newline) + newline + newline + "Run anyway?";
            choice = uiconfirm(obj.hFig, char(msg), 'Check Before Running', ...
                'Options', {'Run', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, ...
                'Icon', 'warning');
            proceed = strcmp(choice, 'Run');
        end

        % -----------------------------------------------------------------
        function initialize_variants_(obj)
            % initialize_variants_() - Start each bank item's variant sequence for a run.
            % Every stimulus forgets its selection history
            % (reset_variant_selection: Serial cursor back to combination 1,
            % ShuffleLeastUsed counts zeroed, a custom selector rebuilt) and
            % then makes the first selection of the run through its own
            % VariantSelectionMode, by regenerating outside a variant cycle.
            % Previews and combination stepping before the run therefore do
            % not shape its order, and Serial still starts at combination 1.
            for i = 1:numel(obj.StimPlayObjs)
                sp = obj.StimPlayObjs(i);
                for k = 1:numel(sp.StimObj)
                    stimObj = sp.StimObj(k);
                    stimObj.reset_variant_selection();
                    stimObj.update_signal();
                end
            end
        end

        % -----------------------------------------------------------------
        function advance_variant_(~, stimObj)
            % advance_variant_(stimObj) - Select the next combination of a presented stimulus.
            % update_signal() outside a variant cycle selects through the
            % stimulus's own VariantSelectionMode (Serial, ShuffleUniform,
            % ShuffleLeastUsed or CustomSelector) and regenerates Signal for
            % it, so the next presentation of this stimulus plays that
            % combination. step_variant(1) used to be called here, which
            % pins index+1 and so bypassed every mode but Serial.
            if isempty(stimObj)
                return
            end
            stimObj.update_signal();
        end

        % -----------------------------------------------------------------
        function sgn = claim_polarity_(obj)
            % sgn = claim_polarity_() - Sign for the next presentation.
            % A stimulus that alternates across presentations (see
            % StimType.alternates_polarity) is inverted on every other
            % presentation OF THE SAME VARIANT, so each combination's
            % repetitions are split between the signs whatever order the
            % bank and its variants are visited in. Counting per bank item
            % would not do: two variants of one item presented in turn
            % would each always get the same sign. Called once per
            % presentation, just before it is buffered.
            sgn = 1;
            bankIdx = obj.nextSPOIdx;
            sp = obj.CurrentSPObj;
            if isempty(sp) || bankIdx < 1
                return
            end
            stimObj = sp.CurrentStimObj;
            if ~stimObj.alternates_polarity()
                return
            end
            info = stimObj.get_variant_info();
            v = info.ActiveIndex;
            if numel(obj.PolarityCount_) < bankIdx
                obj.PolarityCount_{bankIdx} = [];
            end
            counts = obj.PolarityCount_{bankIdx};
            if numel(counts) < v
                counts(v) = 0;
            end
            if mod(counts(v), 2) == 1
                sgn = -1;
            end
            counts(v) = counts(v) + 1;
            obj.PolarityCount_{bankIdx} = counts;
        end

        % -----------------------------------------------------------------
        function report_gui_error_(obj, ME, titleText, userMessage)
            % report_gui_error_() - Log an exception and show a user-facing alert.
            arguments
                obj (1,1) stimgen.StimPlayer
                ME (1,1) MException
                titleText (1,1) string = "StimPlayer Error"
                userMessage (1,1) string = "An unexpected error occurred."
            end

            stimgen.util.vprintf(0, 1, '%s: %s', char(titleText), ME.message);
            stimgen.util.vprintf(0, 1, ME);

            detailedMessage = obj.format_gui_error_message_(ME, userMessage);
            obj.set_status_(titleText + ": " + detailedMessage, isError=true);

            if isempty(obj.hFig) || ~isvalid(obj.hFig)
                return
            end

            try
                uialert(obj.hFig, char(detailedMessage), ...
                    char(titleText), 'Icon', 'error');
            catch
                % Avoid cascading GUI failures while reporting an error.
            end
        end

        % -----------------------------------------------------------------
        function show_gui_message_(obj, messageText, titleText, iconName)
            % show_gui_message_() - Best-effort wrapper around uialert.
            arguments
                obj (1,1) stimgen.StimPlayer
                messageText (1,1) string
                titleText (1,1) string = "StimPlayer"
                iconName (1,1) string = "info"
            end

            if isempty(obj.hFig) || ~isvalid(obj.hFig)
                return
            end

            obj.set_status_(titleText + ": " + messageText, isError=iconName == "error");

            try
                if any(iconName == ["error", "success"])
                    uialert(obj.hFig, char(messageText), char(titleText), 'Icon', char(iconName));
                end
            catch
                % Ignore alert failures if the figure is closing.
            end
        end

        % -----------------------------------------------------------------
        function set_status_(obj, messageText, options)
            % set_status_() - Update the non-modal status label in the GUI.
            arguments
                obj (1,1) stimgen.StimPlayer
                messageText (1,1) string
                options.isError (1,1) logical = false
            end

            h = obj.handles;
            if ~isfield(h, 'StatusLabel') || isempty(h.StatusLabel) || ~isvalid(h.StatusLabel)
                return
            end

            h.StatusLabel.Text = char(messageText);
            if options.isError
                h.StatusLabel.FontColor = [0.75 0.15 0.15];
            else
                h.StatusLabel.FontColor = [0.35 0.35 0.35];
            end
        end

        % -----------------------------------------------------------------
        function messageText = format_gui_error_message_(obj, ME, fallbackText)
            % format_gui_error_message_() - Convert common errors into user-facing guidance.
            arguments
                obj (1,1) stimgen.StimPlayer
                ME (1,1) MException
                fallbackText (1,1) string
            end

            if isempty(obj)
                messageText = fallbackText + newline + newline + string(ME.message);
                return
            end

            messageText = fallbackText + newline + newline + string(ME.message);

            switch string(ME.identifier)
                case "StimPlayer:InvalidISI"
                    messageText = "Enter either one positive ISI value in milliseconds, such as 1000, or a two-value range such as [500 1500].";
                case "stimgen:StimPlayer:SampleRateNotSupported"
                    messageText = string(ME.message) + newline + newline + ...
                        "The sample rate is unchanged. A rate change moves the highest frequency that can be represented, so bring the parameters of those stimuli inside the new range first, then set the rate again.";
                case "StimPlayer:InvalidCalibrationFile"
                    messageText = "The selected calibration file did not contain a usable calibration object.";
                case "stimgen:StimPlayer:NoHardwareHost"
                    messageText = "StimPlayer has no hardware to play through, so only speaker preview is available. " + ...
                        "Open StimPlayer from the host application (e.g. EPsych), or set CaptureAdapter " + ...
                        "to a stimgen.calibration.HwAdapter, to play through calibrated hardware.";
                case "stimgen:StimPlayer:HardwareRateMismatch"
                    messageText = string(ME.message) + newline + newline + ...
                        "A waveform generated at one rate plays at the wrong frequencies and duration at another. " + ...
                        "Set the bank Sample Rate to the hardware rate, then preview again.";
                case "stimgen:StimPlayer:PreviewVoltageOutOfRange"
                    messageText = string(ME.message) + newline + newline + ...
                        "Lower the stimulus Sound Level so the calibrated drive voltage fits the output range.";
                case "stimgen:StimPlayer:HardwareLost"
                    messageText = string(ME.message) + newline + newline + ...
                        "The session was stopped rather than continued without output. Check the hardware connection and the loaded protocol, then Run again. StimOrder, StimOrderTime, StimPolarity and StimVariant hold the presentations made before the loss.";
                case "stimgen:StimPlayer:HardwareWriteFailed"
                    messageText = string(ME.message) + newline + newline + ...
                        "The next stimulus could not be loaded into the hardware buffer, so the session was stopped rather than trigger a stale buffer. Check the hardware connection, then Run again.";
                case "stimgen:StimPlayer:PreviewDuringRun"
                    messageText = "The hardware is presenting the bank right now. Stop the session, then preview through hardware.";
                case "stimgen:StimPlayer:CaptureDuringRun"
                    messageText = "A session is holding the hardware (running or paused). Stop it, then capture.";
                case "stimgen:StimPlayer:NoCaptureHardware"
                    messageText = "Capture needs hardware that can play and record at once, with a microphone on its input. " + ...
                        "Set CaptureAdapter to a stimgen.calibration.HwAdapter -- for example " + ...
                        "stimgen.calibration.WindowsSoundCardAdapter -- or a function returning one, " + ...
                        "or open StimPlayer from a host application that supplies a calibration adapter.";
                case "stimgen:StimPlayer:BadCaptureAdapter"
                    messageText = string(ME.message) + newline + newline + ...
                        "CaptureAdapter has to be something capture can play and record through.";
                case "stimgen:StimPlayer:CaptureVoltageOutOfRange"
                    messageText = string(ME.message) + newline + newline + ...
                        "Lower the stimulus Sound Level so the calibrated drive voltage fits the output range.";
                case "stimgen:StimPlayer:EmptyCaptureSignal"
                    messageText = string(ME.message) + newline + newline + ...
                        "Check the stimulus parameters: nothing was generated to play.";
                case "stimgen:util:filterRateMismatch"
                    messageText = string(ME.message) + newline + newline + ...
                        "An equalization filter only corrects the frequencies it was designed for at the sample rate it was designed at. Redesign the filter for this rate in the calibration GUI (Design Filter, ""Design sample rate"" field) -- the measurement itself does not have to be repeated -- or set the sample rate back to the one the calibration was designed at.";
                case "stimgen:StimType:UnknownWindowFcn"
                    messageText = string(ME.message) + newline + newline + ...
                        "Window Shape names a MATLAB window function. Pick one of the listed shapes, or supply a function on the path that takes a length in samples and returns that many window values.";
                case "stimgen:StimType:NonVectorizableProperty"
                    messageText = "This property must stay scalar in StimPlayer. Use a single value rather than a vector or expression that expands to multiple values.";
                case "stimgen:StimType:PairwiseLengthMismatch"
                    messageText = [ ...
                        "Variant lengths do not match the selected combination mode." + newline + ...
                        "Use equal-length vectors for PairwiseStrict, or use scalar-or-max-length vectors for PairwiseScalarExpand." ...
                    ];
                case "stimgen:StimType:MissingSelectorClass"
                    messageText = "Variant Selection is set to CustomSelector, but no selector class was provided.";
                case "stimgen:StimType:SelectorClassNotFound"
                    messageText = "StimPlayer could not find the requested variant selector class on the MATLAB path.";
                case "stimgen:StimType:SelectorClassType"
                    messageText = "The selected variant selector must define both initialize() and selectNext() methods.";
                case "stimgen:StimType:InvalidSelectorIndex"
                    messageText = "The custom selector returned an invalid variant index for the available combinations.";
                case "stimgen:StimType:InvalidCombinationMode"
                    messageText = "The selected variant combination mode is not recognized.";
                case "stimgen:StimType:InvalidSelectionMode"
                    messageText = "The selected variant selection mode is not recognized.";
                case "stimgen:TORC:TemporalOrthogonality"
                    messageText = "Two ripple components landed on the same modulation rate, which is what a TORC exists to avoid. Spread the rates apart, or lengthen Duration to make the rate grid finer.";
                case "stimgen:TORC:RateBelowFundamental"
                    messageText = "Ripple rates cannot be slower than one cycle per ripple period. Raise the rate, lengthen Duration, or reduce Ripple Periods.";
                case "stimgen:TORC:BandwidthExceedsNyquist"
                    messageText = "The highest carrier would exceed half the sample rate. Lower Low Frequency or Bandwidth, or raise Fs.";
                case {"stimgen:TORC:InvalidComponentList", "stimgen:TORC:EmptyComponentList"}
                    messageText = "Enter the ripple components as a list of numbers, such as 4 8 12 16 or 4:4:24.";
                case "stimgen:TORC:InvalidRate"
                    messageText = "Component rates must all be positive. Set the direction of travel with the sign of the ripple density instead.";
                case "stimgen:TORC:InvalidRateRange"
                    messageText = "Highest Rate must be greater than or equal to Lowest Rate.";
                case "stimgen:SoundFile:EmptyCatalog"
                    messageText = "This sound file stimulus has no files yet. Use the Browse... button to add one or more sound files.";
                case {"stimgen:SoundFile:FileNotFound", "stimgen:SoundFile:FileNotReadable"}
                    messageText = [ ...
                        "A sound file referenced by this stimulus could not be read." + newline + ...
                        "It may have been moved, renamed, or deleted. Re-add it with Browse..., or embed the files (embed) so the bank no longer depends on them." + newline + newline + ...
                        string(ME.message) ...
                    ];
                case "stimgen:SoundFile:IndexOutOfRange"
                    messageText = "File Index refers to a file that is not in the catalog. Use the Use All Files button, or enter an index or range within the catalog size.";
                case "stimgen:SoundFile:InvalidChannel"
                    messageText = [ ...
                        "The requested channel does not exist in that sound file." + newline + ...
                        "Use 0 to average all channels to mono, or a channel number within the file." + newline + newline + ...
                        string(ME.message) ...
                    ];
                case "stimgen:SoundFile:WindowTooLong"
                    messageText = [ ...
                        "The onset/offset window is longer than the selected sound file." + newline + ...
                        "Reduce Window Duration, or clear Apply Window." + newline + newline + ...
                        string(ME.message) ...
                    ];
                case "stimgen:SoundFile:NoEqualizer"
                    messageText = "Calibration Mode is set to Filtered, but the loaded calibration has no equalization filter. Design one in the calibration GUI, or set Calibration Mode to Direct.";
                case "stimgen:SoundFile:VoltageOutOfRange"
                    messageText = [ ...
                        "The requested Sound Level would clip the output." + newline + ...
                        "Natural sounds have a high crest factor, so the peak exceeds 10 V well before the RMS level does. Lower Sound Level." + newline + newline + ...
                        string(ME.message) ...
                    ];
                otherwise
                    rawMessage = string(ME.message);
                    if contains(rawMessage, "Expression cannot be empty.")
                        messageText = "Enter a numeric value or MATLAB expression, such as 4000 or 500*2.^(0:3).";
                    elseif contains(rawMessage, "Assignments are not allowed in expressions.")
                        messageText = "Use expressions only. Do not include assignments like Frequency = ....";
                    elseif contains(rawMessage, "Only a single expression is allowed.")
                        messageText = "Enter one expression only. Separate values with spaces or MATLAB vector syntax rather than semicolons.";
                    elseif contains(rawMessage, "must evaluate to a numeric or logical value.")
                        messageText = "That expression did not resolve to numeric values. Try a numeric vector such as [1000 2000 4000] or an expression like 500*2.^(0:3).";
                    elseif contains(rawMessage, "must evaluate to finite numeric values.")
                        messageText = "The expression must evaluate to finite numbers only. Remove NaN, Inf, or divisions by zero.";
                    end
            end
        end

    end % methods (public)

end
