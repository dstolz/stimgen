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
    %
    % Usage:
    %   adapter = stimgen.calibration.WindowsSoundCardAdapter();
    %   eng = stimgen.calibration.Engine(adapter);
    %   eng.set_configuration(ReferenceFrequency=1000);  % parameters are
    %                                    % SetAccess = protected; use this
    %   eng.calibrate_reference();
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
    % See also: stimgen.calibration.HwAdapter,
    %           stimgen.calibration.WindowsSoundCardAdapter,
    %           documentation/stimgen_calibration.md

    % --- Persistent calibration parameters ---
    properties (SetAccess = protected, SetObservable, AbortSet)
        MicSensitivity      (1,1) double {mustBePositive,mustBeFinite}      = 1     % V/Pa
        ReferenceLevel      (1,1) double {mustBePositive,mustBeFinite}      = 94    % dB SPL
        ReferenceFrequency  (1,1) double {mustBePositive,mustBeFinite}      = 1000  % Hz
        NormativeValue      (1,1) double {mustBePositive,mustBeFinite}      = 80    % dB SPL
        ExcitationVoltage   (1,1) double {mustBePositive}                   = 1     % V (<=10)
        ShowLivePlots       (1,1) logical                                   = false
        CalibrationTimestamp (1,1) datetime = datetime("")
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
        calibrate_reference(obj) % Measure microphone sensitivity from reference tone.
        calibrate_tones(obj, freqs, repeatCount, options) % Build tone calibration LUT.
        calibrate_clicks(obj, durs, repeatCount) % Build click calibration LUT.
        calibrate_swept_sine(obj, duration, freqs, repeatCount, tailDuration) % Run swept-sine calibration.
        design_filter(obj, source, options) % Design equalization filter from a frequency LUT.
        v = compute_adjusted_voltage(obj, type, value, level) % Interpolate LUT voltage.
        ffn = save(obj, ffn) % Save calibration to .esgc file; returns the resolved path.
        restore(obj, s) % Restore engine state from a serialized struct.
        cancel(obj) % Request cancellation of an in-progress calibration run.

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
            % Clear calibration plot axes.
            obj.plot_signal(true);
            obj.plot_spectrum(true);
            obj.plot_transfer('', [], true);
            drawnow;
        end

        plot_signal(obj, reset) % Plot current response waveform.
        plot_spectrum(obj, reset) % Plot current response spectrum.
        plot_transfer(obj, type, tableData, reset) % Plot transfer data overlays.
    end

    methods (Access = private)
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
            t = struct('x', nan(1,n), 'measurement', nan(1,n), ...
                       'spl_db', nan(1,n), 'voltage', nan(1,n));
        end

        restore_from_struct_(obj, s) % Restore engine state from saved struct.
    end

    methods (Static)
        [eng, ffn] = load(ffn) % Load engine calibration from .esgc file; returns the resolved path.
        r = spectral_rms(x, freq, fs) % Estimate RMS amplitude at a frequency.
    end

    methods (Static, Access = private)
        function f = cal_fig_(name)
            % Return/create named figure used by calibration plotting helpers.
            f = findobj('Type', 'figure', 'Name', name);
            if isempty(f)
                f = figure('Name', name, 'NumberTitle', 'off');
            end
            figure(f);
        end

        function s = rmfield_safe_(s, fname)
            % Remove struct field only when present.
            if isstruct(s) && isfield(s, fname)
                s = rmfield(s, fname);
            end
        end
    end
end
