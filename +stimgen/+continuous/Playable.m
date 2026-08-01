classdef Playable < handle

    % stimgen.continuous.Playable
    % Mixin adding continuous (gapless, self-driven) playback to a StimType.
    %
    % Package guide: documentation/stimgen_overview.md
    % Class guide: documentation/stimgen_continuous.md
    %
    % Mix into a concrete stimulus class alongside its carrier superclass:
    %
    %   classdef ContinuousTone < stimgen.Tone & stimgen.continuous.Playable
    %
    % The difference between a continuous and a discrete stimulus is
    % lifecycle, not synthesis -- the waveform math is unchanged. What this
    % mixin adds is: ownership of a stimgen.continuous.Stream, start/stop,
    % and optional modulation by the envelope of another StimType object.
    %
    % Contract for the host class:
    %   * Signal must be a SEAMLESSLY LOOPABLE block. Duration is
    %     reinterpreted as the loop-block length.
    %   * Do NOT call apply_gate. A ramp inside a looping block would be
    %     audible once per lap. The constructor sets ApplyWindow = false and
    %     propMeta drops the window properties; use RampDuration instead,
    %     which fades the stream itself on start and stop.
    %   * update_signal must end with obj.refresh_stream_(), which pushes the
    %     new block to a running stream via a click-free crossfade.
    %
    % This class deliberately holds the engine by composition rather than
    % implementing streaming itself, so the engine stays testable standalone
    % and this mixin remains thin glue.
    %
    % See also stimgen.continuous.Stream, stimgen.ContinuousTone, stimgen.ContinuousNoise

    properties (SetObservable, AbortSet)
        % Stream fade applied on start() and stop(), seconds (shown in ms).
        RampDuration (1,1) double {mustBeNonnegative,mustBeFinite} = 0.020;

        % Class name of the StimType whose envelope modulates the carrier,
        % or "None". Setting this builds a fresh instance of that class.
        EnvelopeSourceClass (1,1) string = "None";

        % "Off"     - carrier only
        % "Loop"    - envelope wraps continuously on its own read pointer
        % "OneShot" - carrier unmodulated until trigger_envelope() fires
        EnvelopeMode (1,1) string {mustBeMember(EnvelopeMode,["Off","Loop","OneShot"])} = "Off";

        % How the envelope is recovered from the source object's Signal.
        EnvelopeMethod (1,1) string {mustBeMember(EnvelopeMethod,["Direct","Hilbert","RectifyLowpass"])} = "Direct";

        % Cutoff for the RectifyLowpass method only, Hz.
        EnvelopeLowpass (1,1) double {mustBePositive,mustBeFinite} = 50;

        % Modulation depth, matching the stimgen.AMnoise convention:
        % applied gain is 1 - depth + depth*envelope.
        EnvelopeDepth (1,1) double {mustBeGreaterThanOrEqual(EnvelopeDepth,0),mustBeLessThanOrEqual(EnvelopeDepth,1)} = 1;
    end

    properties (SetAccess = protected)
        % Live StimType instance supplying the envelope, or empty.
        EnvelopeSource = [];
    end

    properties (Dependent)
        IsRunning % true while the stream is feeding the sound card
    end

    properties (Access = protected)
        stream_ = [];
        envelopeListener_ = [];
        % Cached Start/Stop button handle. Captured from the GUI callback
        % rather than read from StimType.GUIHandles, which is protected to a
        % hierarchy this mixin is not part of.
        streamButton_ = [];
    end

    % =====================================================================
    methods

        function tf = get.IsRunning(obj)
            tf = ~isempty(obj.stream_) && isvalid(obj.stream_) && obj.stream_.IsRunning;
        end

        % -----------------------------------------------------------------
        function delete(obj)
            % Destructor: never leave the sound card open or a timer orphaned.
            if ~isempty(obj.stream_) && isvalid(obj.stream_)
                delete(obj.stream_);
            end
            if ~isempty(obj.envelopeListener_) && isvalid(obj.envelopeListener_)
                delete(obj.envelopeListener_);
            end
        end

        % -----------------------------------------------------------------
        function start(obj)
            % start() - Begin continuous playback, fading in over RampDuration.
            % Playback continues until stop() is called.
            if isempty(obj.Signal)
                obj.update_signal;
            end

            s = obj.stream();
            s.RampDuration = obj.RampDuration;
            obj.push_carrier_(s);
            obj.push_envelope_(s);
            s.start();

            obj.sync_stream_button_();
        end

        % -----------------------------------------------------------------
        function stop(obj)
            % stop() - Fade out over RampDuration and release the device.
            if ~isempty(obj.stream_) && isvalid(obj.stream_)
                obj.stream_.stop();
            end
            obj.sync_stream_button_();
        end

        % -----------------------------------------------------------------
        function toggle(obj, btn)
            % toggle(btn) - Start if stopped, stop if running.
            % btn is the GUI button handle when called from the generated
            % parameter panel, and is cached so later programmatic start/stop
            % calls can keep its label in sync.
            if nargin > 1 && ~isempty(btn) && isvalid(btn)
                obj.streamButton_ = btn;
            end
            if obj.IsRunning
                obj.stop();
            else
                obj.start();
            end
        end

        % -----------------------------------------------------------------
        function trigger_envelope(obj)
            % trigger_envelope() - Play the envelope once over a running carrier.
            % Only meaningful when EnvelopeMode is "OneShot".
            if ~isempty(obj.stream_) && isvalid(obj.stream_)
                obj.stream_.trigger_envelope();
            end
        end

        % -----------------------------------------------------------------
        function s = stream(obj)
            % stream() - The stimgen.continuous.Stream engine, created on demand.
            % Exposed so callers can reach SamplesPerFrame, Device, Underruns.
            if isempty(obj.stream_) || ~isvalid(obj.stream_)
                obj.stream_ = stimgen.continuous.Stream( ...
                    'RampDuration', obj.RampDuration);
            end
            s = obj.stream_;
        end

        % -----------------------------------------------------------------
        function set.EnvelopeSourceClass(obj, value)
            obj.EnvelopeSourceClass = value;
            obj.rebuild_envelope_source_();
        end

    end % methods (public)

    % =====================================================================
    methods (Access = protected)

        function refresh_stream_(obj)
            % refresh_stream_() - Push the current Signal to a running stream.
            % Called at the end of the host class's update_signal. A no-op
            % when not running, so property edits stay cheap while stopped.
            if ~obj.IsRunning
                return
            end
            obj.stream_.RampDuration = obj.RampDuration;
            obj.push_carrier_(obj.stream_);
            obj.push_envelope_(obj.stream_);
        end

        % -----------------------------------------------------------------
        function m = continuous_prop_meta_(obj, base)
            % continuous_prop_meta_(base) - Strip window metadata and add the
            % continuous properties. Host classes call this instead of
            % merging the inherited propMeta directly.
            %
            % ApplyWindow/WindowDuration are removed rather than hidden: a
            % gate inside a looping block is always wrong, and leaving the
            % widgets visible would invite it.
            base = rmfield_if_present_(base, {'WindowDuration', 'ApplyWindow', 'WindowMethod'});

            m = struct();
            m.RampDuration = struct('label', 'Ramp In/Out (ms)', 'format', '%.1f ms', ...
                'limits', [0 5000], 'scale', 1000, 'group', 'Timing', 'order', 20);

            m.EnvelopeSourceClass = struct('label', 'Envelope Source', 'widget', 'dropdown', ...
                'items', ["None", string(stimgen.StimType.list())], 'group', 'Level', 'order', 30);
            m.EnvelopeMode = struct('label', 'Envelope Mode', 'widget', 'dropdown', ...
                'items', ["Off" "Loop" "OneShot"], 'group', 'Level', 'order', 31);
            m.EnvelopeMethod = struct('label', 'Envelope Method', 'widget', 'dropdown', ...
                'items', ["Direct" "Hilbert" "RectifyLowpass"], 'group', 'Level', 'order', 32);
            m.EnvelopeLowpass = struct('label', 'Envelope LPF', 'format', '%.1f Hz', ...
                'limits', [0.1 20000], 'group', 'Level', 'order', 33);
            m.EnvelopeDepth = struct('label', 'Envelope Depth', 'format', '%.2f', ...
                'limits', [0 1], 'group', 'Level', 'order', 34);

            m.EditEnvelopeSource = struct('label', 'Envelope Params', 'widget', 'button', ...
                'buttonText', 'Edit Source...', 'callback', @(~) obj.edit_envelope_source_(), ...
                'group', 'Level', 'order', 35);
            m.StreamControl = struct('label', 'Playback', 'widget', 'button', ...
                'buttonText', 'Start', 'callback', @(btn) obj.toggle(btn), ...
                'group', 'Timing', 'order', 90);

            % Merged inline rather than through
            % stimgen.StimType.merge_prop_meta, which is protected to a
            % hierarchy this mixin is not part of. Same semantics: base wins
            % on a name collision.
            m = merge_(m, base);
        end

        % -----------------------------------------------------------------
        function detach_stream_(obj)
            % detach_stream_() - Drop all live playback state without touching
            % the original's device or timer. Host classes call this from
            % copyElement, since copy() would otherwise hand two objects the
            % same audioDeviceWriter and the same timer, and deleting either
            % would silence both.
            obj.stream_           = [];
            obj.envelopeListener_ = [];
            obj.streamButton_     = [];
            if ~isempty(obj.EnvelopeSource) && isvalid(obj.EnvelopeSource)
                obj.EnvelopeSource = copy(obj.EnvelopeSource);
            end
        end

        % -----------------------------------------------------------------
        function props = continuous_user_properties_(~)
            % continuous_user_properties_() - Names host classes must append to
            % UserProperties so the continuous settings survive toStruct/fromStruct.
            props = ["RampDuration", "EnvelopeSourceClass", "EnvelopeMode", ...
                     "EnvelopeMethod", "EnvelopeLowpass", "EnvelopeDepth"];
        end

    end % methods (protected)

    % =====================================================================
    methods (Access = private)

        function push_carrier_(obj, s)
            s.set_carrier(double(obj.Signal), double(obj.selected_value("Fs")));
        end

        % -----------------------------------------------------------------
        function push_envelope_(obj, s)
            s.set_envelope(obj.build_envelope_(), obj.EnvelopeMode, obj.EnvelopeDepth);
        end

        % -----------------------------------------------------------------
        function e = build_envelope_(obj)
            % build_envelope_() - Extract a [0 1] envelope from the source object.
            e = [];
            if obj.EnvelopeMode == "Off" || isempty(obj.EnvelopeSource) ...
                    || ~isvalid(obj.EnvelopeSource)
                return
            end

            src = obj.EnvelopeSource;
            if isempty(src.Signal)
                src.update_signal;
            end
            x = double(src.Signal);
            if isempty(x)
                return
            end

            switch obj.EnvelopeMethod
                case "Direct"
                    % The objects worth using as modulators (AMnoise with
                    % EnvelopeOnly, AttackModNoise, ClickTrain) already ARE
                    % envelopes, so take the waveform as-is. Negative excursions
                    % are clamped rather than rectified, which would double the
                    % rate of anything oscillating about zero.
                    e = max(x, 0);
                case "Hilbert"
                    e = abs(hilbert(x));
                case "RectifyLowpass"
                    e = obj.lowpass_envelope_(abs(x), double(src.selected_value("Fs")));
            end

            % Clamp before normalizing: filtfilt ringing in the
            % RectifyLowpass path can dip slightly below zero, which would
            % invert the carrier rather than silence it.
            e = max(e, 0);

            peak = max(e);
            if peak > 0
                e = e ./ peak;
            else
                e = [];
            end
        end

        % -----------------------------------------------------------------
        function e = lowpass_envelope_(obj, x, fs)
            % lowpass_envelope_(x, fs) - Zero-phase low-pass of a rectified signal.
            fc = min(obj.EnvelopeLowpass, 0.45 * fs);
            d = designfilt('lowpassiir', 'FilterOrder', 4, ...
                'HalfPowerFrequency', fc, 'SampleRate', fs);
            e = filtfilt(d, x); % zero phase: keeps the envelope time-aligned
        end

        % -----------------------------------------------------------------
        function rebuild_envelope_source_(obj)
            % rebuild_envelope_source_() - Instantiate the selected modulator class
            % and listen to its Signal so live edits reach a running stream.
            if ~isempty(obj.envelopeListener_) && isvalid(obj.envelopeListener_)
                delete(obj.envelopeListener_);
            end
            obj.envelopeListener_ = [];
            obj.EnvelopeSource = [];

            name = obj.EnvelopeSourceClass;
            if name == "None" || strlength(name) == 0
                obj.refresh_stream_();
                return
            end

            try
                src = feval("stimgen." + name);
            catch ME
                error('stimgen:continuous:Playable:BadEnvelopeSource', ...
                    'Could not create envelope source "%s": %s', name, ME.message);
            end

            % Match the carrier's sample rate, or the two buffers would drift.
            src.Fs = obj.Fs;
            src.ApplyCalibration = false; % envelope is a gain, not a level
            src.update_signal;

            obj.EnvelopeSource = src;
            obj.envelopeListener_ = addlistener(src, 'Signal', 'PostSet', ...
                @(~,~) obj.refresh_stream_());

            obj.refresh_stream_();
        end

        % -----------------------------------------------------------------
        function edit_envelope_source_(obj)
            % edit_envelope_source_() - Open the modulator's own parameter GUI.
            % create_gui already takes a parent container, so the nested object
            % gets a full editor with no changes to the flat GUI builder.
            if isempty(obj.EnvelopeSource) || ~isvalid(obj.EnvelopeSource)
                return
            end
            f = uifigure('Name', "Envelope Source: " + obj.EnvelopeSourceClass, ...
                'Position', [100 100 380 520]);
            obj.EnvelopeSource.create_gui(f);
        end

        % -----------------------------------------------------------------
        function sync_stream_button_(obj)
            % sync_stream_button_() - Keep the Start/Stop button text honest.
            if isempty(obj.streamButton_) || ~isvalid(obj.streamButton_)
                return
            end
            if obj.IsRunning
                obj.streamButton_.Text = 'Stop';
            else
                obj.streamButton_.Text = 'Start';
            end
        end

    end % methods (private)

end

% =========================================================================
function a = merge_(a, b)
% Append all fields of b into a, b winning on collision. Mirrors
% stimgen.StimType.merge_prop_meta, which is not reachable from here.
bf = fieldnames(b);
for i = 1:numel(bf)
    a.(bf{i}) = b.(bf{i});
end
end

% =========================================================================
function s = rmfield_if_present_(s, names)
for i = 1:numel(names)
    if isfield(s, names{i})
        s = rmfield(s, names{i});
    end
end
end
