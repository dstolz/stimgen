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
        %                (stimgen.HardwareHost.calibrationAdapter); the
        %                generated waveform is played verbatim, so a loaded
        %                calibration is heard at its calibrated voltage.
        % Selecting "Hardware" requires a host and errors without one.
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

            if nargout == 0, clear obj; end
        end

        % -----------------------------------------------------------------
        function delete(obj)
            % Destructor: stop and clean up timer, listeners and child windows.
            obj.disconnect_interfaces_;
            if ~isempty(obj.Inspector) && isvalid(obj.Inspector)
                delete(obj.Inspector);
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
            required = {'BufferData_0','BufferData_1','BufferSize_0','BufferSize_1', ...
                        'x_Trigger_0','x_Trigger_1'};
            tf = all(isfield(obj.PARAMS, required));
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
            % Route Play / Play All to speakers or to the host's calibration
            % hardware. Selecting hardware without a host is refused up
            % front, so the property never claims a route that cannot play.
            if value == "Hardware"
                obj.require_hardware_host_;
            end
            obj.PlaybackOutput = value;
            obj.on_playback_output_changed_;
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
        function resolve_params_(obj)
            % resolve_params_() - Populate PARAMS from the host.
            % Called at Run time. Silently skips missing parameters.
            obj.PARAMS = struct;
            if isempty(obj.Host)
                return
            end
            names = {'BufferData_0','BufferData_1','BufferSize_0','BufferSize_1', ...
                     'x_Trigger_0','x_Trigger_1'};
            for k = 1:numel(names)
                P = obj.Host.findParameter(names{k});
                if ~isempty(P)
                    obj.PARAMS.(names{k}) = P;
                end
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
        function on_playback_output_changed_(obj)
            % on_playback_output_changed_() - React to a preview-output switch.
            % Syncs the dropdown (for programmatic assignment), adopts the
            % hardware rate when moving onto hardware so the bank is already
            % generated at the rate the converters run at, and refreshes the
            % calibration status label, whose meaning depends on the route.

            h = obj.handles;
            if isfield(h, 'OutputDD') && ~isempty(h.OutputDD) && isvalid(h.OutputDD)
                h.OutputDD.Value = obj.PlaybackOutput;
            end

            if obj.PlaybackOutput == "Hardware"
                obj.adopt_host_fs_;
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

            if ~isempty(obj.PreviewAdapter_) && isvalid(obj.PreviewAdapter_)
                adapter = obj.PreviewAdapter_;
                return
            end

            obj.require_hardware_host_;

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
            % circuits), whose play_and_record return is discarded.

            if ~isempty(obj.Timer) && isvalid(obj.Timer) && strcmp(obj.Timer.Running, 'on')
                error('stimgen:StimPlayer:PreviewDuringRun', ...
                    'Stop the running session before previewing through hardware.');
            end

            obj.require_hardware_host_;
            obj.ensure_host_connected_;

            signal = double(stimObj.Signal);
            peak = max(abs(signal));
            if peak > 10
                error('stimgen:StimPlayer:PreviewVoltageOutOfRange', ...
                    'The waveform peaks at %.2f V, beyond the +/-10 V output range.', peak);
            end

            if isempty(fieldnames(obj.PARAMS))
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

            fields = {'AddBtn','RemoveBtn','TypeDropdown','BankList','RepsField', ...
                'ISIField','FsField','OrderDD','OutputDD','ComboPrevBtn','ComboNextBtn','LoadProtocolMenu', ...
                'LoadBankMenu','SaveBankMenu','CalibrationMenu','CalibrationGuiMenu', ...
                'RecentProtocolsMenu','RecentBanksMenu','RecentCalibrationsMenu', ...
                'LoadProtocolTool','LoadBankTool','SaveBankTool','CalibrationGuiTool', ...
                'AddStimTool','RemoveStimTool'};
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
                h.ProtocolStatusLabel.Text = 'Protocol: none | HW: speaker preview only';
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
                if obj.PlaybackOutput == "Speakers" && ~isempty(obj.Host)
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
            if isempty(obj.StimPlayObjs)
                h.Counter.Text = '0 / 0';
                return
            end
            presented = sum(arrayfun(@(sp) sp.StimPresented, obj.StimPlayObjs));
            total     = sum(arrayfun(@(sp) sp.StimTotal,     obj.StimPlayObjs));
            h.Counter.Text = sprintf('%d / %d', presented, total);
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

            if isempty(idx)
                h.ComboPrevBtn.Enable = 'off';
                h.ComboNextBtn.Enable = 'off';
                h.ComboStatusLbl.Text = 'Combo: - / -';
                return
            end

            stimObj = obj.StimPlayObjs(idx).CurrentStimObj;
            info = stimObj.get_variant_info();

            h.ComboStatusLbl.Text = sprintf('Combo: %d / %d', info.ActiveIndex, info.NumCombinations);
            if info.NumCombinations > 1
                h.ComboPrevBtn.Enable = 'on';
                h.ComboNextBtn.Enable = 'on';
            else
                h.ComboPrevBtn.Enable = 'off';
                h.ComboNextBtn.Enable = 'off';
            end
        end

        % -----------------------------------------------------------------
        function initialize_variants_(obj)
            % initialize_variants_() - Reset all bank items to combination #1.
            for i = 1:numel(obj.StimPlayObjs)
                stimObj = obj.StimPlayObjs(i).CurrentStimObj;
                stimObj.set_variant_index(1);
            end
        end

        % -----------------------------------------------------------------
        function advance_variant_(obj, bankIdx)
            % advance_variant_(obj, bankIdx) - Advance one bank item's variant by +1.
            if bankIdx < 1 || bankIdx > numel(obj.StimPlayObjs)
                return
            end
            stimObj = obj.StimPlayObjs(bankIdx).CurrentStimObj;
            stimObj.step_variant(1);
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
                    messageText = "StimPlayer was opened without a hardware host, so only speaker preview is available. " + ...
                        "Open StimPlayer from the host application (e.g. EPsych) to play through calibrated hardware.";
                case "stimgen:StimPlayer:HardwareRateMismatch"
                    messageText = string(ME.message) + newline + newline + ...
                        "A waveform generated at one rate plays at the wrong frequencies and duration at another. " + ...
                        "Set the bank Sample Rate to the hardware rate, then preview again.";
                case "stimgen:StimPlayer:PreviewVoltageOutOfRange"
                    messageText = string(ME.message) + newline + newline + ...
                        "Lower the stimulus Sound Level so the calibrated drive voltage fits the output range.";
                case "stimgen:StimPlayer:PreviewDuringRun"
                    messageText = "The hardware is presenting the bank right now. Stop the session, then preview through hardware.";
                case "stimgen:util:filterRateMismatch"
                    messageText = string(ME.message) + newline + newline + ...
                        "An equalization filter only corrects the frequencies it was designed for at the sample rate it was designed at. Redesign the filter for this rate in the calibration GUI (Design Filter, ""Design sample rate"" field) -- the measurement itself does not have to be repeated -- or set the sample rate back to the one the calibration was designed at.";
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
