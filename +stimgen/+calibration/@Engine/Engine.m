classdef Engine < handle
    % stimgen.calibration.Engine
    % Core calibration engine: SPL-to-voltage lookup table generator.
    %
    % Orchestrates reference measurement, tone and click sweeps, and provides
    % compute_adjusted_voltage() for real-time stimulus scaling. An optional
    % equalization filter can be designed as a post-calibration step.
    %
    % Uses a unified SPL/voltage model for both tones and clicks: peak
    % measurements are converted to RMS equivalent before computing dB SPL.
    % All calibration runs are atomic - a failure aborts the run and no
    % partial data is retained. calibrate_tones/calibrate_clicks/
    % calibrate_swept_sine poll cancel() between measurements and abort the
    % same way when it has been called.
    %
    % CalibrationData is empty ([]) until a successful run completes.
    % After a successful run it is a struct with fields:
    %   tone             - struct: frequency, measurement, spl_db, voltage (Nx1); metrics sub-struct
    %   click            - struct: duration, measurement, spl_db, voltage (Nx1); metrics sub-struct
    %   swept_sine       - struct: frequency, measurement, spl_db, voltage (Nx1); metrics sub-struct.
    %                      Its metrics also carry a full acoustic characterization
    %                      derived from the deconvolved impulse response: phase and
    %                      group delay (with the minimum-phase/excess split),
    %                      reflection arrival times and levels, reverberation time
    %                      per octave band, clarity/definition, and time-gated
    %                      harmonic distortion. See
    %                      documentation/stimgen_SweptSineCalibration.md
    %   filter           - digitalFilter | [] (populated by design_filter)
    %   filterGrpDelay   - int (group delay samples; 0 until design_filter runs)
    %   filterSource     - "tone" | "swept_sine" (which LUT the filter came from)
    %   filterDesign     - struct of the design options and the achieved
    %                      correction span, so a saved filter records how it
    %                      was made (see design_filter)
    %   filterTest       - struct recording a test_filter verification run
    %   toneTest         - struct recording a test_tones verification run, so
    %                      a saved calibration carries the evidence that its
    %                      tone LUT reproduces the levels it promises
    %
    % Usage:
    %   adapter = stimgen.calibration.WindowsSoundCardAdapter();
    %   eng = stimgen.calibration.Engine(adapter);
    %   eng.set_configuration(ReferenceFrequency=1000);  % parameters are
    %                                    % SetAccess = protected; use this
    %   eng.calibrate_reference();      % records an acoustic calibrator held
    %                                   % on the mic; nothing is played
    %   eng.calibrate_tones([], 3);     % 3 passes over the burst train
    %   eng.calibrate_clicks([], 3);
    %   eng.design_filter();            % optional; see design_filter for
    %                                   % length/interpolation/smoothing options
    %   eng.save('my_cal.esgc');
    %
    %   % offline use (no adapter needed):
    %   eng = stimgen.calibration.Engine.load('my_cal.esgc');
    %   v   = eng.compute_adjusted_voltage("tone", 4000, 70);
    %
    % While a run is in progress the engine broadcasts a LiveUpdate event
    % carrying a stimgen.calibration.LiveUpdate payload for every measurement,
    % gated by ShowLivePlots. stimgen.calibration.LiveMonitor renders that
    % stream; a host application can listen to it instead to log or forward
    % progress. Nothing in this class draws.
    %
    % See also: stimgen.calibration.HwAdapter,
    %           stimgen.calibration.WindowsSoundCardAdapter,
    %           stimgen.calibration.LiveMonitor, stimgen.calibration.LiveUpdate,
    %           documentation/stimgen_calibration.md

    % --- Persistent calibration parameters ---
    properties (SetAccess = protected, SetObservable, AbortSet)
        MicSensitivity      (1,1) double {mustBePositive,mustBeFinite}      = 1     % V/Pa
        ReferenceLevel      (1,1) double {mustBePositive,mustBeFinite}      = 94    % dB SPL
        ReferenceFrequency  (1,1) double {mustBePositive,mustBeFinite}      = 1000  % Hz
        NormativeValue      (1,1) double {mustBePositive,mustBeFinite}      = 80    % dB SPL
        ExcitationVoltage   (1,1) double {mustBePositive}                   = 1     % V (<=10)
        MaxOutputVoltage    (1,1) double {mustBePositive,mustBeFinite}      = 10    % V full scale
        ShowLivePlots       (1,1) logical                                   = false
        % Which LUT serves "tone" lookups (and the "filter" lookups anchored to
        % them). "swept_sine" overrides any direct tone calibration whenever
        % swept sine data exists, falling back to the tone LUT when it does not.
        % Both LUTs stay stored either way; this only redirects the lookup.
        ToneLutSource       (1,1) string {mustBeMember(ToneLutSource, ["tone", "swept_sine"])} = "tone"
        CalibrationTimestamp (1,1) datetime = datetime("")
    end

    events
        % Broadcast per measurement while ShowLivePlots is true. Event data is
        % a stimgen.calibration.LiveUpdate.
        LiveUpdate
    end

    % --- Calibration results and transient signals ---
    properties (SetAccess = protected)
        CalibrationData = []    % struct (see class doc) or [] if uncalibrated
        Adapter                 % stimgen.calibration.HwAdapter | []
        ExcitationSignal (1,:) double = []
        ResponseSignal   (1,:) double = []
        ResponseTHD      (1,1) double = nan
    end

    properties (Access = private)
        CancelRequested_ (1,1) logical = false   % set by cancel(); consumed by throw_if_cancelled_
        Monitors_ (1,:) cell = {}   % LiveMonitor objects registered via register_monitor_
        RunTic_                     % tic id of the run in progress; [] outside one
        LiveHookFailed_ (1,1) logical = false  % latched by emit_live_ so a broken listener logs once, not per measurement
    end

    properties (Dependent)
        Fs          % sample rate from adapter (0 if no adapter)
        IsCalibrated % true when CalibrationData is a non-empty struct
    end

    methods
        function obj = Engine(adapter)
            % obj = stimgen.calibration.Engine()
            % obj = stimgen.calibration.Engine(adapter)
            %
            % Construct a calibration engine. Supply an HwAdapter to enable
            % live measurement; omit it for offline compute_adjusted_voltage
            % use only.
            %
            % Parameters:
            %   adapter - stimgen.calibration.HwAdapter | [] (default [])
            arguments
                adapter = []
            end
            if ~isempty(adapter)
                if ~isa(adapter, 'stimgen.calibration.HwAdapter')
                    error('stimgen:calibration:Engine:badAdapter', ...
                        'adapter must be a stimgen.calibration.HwAdapter.');
                end
            end
            obj.Adapter = adapter;
        end

        set_configuration(obj, options) % Update engine calibration parameters.
        set_adapter(obj, adapter) % Attach, replace, or detach the hardware adapter.
        calibrate_reference(obj) % Measure microphone sensitivity by recording an acoustic calibrator (plays nothing).
        calibrate_tones(obj, freqs, repeatCount, options) % Build tone calibration LUT.
        calibrate_clicks(obj, durs, repeatCount) % Build click calibration LUT.
        calibrate_swept_sine(obj, duration, freqs, repeatCount, tailDuration) % Run swept-sine calibration.
        design_filter(obj, source, options) % Design equalization filter from a frequency LUT.
        results = test_filter(obj, options) % Verify the designed filter flattens the measured response.
        results = test_tones(obj, freqs, levels, options) % Verify the tone LUT reproduces requested levels at discrete tones.
        v = compute_adjusted_voltage(obj, type, value, level) % Interpolate LUT voltage.
        ffn = save(obj, ffn) % Save calibration to .esgc file; returns the resolved path.
        restore(obj, s) % Restore engine state from a serialized struct.
        cancel(obj) % Request cancellation of an in-progress calibration run.
        reset_calibration(obj) % Discard acquired calibration data; keeps adapter and parameters.

        function Fs = get.Fs(obj)
            % Return adapter sample rate or 0 when no adapter is attached.
            if isempty(obj.Adapter)
                Fs = 0;
            else
                Fs = obj.Adapter.sample_rate();
            end
        end

        function tf = get.IsCalibrated(obj)
            % True when CalibrationData is a non-empty struct.
            tf = isstruct(obj.CalibrationData) && ~isempty(obj.CalibrationData);
        end

        function plot_reset(obj)
            % Clear the attached monitors' panels.
            %
            % Deprecated along with plot_signal/plot_spectrum/plot_transfer:
            % drawing belongs to stimgen.calibration.LiveMonitor now. Kept so
            % that scripts written against the old subplot figure keep working.
            mons = obj.live_monitors_();
            for k = 1:numel(mons)
                mons{k}.reset();
            end
            drawnow;
        end

        plot_signal(obj, reset) % Deprecated; delegates to LiveMonitor.
        plot_spectrum(obj, reset) % Deprecated; delegates to LiveMonitor.
        plot_transfer(obj, type, tableData, reset) % Deprecated; delegates to LiveMonitor.
    end

    % ------------------------------------------------------------------ %
    % Live-update plumbing. stimgen.calibration.LiveMonitor is the only
    % outside caller: it registers itself so the deprecated plot_ entry
    % points can find a renderer, and asks for a snapshot when it needs to
    % draw the engine's state outside a run.
    methods (Access = {?stimgen.calibration.Engine, ?stimgen.calibration.LiveMonitor})

        function register_monitor_(obj, mon)
            % register_monitor_(obj, mon)
            % Remember a monitor that is following this engine. The LiveUpdate
            % event drives it during a run; this registration is what lets the
            % off-run entry points reach it as well.
            mons = obj.live_monitors_();
            for k = 1:numel(mons)
                if mons{k} == mon
                    obj.Monitors_ = mons;
                    return
                end
            end
            obj.Monitors_ = [mons, {mon}];
        end

        function unregister_monitor_(obj, mon)
            % unregister_monitor_(obj, mon)
            % Forget a monitor. Also drops any that have since been deleted.
            mons = obj.live_monitors_();
            keep = true(1, numel(mons));
            for k = 1:numel(mons)
                keep(k) = mons{k} ~= mon;
            end
            obj.Monitors_ = mons(keep);
        end

        function d = live_snapshot_(obj, stage, phase, varargin)
            % d = live_snapshot_(obj, stage, phase)
            % d = live_snapshot_(obj, stage, phase, Name, Value, ...)
            %
            % Build one stimgen.calibration.LiveUpdate describing the engine's
            % current state. Everything a renderer can derive from the engine
            % itself -- sample rate, the excitation/response pair, the
            % parameters needed to turn volts into dB SPL, elapsed run time --
            % is filled in here, so a caller only supplies what is specific to
            % the measurement it just took (Table, Span, Index, Markers, ...).
            %
            % A Metrics struct passed by the caller is merged onto the
            % engine-derived one rather than replacing it, so naming spl_db
            % does not silently discard peak_v and the clipping flag.
            args            = struct();
            args.Fs         = obj.Fs;
            args.Excitation = obj.ExcitationSignal;
            args.Response   = obj.ResponseSignal;
            args.Context    = obj.live_context_();
            args.Elapsed    = obj.run_elapsed_();

            metrics = obj.live_metrics_();
            for k = 1:2:numel(varargin)
                if strcmp(varargin{k}, 'Metrics')
                    metrics = obj.merge_struct_(metrics, varargin{k+1});
                else
                    args.(varargin{k}) = varargin{k+1};
                end
            end
            args.Metrics = metrics;

            nv = namedargs2cell(args);
            d  = stimgen.calibration.LiveUpdate(stage, phase, nv{:});
        end
    end

    methods (Access = private)
        function mons = live_monitors_(obj)
            % mons = live_monitors_(obj)
            % Registered monitors that are still alive. A host GUI can be
            % closed without detaching, so the list is pruned on every read
            % rather than trusted.
            mons = obj.Monitors_;
            if isempty(mons), return; end
            alive = cellfun(@(m) ~isempty(m) && isvalid(m), mons);
            mons  = mons(alive);
            obj.Monitors_ = mons;
        end

        function emit_live_(obj, stage, phase, varargin)
            % emit_live_(obj, stage, phase, Name, Value, ...)
            % Broadcast one LiveUpdate, gated by ShowLivePlots so a headless
            % run pays nothing for the payload it would not render.
            %
            % Listener errors are caught by MATLAB itself (warned, not
            % propagated), so the guard here is for payload construction:
            % live_snapshot_ runs before notify, and every calibrate_ method
            % treats an error as an aborted run and discards the partial data.
            % Display is not worth a measurement: a snapshot failure is logged
            % once per run and the sweep carries on. LiveMonitor.update guards
            % its own rendering the same way, so a plotting bug is one log
            % line rather than a per-measurement warning storm.
            if ~obj.ShowLivePlots, return; end
            try
                notify(obj, 'LiveUpdate', obj.live_snapshot_(stage, phase, varargin{:}));
            catch ME
                if ~obj.LiveHookFailed_
                    obj.LiveHookFailed_ = true;
                    stimgen.util.vprintf(0, 1, ...
                        'A LiveUpdate listener failed; live plotting may be incomplete for this run.');
                    stimgen.util.vprintf(0, 1, ME);
                end
            end
        end

        function begin_run_(obj)
            % Start the clock that feeds LiveUpdate.Elapsed, from which the
            % monitor derives its time-remaining estimate. Also re-arms the
            % broken-listener warning, so a fault is reported once per run
            % rather than once per session.
            obj.RunTic_ = tic;
            obj.LiveHookFailed_ = false;
        end

        function s = run_elapsed_(obj)
            % Seconds since begin_run_, or 0 outside a run.
            if isempty(obj.RunTic_)
                s = 0;
            else
                s = toc(obj.RunTic_);
            end
        end

        function c = live_context_(obj)
            % Engine parameters a renderer needs to interpret a payload.
            c = struct( ...
                'ReferenceLevel',    obj.ReferenceLevel, ...
                'MicSensitivity',    obj.MicSensitivity, ...
                'NormativeValue',    obj.NormativeValue, ...
                'ExcitationVoltage', obj.ExcitationVoltage, ...
                'MaxOutputV',        obj.MaxOutputVoltage);
        end

        function m = live_metrics_(obj)
            % Scalars derivable from the response record alone. Clipping is
            % judged by estimate_headroom_, the same test whose verdict is
            % stored in the calibration metrics, so the warning on screen and
            % the flag in the saved file cannot disagree.
            m = stimgen.calibration.LiveUpdate.default_metrics();
            m.full_scale_v = obj.MaxOutputVoltage;

            y = obj.ResponseSignal;
            if isempty(y), return; end

            h = obj.estimate_headroom_(obj.ExcitationSignal, y);
            m.peak_v   = h.responsePeakV;
            m.rms_v    = sqrt(mean(y .^ 2));
            m.clipping = h.responseClippingLikely;
        end

        function render_engine_state_(obj, reset)
            % Back end of the deprecated plot_signal/plot_spectrum entry
            % points: draw the current response through whichever monitors are
            % attached, creating one that owns its own window if none is.
            mons = obj.live_monitors_();
            if isempty(mons)
                mons = {stimgen.calibration.LiveMonitor(obj)};
            end
            for k = 1:numel(mons)
                if reset
                    mons{k}.reset();
                else
                    mons{k}.show_engine_state(obj);
                end
            end
        end

        function assert_adapter_(obj)
            % Raise an error when no hardware adapter is attached.
            if isempty(obj.Adapter)
                error('stimgen:calibration:Engine:noAdapter', ...
                    'No HwAdapter attached. Provide an adapter to run calibrations.');
            end
        end

        r = measure_(obj, signal, mode, options) % Acquire and compute measurement metric.
        [y, schedule] = build_tone_sequence_(obj, freqs, burstDur, gapDur) % Assemble one gated tone-burst train.
        [lag, atBound] = align_response_(obj, x, y, maxLag) % Bulk acquisition delay by cross-correlation.
        [exBurst, rsBurst, rsSteady, steadySpan] = extract_burst_(obj, x, response, s, lag) % Cut one scheduled burst from an excitation/response pair.
        [name, lut] = resolve_tone_lut_(obj) % Which LUT serves tone lookups, and its contents.
        [spl_db, voltage] = compute_spl_voltage_(obj, measurement, mode) % Convert measurement to SPL and normative voltage.
        [noiseFloorDb, snrDb] = estimate_noise_snr_(obj, y, fs, toneFreq) % Estimate noise floor and SNR.
        [thdDb, h2Db, h3Db] = estimate_harmonics_(obj, y, fs, fundamentalFreq) % Estimate THD and harmonic levels.
        A = analyze_sweep_response_(obj, x, y, fs, sweep) % Full swept-sine analysis from one deconvolution.
        [H, freqHz, h, nfft] = deconvolve_sweep_(obj, x, y, fs) % Regularized sweep deconvolution.
        loc = locate_impulse_(obj, h, fs, searchLast) % Direct arrival, usable extent, noise crossing.
        metrics = estimate_transfer_metrics_(obj, hg, fs, band, bulkDelaySamples, perOctave) % Magnitude, phase, group delay.
        m = estimate_impulse_metrics_(obj, h, fs, loc, band, searchLast) % Reflections, decay, clarity.
        m = estimate_sweep_harmonics_(obj, h, fs, loc, sweep, geom) % Time-gated harmonic distortion.
        g = harmonic_geometry_(obj, sweep, maxOrder) % Where the harmonic products wrap, and where the linear response ends.
        y = zero_phase_bandpass_(obj, x, filt) % filtfilt padded to the filter's own settling time.
        r = estimate_reflections_(obj, h, fs, loc, maxCount) % Discrete arrivals after the direct sound.
        d = decay_times_(obj, h, fs, noisePower) % Schroeder EDC, EDT/T20/T30.
        out = smooth_to_log_grid_(obj, fax, vals, grid, fracOct, mode) % Fractional-octave average onto a log grid.
        stats = repeatability_stats_(obj, values) % Summarize repeatability statistics.
        m = estimate_headroom_(obj, excitation, response) % Estimate clipping and headroom margins.
        out = aggregate_headroom_(obj, metricsArray) % Aggregate headroom metrics over repeats.
        m = sweep_transfer_rms_(obj, x, y, freqs, fs, band) % Equivalent steady-tone RMS from a swept-sine pair.
        y = trim_response_(obj, y) % Trim trailing response buffer padding.
        cd = commit_cal_data_(obj) % Build calibration output struct.
        reset_cancel_(obj) % Clear any pending cancellation request before starting a new run.
        throw_if_cancelled_(obj) % Pump the event queue and abort the run if cancel() was called.

        function t = empty_table_(~, n)
            % Allocate a calibration table struct for in-progress runs.
            % sd_db is the across-repeat spread of the level, NaN until a
            % second pass exists to compute one from; LiveUpdate.Table carries
            % it so the monitor can draw the convergence ribbon.
            t = struct('x', nan(1,n), 'measurement', nan(1,n), ...
                       'spl_db', nan(1,n), 'voltage', nan(1,n), ...
                       'sd_db', nan(1,n));
        end

        restore_from_struct_(obj, s) % Restore engine state from saved struct.
    end

    methods (Static)
        [eng, ffn] = load(ffn) % Load engine calibration from .esgc file; returns the resolved path.
        r = spectral_rms(x, freq, fs) % Estimate RMS amplitude at a frequency.
    end

    methods (Static, Access = private)
        function s = merge_struct_(s, add)
            % Overlay the fields of add onto s. Used to let a caller name only
            % the metrics it knows without dropping the engine-derived rest.
            if ~isstruct(add), return; end
            f = fieldnames(add);
            for k = 1:numel(f)
                s.(f{k}) = add.(f{k});
            end
        end

        function sd = level_sd_db_(measurements)
            % sd = level_sd_db_(measurements)
            % Across-repeat standard deviation of a level, in dB, for each
            % column of a repeats-by-points measurement matrix. 0 for a single
            % pass, which the monitor reads as "no spread measured" and skips.
            n  = size(measurements, 2);
            sd = nan(1, n);
            for i = 1:n
                v = measurements(:, i);
                v = v(isfinite(v) & v > 0);
                if numel(v) < 2, continue; end
                sd(i) = std(20 * log10(v));
            end
        end

        function s = rmfield_safe_(s, fname)
            % Remove struct field only when present.
            if isstruct(s) && isfield(s, fname)
                s = rmfield(s, fname);
            end
        end
    end
end
