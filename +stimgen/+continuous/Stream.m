classdef Stream < handle

    % obj = stimgen.continuous.Stream(Name,Value,...)
    % Gapless sound-card streaming engine for continuous stimuli.
    %
    % Package guide: documentation/stimgen_overview.md
    % Class guide: documentation/stimgen_continuous.md
    %
    % Feeds an audioDeviceWriter from a MATLAB timer, reading a looping
    % carrier buffer through a wrapping pointer so output never stops or
    % seams. An optional envelope buffer wraps on its OWN pointer, so the
    % envelope period need not divide the carrier block length.
    %
    % The engine deliberately knows nothing about stimuli. It is driven
    % entirely through set_carrier/set_envelope and is usable standalone:
    %
    %   s = stimgen.continuous.Stream;
    %   s.set_carrier(sin(2*pi*1000*(0:47999)/48000), 48000);
    %   s.start; pause(3); s.stop
    %
    % Click-free behavior comes from two mechanisms:
    %   * start/stop apply a cosine-squared ramp of RampDuration.
    %   * set_carrier while running never mutates the live buffer; it
    %     equal-power crossfades to the new one over CrossfadeDuration.
    %
    % See also stimgen.continuous.Playable, stimgen.ContinuousTone

    properties (SetObservable, AbortSet)
        RampDuration      (1,1) double {mustBeNonnegative,mustBeFinite} = 0.020; % s, start/stop fade
        CrossfadeDuration (1,1) double {mustBeNonnegative,mustBeFinite} = 0.020; % s, parameter-change fade
        SamplesPerFrame   (1,1) double {mustBePositive,mustBeInteger}   = 2048;
        Device            (1,1) string = ""; % "" = system default output device
    end

    properties (Constant)
        % Rates a sound card is likely to run natively. Anything else still
        % opens, but goes through the OS resampler (see open_device_).
        NATIVE_RATES = [44100 48000 88200 96000 176400 192000];
    end

    properties (SetAccess = protected)
        SampleRate (1,1) double = 48000;
        IsRunning  (1,1) logical = false;
        Underruns  (1,1) double = 0; % cumulative samples dropped since start
    end

    properties (Access = private)
        device_
        timer_

        carrier_    (1,:) double = [];
        carrierPtr_ (1,1) double = 1;

        % Crossfade state: the previous carrier keeps playing under the new
        % one until xfadeRemain_ reaches zero.
        xfadePrev_    (1,:) double = [];
        xfadePrevPtr_ (1,1) double = 1;
        xfadeLen_     (1,1) double = 0;
        xfadeDone_    (1,1) double = 0;
        xfadeRemain_  (1,1) double = 0;

        env_      (1,:) double = [];
        envPtr_   (1,1) double = 1;
        envMode_  (1,1) string = "Off";
        envDepth_ (1,1) double = 1;
        envArmed_ (1,1) logical = false; % a OneShot pass is in progress

        % Master fade. rampPos_ walks between 0 and rampLen_ at rampDir_.
        rampPos_ (1,1) double = 0;
        rampLen_ (1,1) double = 1;
        rampDir_ (1,1) double = 0;

        stopping_ (1,1) logical = false;

        % Re-entrancy guard. audioDeviceWriter blocks while the device queue
        % is full, and blocking lets MATLAB's event queue run -- which can
        % fire the timer callback on top of a frame write that is already in
        % progress, corrupting the read pointers or, worse, releasing the
        % device from underneath an active step().
        inFrame_ (1,1) logical = false;
    end

    methods

        function obj = Stream(varargin)
            for i = 1:2:numel(varargin)
                if isprop(obj, varargin{i})
                    obj.(varargin{i}) = varargin{i+1};
                end
            end
        end

        % -----------------------------------------------------------------
        function delete(obj)
            % Destructor: silence the device and drop the timer.
            obj.halt_();
        end

        % -----------------------------------------------------------------
        function set_carrier(obj, y, fs)
            % set_carrier(y, fs) - Install the looping carrier buffer.
            % When called while running, crossfades from the current buffer
            % rather than swapping it, so a live parameter edit does not click.
            arguments
                obj (1,1) stimgen.continuous.Stream
                y   (1,:) double
                fs  (1,1) double {mustBePositive,mustBeFinite}
            end

            if isempty(y) || ~all(isfinite(y))
                error('stimgen:continuous:Stream:InvalidCarrier', ...
                    'Carrier must be a non-empty vector of finite values.');
            end

            % Peak-normalize: apply_calibration scales to a hardware voltage
            % that routinely exceeds the sound card's +/-1 full scale.
            peak = max(abs(y));
            if peak > 0
                y = y ./ peak;
            end

            rateChanged = fs ~= obj.SampleRate;
            obj.SampleRate = fs;

            if ~obj.IsRunning || isempty(obj.carrier_) || rateChanged
                obj.carrier_    = y;
                obj.carrierPtr_ = 1;
                obj.xfadeRemain_ = 0;
                obj.xfadePrev_   = [];
                return
            end

            obj.xfadePrev_    = obj.carrier_;
            obj.xfadePrevPtr_ = obj.carrierPtr_;
            obj.xfadeLen_     = max(1, round(obj.CrossfadeDuration * fs));
            obj.xfadeDone_    = 0;
            obj.xfadeRemain_  = obj.xfadeLen_;

            obj.carrier_    = y;
            obj.carrierPtr_ = 1;
        end

        % -----------------------------------------------------------------
        function set_envelope(obj, y, mode, depth)
            % set_envelope(y, mode, depth) - Install the modulating envelope.
            % mode is "Off", "Loop" or "OneShot"; depth is in [0 1].
            arguments
                obj   (1,1) stimgen.continuous.Stream
                y     (1,:) double
                mode  (1,1) string {mustBeMember(mode,["Off","Loop","OneShot"])} = "Loop"
                depth (1,1) double {mustBeGreaterThanOrEqual(depth,0),mustBeLessThanOrEqual(depth,1)} = 1
            end

            obj.envMode_  = mode;
            obj.envDepth_ = depth;

            if isempty(y) || mode == "Off"
                obj.env_      = [];
                obj.envArmed_ = false;
                return
            end

            obj.env_ = y;
            % Keep a looping envelope phase-continuous across an edit rather
            % than snapping it back to the start.
            obj.envPtr_ = min(obj.envPtr_, numel(y));
            if mode == "OneShot"
                obj.envArmed_ = false;
            end
        end

        % -----------------------------------------------------------------
        function trigger_envelope(obj)
            % trigger_envelope() - Play the envelope once over the carrier.
            % Only meaningful in "OneShot" mode; ignored otherwise.
            if obj.envMode_ ~= "OneShot" || isempty(obj.env_)
                return
            end
            obj.envPtr_   = 1;
            obj.envArmed_ = true;
        end

        % -----------------------------------------------------------------
        function start(obj)
            % start() - Open the device and begin streaming, fading in.
            if obj.IsRunning
                return
            end
            if isempty(obj.carrier_)
                error('stimgen:continuous:Stream:NoCarrier', ...
                    'No carrier signal has been set. Call set_carrier before start.');
            end

            obj.open_device_();

            obj.Underruns = 0;
            obj.rampLen_  = max(1, round(obj.RampDuration * obj.SampleRate));
            obj.rampPos_  = 0;
            obj.rampDir_  = 1;
            obj.stopping_ = false;
            obj.IsRunning = true;

            % A period shorter than one frame keeps the device queue fed;
            % audioDeviceWriter blocks on the small surplus, which is what
            % actually paces the loop. BusyMode 'drop' absorbs timer jitter.
            period = max(0.001, round(0.85 * obj.SamplesPerFrame / obj.SampleRate, 3));

            % Prime the queue before the timer takes over. Without this the
            % first tick arrives against an empty device buffer and drops a
            % frame, which is audible as a tick at onset.
            for k = 1:2
                obj.write_frame_();
            end
            obj.Underruns = 0;

            obj.clear_stale_timers_();
            obj.timer_ = timer( ...
                'Tag',           'stimgenContinuousStream', ...
                'Period',        period, ...
                'ExecutionMode', 'fixedRate', ...
                'BusyMode',      'drop', ...
                'TimerFcn',      @(~,~) obj.on_tick_(), ...
                'ErrorFcn',      @(~,~) obj.halt_());
            start(obj.timer_);

            stimgen.util.vprintf(1, 'continuous.Stream: started at %.1f Hz (frame %d, period %.3f s).', ...
                obj.SampleRate, obj.SamplesPerFrame, period);
        end

        % -----------------------------------------------------------------
        function stop(obj)
            % stop() - Fade out and release the device.
            % Returns once the fade has been written, so the caller does not
            % have to wait on the timer.
            if ~obj.IsRunning
                obj.halt_();
                return
            end

            % Retire the timer BEFORE writing the fade. The writes below
            % block, and a blocked write lets the event queue dispatch the
            % tick callback on top of us.
            obj.kill_timer_();

            obj.stopping_ = true;
            obj.rampDir_  = -1;

            % Write the fade-out synchronously: relying on the timer would
            % race with a caller that deletes the object immediately after.
            nFrames = ceil(obj.rampPos_ / obj.SamplesPerFrame) + 1;
            for k = 1:nFrames
                if ~obj.IsRunning
                    break
                end
                obj.write_frame_();
                if obj.rampPos_ <= 0
                    break
                end
            end

            obj.halt_();
            stimgen.util.vprintf(1, 'continuous.Stream: stopped (%d underrun samples).', obj.Underruns);
        end

    end % methods (public)

    % =====================================================================
    methods (Access = private)

        function open_device_(obj)
            % open_device_() - Create and validate the audioDeviceWriter.
            % Probes with a silent frame so an unsupported sample rate fails
            % here with a clear message rather than mid-stream.
            obj.release_device_();

            args = {'SampleRate', obj.SampleRate, ...
                    'BufferSize', obj.SamplesPerFrame, ...
                    'SupportVariableSizeInput', false};
            if strlength(obj.Device) > 0
                args = [args, {'Device', char(obj.Device)}];
            end

            try
                obj.device_ = audioDeviceWriter(args{:});
                obj.device_(zeros(obj.SamplesPerFrame, 1)); % probe
            catch ME
                obj.release_device_();
                error('stimgen:continuous:Stream:UnsupportedSampleRate', ...
                    ['Could not open the audio device at %.4f Hz.\n' ...
                     'Sound cards typically support 44100, 48000, 88200 or 96000 Hz. ' ...
                     'Set Fs to one of those on the stimulus object (the stimgen default ' ...
                     '97656.25 Hz is a TDT rate and is not a sound-card rate).\n\n' ...
                     'Device reported: %s'], obj.SampleRate, ME.message);
            end

            % Windows shared-mode audio accepts almost any rate and silently
            % resamples to the device's native one. That is not an error, but
            % it does destroy the sample-exact loop seam the continuous
            % stimulus classes work to produce, so say so out loud.
            if ~any(abs(obj.SampleRate - stimgen.continuous.Stream.NATIVE_RATES) < 1e-6)
                stimgen.util.vprintf(0, 1, ...
                    ['continuous.Stream: %.4f Hz is not a native sound-card rate, so the OS ' ...
                     'will resample and the loop seam will not be sample-exact. ' ...
                     'Set Fs to one of %s Hz for a truly gapless loop.'], ...
                    obj.SampleRate, strjoin(string(stimgen.continuous.Stream.NATIVE_RATES), ', '));
            end
        end

        % -----------------------------------------------------------------
        function on_tick_(obj)
            % on_tick_() - Timer callback: keep the device queue fed.
            if ~obj.IsRunning
                return
            end
            try
                obj.write_frame_();
                if obj.stopping_ && obj.rampPos_ <= 0
                    obj.halt_();
                end
            catch ME
                stimgen.util.vprintf(0, 1, 'continuous.Stream: streaming failed, halting.');
                stimgen.util.vprintf(0, 1, ME);
                obj.halt_();
            end
        end

        % -----------------------------------------------------------------
        function write_frame_(obj)
            % write_frame_() - Assemble and push one frame to the device.
            % Non-reentrant: see inFrame_.
            if obj.inFrame_ || isempty(obj.device_)
                return
            end
            obj.inFrame_ = true;
            try
                n = obj.SamplesPerFrame;
                y = obj.next_frame_(n);
                nU = obj.device_(y(:));
                if nU > 0
                    obj.Underruns = obj.Underruns + nU;
                    % Behind the device: push a second frame to catch up.
                    y2 = obj.next_frame_(n);
                    obj.device_(y2(:));
                end
            catch ME
                obj.inFrame_ = false;
                rethrow(ME)
            end
            obj.inFrame_ = false;
        end

        % -----------------------------------------------------------------
        function y = next_frame_(obj, n)
            % next_frame_(n) - Carrier (x crossfade) x envelope x master fade.
            y = obj.read_loop_(obj.carrier_, obj.carrierPtr_, n);
            obj.carrierPtr_ = obj.wrap_(obj.carrierPtr_, n, numel(obj.carrier_));

            if obj.xfadeRemain_ > 0
                prev = obj.read_loop_(obj.xfadePrev_, obj.xfadePrevPtr_, n);
                obj.xfadePrevPtr_ = obj.wrap_(obj.xfadePrevPtr_, n, numel(obj.xfadePrev_));

                u = min(1, (obj.xfadeDone_ + (0:n-1)) ./ obj.xfadeLen_);
                y = y .* sin(pi/2 .* u) + prev .* cos(pi/2 .* u); % equal power

                obj.xfadeDone_   = obj.xfadeDone_ + n;
                obj.xfadeRemain_ = max(0, obj.xfadeRemain_ - n);
                if obj.xfadeRemain_ == 0
                    obj.xfadePrev_ = [];
                end
            end

            e = obj.next_envelope_(n);
            if ~isempty(e)
                y = y .* e;
            end

            y = y .* obj.next_gain_(n);
        end

        % -----------------------------------------------------------------
        function e = next_envelope_(obj, n)
            % next_envelope_(n) - Envelope gain for this frame, or [] if unused.
            e = [];
            if obj.envMode_ == "Off" || isempty(obj.env_)
                return
            end

            if obj.envMode_ == "Loop"
                e = obj.read_loop_(obj.env_, obj.envPtr_, n);
                obj.envPtr_ = obj.wrap_(obj.envPtr_, n, numel(obj.env_));
            else % OneShot: unity until triggered, then a single pass
                e = ones(1, n);
                if obj.envArmed_
                    k = min(n, numel(obj.env_) - obj.envPtr_ + 1);
                    e(1:k) = obj.env_(obj.envPtr_:obj.envPtr_ + k - 1);
                    obj.envPtr_ = obj.envPtr_ + k;
                    if obj.envPtr_ > numel(obj.env_)
                        obj.envArmed_ = false;
                    end
                end
            end

            e = 1 - obj.envDepth_ + obj.envDepth_ .* e;
        end

        % -----------------------------------------------------------------
        function g = next_gain_(obj, n)
            % next_gain_(n) - Sample-accurate cosine-squared master fade.
            p = min(max(obj.rampPos_ + obj.rampDir_ .* (1:n), 0), obj.rampLen_);
            g = 0.5 - 0.5 .* cos(pi .* p ./ obj.rampLen_);
            obj.rampPos_ = p(end);
            if obj.rampDir_ > 0 && obj.rampPos_ >= obj.rampLen_
                obj.rampDir_ = 0;
            end
        end

        % -----------------------------------------------------------------
        function halt_(obj)
            % halt_() - Unconditionally tear down timer and device.
            % Timer first, always: the device must never be released while a
            % tick could still be dispatched into a frame write.
            obj.kill_timer_();

            obj.IsRunning = false;
            obj.stopping_ = false;
            obj.rampDir_  = 0;
            obj.rampPos_  = 0;
            obj.inFrame_  = false;

            obj.release_device_();
        end

        % -----------------------------------------------------------------
        function kill_timer_(obj)
            if ~isempty(obj.timer_) && isvalid(obj.timer_)
                stop(obj.timer_);
                delete(obj.timer_);
            end
            obj.timer_ = [];
        end

        % -----------------------------------------------------------------
        function release_device_(obj)
            % release() alone leaves the underlying portaudio stream
            % registered, which faults during MATLAB's process-exit teardown.
            % delete() as well.
            if ~isempty(obj.device_)
                try
                    release(obj.device_);
                catch
                    % Device may already be gone; nothing useful to do.
                end
                try
                    delete(obj.device_);
                catch
                end
            end
            obj.device_ = [];
        end

        % -----------------------------------------------------------------
        function clear_stale_timers_(~)
            % Mirror stimgen.StimPlayer.playback_control: a stale timer from a
            % crashed session would otherwise keep firing into a dead object.
            t = timerfindall('Tag', 'stimgenContinuousStream');
            for k = 1:numel(t)
                if isvalid(t(k))
                    stop(t(k));
                    delete(t(k));
                end
            end
        end

    end % methods (private)

    % =====================================================================
    methods (Static, Access = private)

        function y = read_loop_(buf, ptr, n)
            % read_loop_(buf, ptr, n) - n samples from buf starting at ptr, wrapping.
            y = buf(mod(ptr - 1 + (0:n-1), numel(buf)) + 1);
        end

        function ptr = wrap_(ptr, n, len)
            ptr = mod(ptr - 1 + n, len) + 1;
        end

    end % methods (Static, Access = private)

end
