classdef DMR < stimgen.StimType

    % obj = stimgen.DMR(Name,Value,...)
    % Dynamic moving ripple (DMR) and ripple noise (RN) stimulus generator.
    %
    % Class guide: documentation/stimgen_StimTypes.md#dmr
    %
    % A DMR is a broadband sound whose spectrotemporal envelope is a single
    % sinusoidal ripple on a log-frequency axis whose ripple density Omega(t)
    % (cycles/octave) and temporal modulation rate Fm(t) (Hz) wander slowly
    % and randomly over time. Ripple noise is the same carrier bank driven by
    % the sum of several independent DMR envelopes: the same long-term
    % statistics without the local structure. Both exist for reverse
    % correlation, so everything needed to reconstruct the envelope that was
    % played is kept (see generation_record, envelope_at, export_envelope).
    %
    % Reference:
    %   Escabi MA, Schreiner CE (2002) "Nonlinear spectrotemporal sound
    %   analysis by neurons in the auditory midbrain." J Neurosci
    %   22(10):4114-4131. doi:10.1523/JNEUROSCI.22-10-04114.2002
    %   Equation numbers in the comments below refer to that paper.
    %
    % Synthesis. Carriers f_k are geometrically spaced from LowFrequency,
    % f_k = alpha f_(k-1) with alpha = (HighFrequency/LowFrequency)^(1/NumCarriers),
    % at tonotopic positions X_k = log2(f_k/f_1) octaves. The envelope, in dB, is
    %
    %   S_DMR(t,X_k) = M/2 sin(2 pi Omega(t) X_k + Phi(t))               [Eq. 1]
    %   Phi(t)       = 2 pi * integral from 0 to t of Fm
    %
    % and for ripple noise, with L = NumEnvelopes independent envelopes,
    %
    %   Sbar_RN(t,X_k) = 1/sqrt(L) sum_l S_DMR,l(t,X_k)                  [Eq. 2]
    %   S_RN(t,X_k)    = M/2 erf(Sbar_RN / (c sigma_DMR)),  sigma_DMR = M/sqrt(8)   [Eq. 3]
    %
    % The waveform sums the carriers, each at a random phase, with the
    % envelope converted to linear amplitude:
    %
    %   s(t) = sum_k 10^((S(t,X_k) - M/2)/20) sin(2 pi f_k t + phi_k)    [Eq. 4-5]
    %
    % Parameter trajectories. As in the paper, Omega and Fm each start as a
    % sequence of normally distributed values, sampled at twice the property
    % "...ChangeRate" (6 Hz and 3 Hz at the defaults), interpolated between
    % those knots with cubic convolution, mapped through erf onto -1..1 and
    % rescaled linearly to the Min..Max interval.
    %
    % Where this class reads or departs from the paper as printed. Each of
    % these is also named in every generation record (rec.Rules):
    %   Phase      - Eq. 1 prints Phi = integral of Fm, without 2 pi. Fm is in
    %                Hz and Eq. 7 has 2 pi Fm tau, so Phi = 2 pi integral Fm.
    %   Carriers   - the paper gives alpha = 1.01617, "43 carriers per octave",
    %                230 carriers over 500-20,000 Hz. (20000/500)^(1/230) is
    %                1.016168; 2^(1/43) is 1.016250. So the grid is NumCarriers
    %                steps of alpha from LowFrequency, with HighFrequency the
    %                (unplayed) end of the range: the top carrier is
    %                HighFrequency/alpha.
    %   erf scale  - the paper says erf maps normally distributed amplitudes
    %                onto uniformly distributed ones: Omega and Fm flat over
    %                their ranges, and sigma_RN^2 = M^2/12, the variance of a
    %                uniform distribution on [-M/2, M/2]. For a normal variable
    %                of standard deviation sigma that is erf(x/(sqrt(2) sigma)),
    %                with sigma the standard deviation of the signal erf is
    %                applied to: sigma_DMR = M/sqrt(8) for the ripple-noise sum,
    %                and sqrt(57/70) = 0.902 -- not 1 -- for the knot sequence,
    %                because erf is applied after the interpolation and
    %                interpolating between unit-variance knots lowers the
    %                variance (KnotInterpolantVariance). The equations are
    %                printed as erf(x/sigma_DMR) and erf(x), which give
    %                sigma_RN^2 = M^2/8.61 and trajectories that spend more
    %                time near their limits (variance 0.104 of range^2, against
    %                1/12 = 0.083 for flat). ErfScaling selects: "Uniform"
    %                (default) or "AsPrinted". The trajectories the paper
    %                shows (Fig. 2A,B) are flat; see the class guide.
    %   Interpolant- the paper used interp1's 'cubic' option, whose meaning
    %                has changed between MATLAB releases. Cubic convolution
    %                (Keys, a = -1/2) is written out here so the generator
    %                does not depend on the release.
    %   Integral   - the paper does not say how the integral for Phi was
    %                evaluated. Here it is a fixed 32-point Gauss-Legendre
    %                rule per knot interval, accumulated at the knots, which
    %                makes Phi(t) a function of t alone -- independent of Fs
    %                and of the grid it is asked for on.
    %   Random numbers - not specified in the paper. See "Draw contract".
    % The paper generated at 44.1 kHz and presented the stimulus continuously
    % for 10-20 min with an independent sequence per ear. This class makes
    % one-channel segments of Duration seconds; it reproduces the published
    % method, not the authors' stimulus files.
    %
    % Segments and seeds. Each Seed is one realization, starting at Phi = 0.
    % Vectorizing Seed (Seed = 1:40) makes each seed a variant, so a
    % StimPlayer run presents a different segment per trial and logs which.
    % Seed must be a non-negative integer: there is no "reseed randomly"
    % value, because a stimulus whose seed was never recorded cannot be
    % reconstructed.
    %
    % Versions. GeneratorVersion 2 is the first to scale the trajectories by
    % the interpolated sequence's standard deviation under "Uniform".
    % Version 1 divided by sqrt(2) alone, as if that deviation were 1, which
    % left Omega and Fm weighted toward mid-range (variance 0.073 of range^2)
    % and the long-term envelope correlation wider than the paper's Eq. 9. A
    % version 1 generation record still rebuilds its own waveform: it holds
    % the divisor that was used.
    %
    % Draw contract (GeneratorVersion). A waveform is a pure function of the
    % properties, Fs and GeneratorVersion. Random numbers come from a private
    % RandStream('mrg32k3a','Seed',Seed,'NormalTransform','Inversion') -- the
    % global stream is never touched -- with one substream per quantity:
    %   substream 1          carrier phases, 2 pi rand(1,NumCarriers)
    %   substream 10*l + 1   envelope l, ripple-density knots, randn
    %   substream 10*l + 2   envelope l, modulation-rate knots, randn
    % so changing the carrier count, the number of envelopes or Duration
    % leaves the other draws as they were (a longer Duration appends knots).
    % Any change to the generator, the substream map, the knot grid, the
    % interpolant, the erf mapping, the phase quadrature, the carrier grid,
    % the amplitude expression, the RN combination or the summation order
    % changes the waveform a seed produces and must bump GeneratorVersion.
    %
    % Level. SoundLevel is the overall rms level of the segment, as for
    % stimgen.Noise and stimgen.TORC. Each segment is normalized to its own
    % rms before calibration; RawRms and RawPeak hold the figures before
    % that normalization.
    %
    % Cost. Synthesis is NumCarriers * (NumEnvelopes + 2) transcendental
    % evaluations per sample, in blocks of BlockSize samples. The last
    % synthesis is cached, so presenting the same seed again, or editing only
    % SoundLevel, the gate or the calibration, does not synthesize again.
    %
    % Example:
    %   s = stimgen.DMR('Duration', 5, 'Seed', 1:40);   % 40 five-second segments
    %   s.update_signal;
    %   s.plot_dynamic_spectrum
    %   rec = s.generation_record();                    % what Signal was made from
    %
    % See also: stimgen.TORC, stimgen.StimType/generation_record

    % ================================================================== %
    % PAPER VALUES -- Escabi & Schreiner (2002), Materials and Methods,
    % "Acoustic stimuli". Every default below except ErfScaling and Seed is
    % the value the paper states. They are the property defaults (not
    % constructor arguments) so that current_parameter_summary, which
    % compares against the class defaults, reports only departures from the
    % paper.
    % ================================================================== %
    properties (SetObservable,AbortSet)
        LowFrequency  (1,1) double {mustBePositive,mustBeFinite} = 500;   % Hz, f_1
        HighFrequency (1,1) double {mustBePositive,mustBeFinite} = 20000; % Hz, end of the 5.32-octave range
        NumCarriers   (1,1) double {mustBeInteger,mustBeGreaterThanOrEqual(NumCarriers,2),mustBeFinite} = 230;

        EnvelopeMode  (1,1) string {mustBeMember(EnvelopeMode,["DMR","RippleNoise"])} = "DMR";
        NumEnvelopes  (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 16; % L of Eq. 2; read in RippleNoise mode

        RippleDensityMin        (1,1) double {mustBeFinite} = 0;               % cycles/octave
        RippleDensityMax        (1,1) double {mustBeFinite} = 4;               % cycles/octave
        RippleDensityChangeRate (1,1) double {mustBePositive,mustBeFinite} = 3;   % Hz; knots at twice this

        ModulationRateMin        (1,1) double {mustBeFinite} = -350;           % Hz
        ModulationRateMax        (1,1) double {mustBeFinite} = 350;            % Hz
        ModulationRateChangeRate (1,1) double {mustBePositive,mustBeFinite} = 1.5; % Hz; knots at twice this

        ModulationDepth (1,:) double {mustBePositive,mustBeFinite} = 30;       % dB peak-to-peak, M (paper: 30 or 45)

        % Not paper values. ErfScaling chooses between the paper's stated
        % statistics and its equations as printed (see the class help).
        ErfScaling (1,1) string {mustBeMember(ErfScaling,["Uniform","AsPrinted"])} = "Uniform";
        Seed (1,:) double {mustBeInteger,mustBeNonnegative,mustBeLessThan(Seed,4294967296)} = 1;
    end
    % ================================================================== %

    % Derived by update_signal. Deliberately neither SetObservable (writing
    % them must not retrigger the update) nor listed in UserProperties (they
    % are recomputed, not restored).
    properties (SetAccess = protected)
        CarrierFrequencies (1,:) double = [];  % Hz
        CarrierPhases      (1,:) double = [];  % rad
        OctaveAxis         (1,:) double = [];  % octaves above LowFrequency
        RawRms             (1,1) double = NaN; % rms of the synthesized sum, before normalization
        RawPeak            (1,1) double = NaN; % max(abs()) of the synthesized sum, before normalization
    end

    properties (Constant)
        CalibrationType = "filter";
        Normalization   = "rms";

        % Version of the draw contract in the class help. Written into every
        % generation record and envelope export.
        GeneratorVersion = 2;

        % Variance, averaged over time, of the cubic-convolution interpolant
        % of independent unit-variance knots: the integral over one knot
        % interval of the sum of the four squared kernel weights, which is
        % exactly 57/70. It is 1 at a knot and 0.64 midway between two. The
        % "Uniform" erf scaling divides the interpolated sequence by the
        % square root of this before erf, which is what makes Omega and Fm
        % flat over their ranges.
        KnotInterpolantVariance = 57/70;

        % Samples synthesized per pass. Bounds the working memory (the
        % quadrature holds QuadratureOrder values per sample per envelope);
        % the waveform does not depend on it, because every sample is a
        % function of its own time only.
        BlockSize = 2^16;
    end

    properties (Access = private)
        plan_   = []   % what the waveform in Signal was synthesized from (see plan_from_)
        record_ = []   % the DMR half of generation_record, captured by update_signal
    end

    properties (Access = private, Transient)
        cache_ = []    % struct('key','raw','plan'): the last synthesis, before normalization
    end


    methods

        function obj = DMR(varargin)
            % Defaults first, caller's pairs last, so a caller's value wins.
            obj = obj@stimgen.StimType( ...
                'DisplayName', 'Dynamic Moving Ripple', ...
                'UserProperties', ["SoundLevel","Duration","WindowDuration","ApplyWindow", ...
                    "LowFrequency","HighFrequency","NumCarriers", ...
                    "EnvelopeMode","NumEnvelopes", ...
                    "RippleDensityMin","RippleDensityMax","RippleDensityChangeRate", ...
                    "ModulationRateMin","ModulationRateMax","ModulationRateChangeRate", ...
                    "ErfScaling","ModulationDepth","Seed"], ...
                ... % Toolbox choices, not paper values. One second keeps the
                ... % default cheap to generate; the paper's short segment was 5 s.
                'Duration', 1, ...
                ... % The carriers start at random phases, so an ungated
                ... % segment starts and ends with a step.
                'WindowDuration', 0.010, ...
                varargin{:});
        end


        function update_signal(obj)
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            started = tic;

            % Until this generation has finished, there is no record that
            % describes Signal.
            obj.record_ = [];

            p = obj.resolve_parameters_();

            % The synthesized sum is a pure function of p, so the last one is
            % reused when p has not changed: the same seed presented again,
            % or an edit to SoundLevel, the gate or the calibration.
            % Everything after it runs either way, so a cached and a fresh
            % generation go through identical arithmetic.
            cacheHit = ~isempty(obj.cache_) && isequal(obj.cache_.key, p);
            if cacheHit
                plan = obj.cache_.plan;
                raw  = obj.cache_.raw;
            else
                plan = stimgen.DMR.plan_from_(p);
                raw  = stimgen.DMR.render_(plan);
                obj.cache_ = struct('key', p, 'raw', raw, 'plan', plan);
                obj.log_nyquist_margin_(plan);
            end

            rawRms  = sqrt(mean(raw .^ 2));
            rawPeak = max(abs(raw));

            obj.plan_              = plan;
            obj.CarrierFrequencies = plan.CarrierFrequencies;
            obj.CarrierPhases      = plan.CarrierPhases;
            obj.OctaveAxis         = plan.OctaveAxis;
            obj.RawRms             = rawRms;
            obj.RawPeak            = rawPeak;

            obj.Signal = raw;

            obj.apply_normalization;

            obj.apply_calibration;

            obj.apply_gate;

            obj.record_ = obj.build_record_(plan, rawRms, rawPeak, cacheHit, toc(started));
        end


        function rec = generation_record(obj)
            % rec = generation_record(obj)
            % What the waveform currently in Signal was generated from: the
            % base record (see stimgen.StimType/generation_record) plus
            % everything needed to reconstruct the envelope and the waveform
            % without this class's random number generator.
            %
            % The DMR fields are the ones update_signal captured when it made
            % Signal, not values recomputed now, so they describe that
            % waveform even if properties have been edited under hold_updates
            % since. Generated is false, and they are absent, when no
            % waveform has been generated.
            %
            % Returns rec with the base fields and:
            %   GeneratorVersion  - the draw contract the waveform follows
            %   Generated         - true when the fields below are present
            %   GeneratedVariantIndex - the combination update_signal had locked
            %   Seed, Generator, NormalTransform, Substreams
            %   EnvelopeMode, NumEnvelopes, ErfScaling
            %   ErfDivisor        - c of the ripple-noise compression,
            %                       erf(Sbar / (c * M/sqrt(8)))
            %   TrajectoryErfDivisor - what each knot interpolant is divided
            %                       by before erf
            %   ModulationDepth, Duration
            %   LowFrequency, HighFrequency, NumCarriers
            %   CarrierFrequencies, CarrierPhases, OctaveAxis
            %   RippleDensityRange, ModulationRateRange  - [min max]
            %   RippleKnotRate, RateKnotRate             - Hz
            %   Envelope(l)       - RippleKnotTimes, RippleKnots, RateKnotTimes,
            %                       RateKnots (the normal draws), RateKnotCycles
            %                       (integral of Fm, in cycles, from 0 to each
            %                       knot interval's start)
            %   QuadratureNodes, QuadratureWeights - the rule behind
            %                       RateKnotCycles and the phase, on (0,1)
            %   Rules             - struct of text: Interpolation, ErfMapping,
            %                       PhaseIntegration, AmplitudeMapping,
            %                       Combination, Phase
            %   RawRms, RawPeak   - of the synthesized sum, before normalization
            %   Gate              - Applied, WindowFcn, WindowDuration (s), NumSamples
            %   NyquistMarginHz   - Fs/2 minus the top carrier
            %   GenerationSeconds - wall time update_signal took
            %   CacheHit          - true when the synthesis was reused
            rec = generation_record@stimgen.StimType(obj);
            rec.GeneratorVersion = stimgen.DMR.GeneratorVersion;
            rec.Generated        = ~isempty(obj.record_);
            if ~rec.Generated
                return
            end
            fn = fieldnames(obj.record_);
            for i = 1:numel(fn)
                rec.(fn{i}) = obj.record_.(fn{i});
            end
        end


        function [S, x] = envelope_at(obj, t)
            % [S, x] = envelope_at(obj, t)
            % The spectrotemporal envelope that drove the current Signal, in
            % dB, at arbitrary times.
            %
            % This is the envelope of Eq. 1 (DMR) or Eq. 3 (ripple noise): dB
            % about the middle of its range, so -M/2 <= S <= M/2. It is NOT
            % gated -- the onset/offset window is applied to the waveform
            % afterwards and is described by generation_record().Gate -- and
            % it is the same function of t that synthesis evaluated, at any
            % sampling the analysis needs.
            %
            % Parameters:
            %   t - times in seconds, 0 <= t <= the signal's duration.
            %
            % Returns:
            %   S - NumCarriers-by-numel(t) envelope, dB.
            %   x - 1-by-NumCarriers tonotopic axis, octaves above LowFrequency.
            plan = obj.current_plan_();
            t = reshape(double(t), 1, []);
            stimgen.DMR.assert_times_in_range_(plan, t);

            x = plan.OctaveAxis;
            S = zeros(numel(x), numel(t));
            B = stimgen.DMR.BlockSize;
            for i0 = 1:B:numel(t)
                idx = i0:min(i0 + B - 1, numel(t));
                [om, cyc] = stimgen.DMR.trajectories_(plan, t(idx));
                for k = 1:numel(x)
                    S(k, idx) = stimgen.DMR.envelope_db_(plan, x(k), om, cyc);
                end
            end
        end


        function [S, t, x] = dynamic_spectrum(obj, nTime)
            % [S, t, x] = dynamic_spectrum(obj)
            % [S, t, x] = dynamic_spectrum(obj, nTime)
            % The envelope of the current Signal on an even time grid: the
            % same contract as stimgen.TORC/dynamic_spectrum. For chosen
            % times, or a chosen sample rate, use envelope_at.
            %
            % Parameters:
            %   nTime - Number of time samples (default: the signal length,
            %           which is a NumCarriers-by-N matrix -- pass a count).
            %
            % Returns:
            %   S - NumCarriers-by-nTime envelope, dB about mid-range.
            %   t - 1-by-nTime time axis, seconds: (0:nTime-1)*(duration/nTime).
            %   x - 1-by-NumCarriers tonotopic axis, octaves above LowFrequency.
            plan = obj.current_plan_();
            if nargin < 2 || isempty(nTime)
                nTime = plan.N;
            end
            dur = plan.N / plan.Fs;
            t   = (0:nTime-1) .* (dur/nTime);
            [S, x] = obj.envelope_at(t);
        end


        function tr = ripple_trajectory(obj, nTime)
            % tr = ripple_trajectory(obj)
            % tr = ripple_trajectory(obj, nTime)
            % The ripple parameters behind the current Signal on an even time
            % grid (the grid dynamic_spectrum uses).
            %
            % Parameters:
            %   nTime - Number of time samples (default: 1000).
            %
            % Returns:
            %   tr.t     - 1-by-nTime time axis, seconds
            %   tr.Omega - L-by-nTime ripple density, cycles/octave
            %   tr.Fm    - L-by-nTime temporal modulation rate, Hz
            %   tr.Phase - L-by-nTime Phi(t), radians (2 pi * integral of Fm)
            % with one row per envelope: L is 1 for a DMR and NumEnvelopes
            % for ripple noise.
            plan = obj.current_plan_();
            if nargin < 2 || isempty(nTime)
                nTime = 1000;
            end
            dur = plan.N / plan.Fs;
            t   = (0:nTime-1) .* (dur/nTime);
            [om, cyc, fm] = stimgen.DMR.trajectories_(plan, t);
            tr = struct('t', t, 'Omega', om, 'Fm', fm, 'Phase', 2*pi*cyc);
        end


        function file = export_envelope(obj, file, options)
            % file = export_envelope(obj, file)
            % file = export_envelope(obj, file, 'SampleRate', 4000, 'Combinations', [])
            % Write the envelope, the ripple parameters and the generation
            % record of every variant combination (every seed) to one MAT
            % file, so an analysis does not depend on this class
            % regenerating the same numbers later.
            %
            % Each combination is generated on a pinned copy of the stimulus
            % (the combination viewer's pattern), so this object's Signal,
            % active combination and selection order are untouched. It is
            % generated in full, not just planned, so the file carries each
            % segment's RawRms.
            %
            % Parameters:
            %   file         - output path; ".mat" is added if it has no extension.
            %                  An existing file is replaced.
            %   SampleRate   - envelope sampling rate in Hz (default 4000, the
            %                  rate the paper sampled its envelopes at for the
            %                  STRF). Must be at least twice the fastest
            %                  modulation rate, or the ripple aliases.
            %   Combinations - variant indices to write (default: all).
            %
            % Returns:
            %   file - the path written, as a string.
            %
            % File layout (MAT version 7.3, so one combination can be read
            % without loading the rest; everything double precision):
            %   FormatVersion        1
            %   GeneratorVersion     the draw contract the waveforms follow
            %   CreatedAt            'yyyy-mm-ddTHH:MM:SS', local time
            %   Source               this stimulus's toStruct -- restore it
            %                        with stimgen.StimType.fromStruct
            %   EnvelopeFs           the SampleRate used, Hz
            %   Gated                false: envelopes are before the onset/
            %                        offset gate, which each Record describes
            %   EnvelopeUnits        text
            %   Seed, VariantIndex, RawRms, RawPeak
            %                        one value per combination written
            %   CombinationVariables names of the per-combination variables
            %   C0001, C0002, ...    one struct per combination, named by its
            %                        variant index, with fields:
            %       Seed, VariantIndex
            %       Time               1-by-nT, s: (0:nT-1)/EnvelopeFs
            %       OctaveAxis         1-by-K, octaves above LowFrequency
            %       CarrierFrequencies 1-by-K, Hz
            %       Envelope           K-by-nT, dB (envelope_at(Time))
            %       Omega, Fm, Phase   L-by-nT: cycles/octave, Hz, rad
            %       Record             generation_record() of that segment
            arguments
                obj  (1,1) stimgen.DMR
                file (1,1) string
                options.SampleRate   (1,1) double {mustBePositive,mustBeFinite} = 4000
                options.Combinations (1,:) double {mustBeInteger,mustBePositive} = double.empty(1,0)
            end

            [folder, name, ext] = fileparts(file);
            if strlength(ext) == 0
                file = fullfile(folder, name + ".mat");
            end
            file  = string(file);
            fsEnv = options.SampleRate;

            % One copy, reselection off, pinned combination by combination.
            pinned = copy(obj);
            pinned.VariantReselectOnUpdate = false;
            info = pinned.get_variant_info();
            nAll = max(1, info.NumCombinations);
            combos = options.Combinations;
            if isempty(combos)
                combos = 1:nAll;
            end
            if any(combos > nAll)
                error('stimgen:DMR:CombinationOutOfRange', ...
                    'Combinations must be between 1 and %d, the number of variant combinations.', nAll);
            end

            % Checked before anything is written. The modulation-rate limits
            % are scalar properties, the same for every combination.
            fastest = max(abs([obj.ModulationRateMin, obj.ModulationRateMax]));
            if fsEnv < 2 * fastest
                error('stimgen:DMR:EnvelopeRateTooLow', ...
                    ['SampleRate (%g Hz) is less than twice the fastest modulation rate ' ...
                     '(%g Hz), so the exported envelope would alias. Use at least %g Hz.'], ...
                    fsEnv, fastest, 2 * fastest);
            end

            header = struct();
            header.FormatVersion    = 1;
            header.GeneratorVersion = stimgen.DMR.GeneratorVersion;
            header.CreatedAt        = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
            header.Source           = obj.toStruct();
            header.EnvelopeFs       = fsEnv;
            header.Gated            = false;
            header.EnvelopeUnits    = ['dB about the middle of the envelope range (-M/2 to M/2), ' ...
                                       'before the onset/offset gate'];
            save(file, '-struct', 'header', '-v7.3');

            n = numel(combos);
            index = struct('Seed', zeros(1, n), 'VariantIndex', zeros(1, n), ...
                           'RawRms', zeros(1, n), 'RawPeak', zeros(1, n), ...
                           'CombinationVariables', strings(1, n));
            for i = 1:n
                pinned.set_variant_index(combos(i));
                rec = pinned.generation_record();

                plan = pinned.plan_;
                t = (0:floor(rec.Duration * fsEnv)) ./ fsEnv;
                t = t(t <= rec.Duration);
                [S, x]        = pinned.envelope_at(t);
                [om, cyc, fm] = stimgen.DMR.trajectories_(plan, t);

                combo = struct();
                combo.Seed               = rec.Seed;
                combo.VariantIndex       = combos(i);
                combo.Time               = t;
                combo.OctaveAxis         = x;
                combo.CarrierFrequencies = rec.CarrierFrequencies;
                combo.Envelope           = S;
                combo.Omega              = om;
                combo.Fm                 = fm;
                combo.Phase              = 2*pi*cyc;
                combo.Record             = rec;

                % Appended one combination at a time, so only one envelope
                % matrix is ever held in memory.
                varName = sprintf('C%04d', combos(i));
                part = struct();
                part.(varName) = combo;
                save(file, '-struct', 'part', '-append');

                index.Seed(i)                 = rec.Seed;
                index.VariantIndex(i)         = combos(i);
                index.RawRms(i)               = rec.RawRms;
                index.RawPeak(i)              = rec.RawPeak;
                index.CombinationVariables(i) = string(varName);
                stimgen.util.vprintf(2, 'DMR: exported combination %d (seed %d) to %s', ...
                    combos(i), rec.Seed, char(file));
            end
            save(file, '-struct', 'index', '-append');
        end


        function h = plot_dynamic_spectrum(obj, ax, nTime)
            % h = plot_dynamic_spectrum(obj)
            % h = plot_dynamic_spectrum(obj, ax, nTime)
            % Display the envelope as an image, time in ms on the x-axis and
            % octaves above LowFrequency on the y-axis.
            %
            % Parameters:
            %   ax    - Target axes handle (default: gca).
            %   nTime - Time samples to render (default: 1000).
            %
            % Returns:
            %   h - Image handle.
            if nargin < 2 || isempty(ax), ax = gca; end
            if nargin < 3 || isempty(nTime), nTime = 1000; end

            [S, t, x] = obj.dynamic_spectrum(nTime);

            h = imagesc(ax, t*1e3, x, S);
            set(ax,'YDir','normal');
            xlabel(ax,'time (ms)');
            ylabel(ax,sprintf('octaves above %.0f Hz', obj.CarrierFrequencies(1)));
            c = colorbar(ax);
            c.Label.String = 'level (dB re mid-range)';
        end

    end % methods (public)


    methods (Access = protected)

        function m = propMeta(obj)
            % propMeta() - Display metadata for DMR GUI properties.
            m = struct();
            m.LowFrequency  = struct('label','Low Frequency (Hz)',  'format','%.1f Hz','limits',[1 100000], ...
                                     'tooltip',stimgen.util.tooltip(obj,'LowFrequency'),'order',10);
            m.HighFrequency = struct('label','High Frequency (Hz)', 'format','%.1f Hz','limits',[1 100000], ...
                                     'tooltip',stimgen.util.tooltip(obj,'HighFrequency'),'order',20);
            m.NumCarriers   = struct('label','Carriers',            'format','%.0f',   'limits',[2 5000], ...
                                     'tooltip',stimgen.util.tooltip(obj,'NumCarriers'),'order',30);
            m.EnvelopeMode  = struct('label','Envelope','widget','dropdown', ...
                                     'items',["DMR","RippleNoise"], ...
                                     'tooltip',stimgen.util.tooltip(obj,'EnvelopeMode'),'order',40);
            m.NumEnvelopes  = struct('label','Ripple Noise Envelopes','format','%.0f','limits',[1 1000], ...
                                     'tooltip',stimgen.util.tooltip(obj,'NumEnvelopes'),'order',50);

            m.RippleDensityMin        = struct('label','Ripple Density Min (cyc/oct)','format','%.2f','limits',[-100 100], ...
                                               'tooltip',stimgen.util.tooltip(obj,'RippleDensityMin'),'order',60);
            m.RippleDensityMax        = struct('label','Ripple Density Max (cyc/oct)','format','%.2f','limits',[-100 100], ...
                                               'tooltip',stimgen.util.tooltip(obj,'RippleDensityMax'),'order',70);
            m.RippleDensityChangeRate = struct('label','Ripple Density Change Rate (Hz)','format','%.2f Hz','limits',[0.001 1000], ...
                                               'tooltip',stimgen.util.tooltip(obj,'RippleDensityChangeRate'),'order',80);

            m.ModulationRateMin        = struct('label','Modulation Rate Min (Hz)','format','%.1f Hz','limits',[-10000 10000], ...
                                                'tooltip',stimgen.util.tooltip(obj,'ModulationRateMin'),'order',90);
            m.ModulationRateMax        = struct('label','Modulation Rate Max (Hz)','format','%.1f Hz','limits',[-10000 10000], ...
                                                'tooltip',stimgen.util.tooltip(obj,'ModulationRateMax'),'order',100);
            m.ModulationRateChangeRate = struct('label','Modulation Rate Change Rate (Hz)','format','%.2f Hz','limits',[0.001 1000], ...
                                                'tooltip',stimgen.util.tooltip(obj,'ModulationRateChangeRate'),'order',110);

            m.ErfScaling = struct('label','erf Scaling','widget','dropdown', ...
                                  'items',["Uniform","AsPrinted"], ...
                                  'tooltip',stimgen.util.tooltip(obj,'ErfScaling'),'order',120);
            m.Seed       = struct('label','Seed','format','%.0f','limits',[0 4294967295], ...
                                  'tooltip',stimgen.util.tooltip(obj,'Seed'),'order',130);

            m.ModulationDepth = struct('label','Modulation Depth (dB pk-pk)','format','%.1f dB', ...
                                       'limits',[0.1 120],'tooltip',stimgen.util.tooltip(obj,'ModulationDepth'), ...
                                       'group','Level','order',15);

            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.StimType(obj));
        end

    end % methods (Access = protected)


    methods (Access = private)

        function p = resolve_parameters_(obj)
            % p = resolve_parameters_(obj)
            % Everything the synthesized sum depends on, for the combination
            % update_signal has locked, validated. This struct is the cache
            % key: two calls that return equal structs make equal waveforms.
            p = struct();
            p.GeneratorVersion = stimgen.DMR.GeneratorVersion;
            p.Fs = double(obj.selected_value("Fs"));
            p.N  = max(1, round(p.Fs * double(obj.selected_value("Duration"))));

            p.LowFrequency  = double(obj.selected_value("LowFrequency"));
            p.HighFrequency = double(obj.selected_value("HighFrequency"));
            p.NumCarriers   = double(obj.selected_value("NumCarriers"));

            % EnvelopeMode and ErfScaling are scalar strings, never a variant
            % axis, so they are read directly.
            p.EnvelopeMode = string(obj.EnvelopeMode);
            if p.EnvelopeMode == "RippleNoise"
                p.NumEnvelopes = double(obj.selected_value("NumEnvelopes"));
            else
                p.NumEnvelopes = 1;   % a DMR is one envelope whatever NumEnvelopes holds
            end
            p.ErfScaling = string(obj.ErfScaling);

            p.RippleDensityMin        = double(obj.selected_value("RippleDensityMin"));
            p.RippleDensityMax        = double(obj.selected_value("RippleDensityMax"));
            p.RippleDensityChangeRate = double(obj.selected_value("RippleDensityChangeRate"));

            p.ModulationRateMin        = double(obj.selected_value("ModulationRateMin"));
            p.ModulationRateMax        = double(obj.selected_value("ModulationRateMax"));
            p.ModulationRateChangeRate = double(obj.selected_value("ModulationRateChangeRate"));

            p.ModulationDepth = double(obj.selected_value("ModulationDepth"));
            p.Seed            = double(obj.selected_value("Seed"));

            if p.HighFrequency <= p.LowFrequency
                error('stimgen:DMR:InvalidRange', ...
                    'HighFrequency (%g Hz) must be greater than LowFrequency (%g Hz).', ...
                    p.HighFrequency, p.LowFrequency);
            end
            if p.RippleDensityMax < p.RippleDensityMin
                error('stimgen:DMR:InvalidRange', ...
                    'RippleDensityMax (%g cycles/octave) must not be less than RippleDensityMin (%g).', ...
                    p.RippleDensityMax, p.RippleDensityMin);
            end
            if p.ModulationRateMax < p.ModulationRateMin
                error('stimgen:DMR:InvalidRange', ...
                    'ModulationRateMax (%g Hz) must not be less than ModulationRateMin (%g Hz).', ...
                    p.ModulationRateMax, p.ModulationRateMin);
            end

            % The top carrier is one step of alpha below HighFrequency.
            fTop = p.HighFrequency / (p.HighFrequency / p.LowFrequency)^(1 / p.NumCarriers);
            if fTop >= p.Fs/2
                error('stimgen:DMR:BandwidthExceedsNyquist', ...
                    ['The top carrier (%.0f Hz) reaches or exceeds the Nyquist frequency ' ...
                     '(%.0f Hz). Lower HighFrequency or raise Fs.'], fTop, p.Fs/2);
            end
        end


        function plan = current_plan_(obj)
            % plan = current_plan_(obj)
            % The plan behind the waveform in Signal, generating it first if
            % nothing has been generated yet.
            if isempty(obj.plan_) || isempty(obj.Signal)
                obj.update_signal();
            end
            plan = obj.plan_;
            if isempty(plan)
                error('stimgen:DMR:NotGenerated', ...
                    'The stimulus has not been generated, so it has no envelope to report.');
            end
        end


        function rec = build_record_(obj, plan, rawRms, rawPeak, cacheHit, seconds)
            % rec = build_record_(obj, plan, rawRms, rawPeak, cacheHit, seconds)
            % The DMR half of generation_record, taken while update_signal
            % still has the combination locked -- so the gate values read
            % here are the ones apply_gate just used.
            [xi, wq] = stimgen.DMR.gauss_legendre_();

            applied = logical(obj.selected_value("ApplyWindow"));
            gate = struct( ...
                'Applied',        applied, ...
                'WindowFcn',      string(obj.WindowFcn), ...
                'WindowDuration', double(obj.effective_window_duration_()), ...
                'NumSamples',     0);
            if applied
                % What apply_gate applied: the whole window, or -- when the
                % window is longer than the signal -- one shrunk to fit.
                nGate = numel(obj.Window);
                if nGate > plan.N
                    nGate = plan.N - rem(plan.N, 2);
                end
                gate.NumSamples = nGate;
            end

            rec = struct();
            rec.GeneratedVariantIndex = obj.variantActiveIdx_;
            rec.Seed                  = plan.Seed;
            rec.Generator             = plan.Generator;
            rec.NormalTransform       = plan.NormalTransform;
            rec.Substreams            = plan.Substreams;
            rec.EnvelopeMode          = plan.EnvelopeMode;
            rec.NumEnvelopes          = plan.NumEnvelopes;
            rec.ErfScaling            = plan.ErfScaling;
            rec.ErfDivisor            = plan.ErfDivisor;
            rec.TrajectoryErfDivisor  = plan.TrajectoryErfDivisor;
            rec.ModulationDepth       = plan.ModulationDepth;
            rec.Duration              = plan.N / plan.Fs;
            rec.LowFrequency          = plan.LowFrequency;
            rec.HighFrequency         = plan.HighFrequency;
            rec.NumCarriers           = numel(plan.CarrierFrequencies);
            rec.CarrierFrequencies    = plan.CarrierFrequencies;
            rec.CarrierPhases         = plan.CarrierPhases;
            rec.OctaveAxis            = plan.OctaveAxis;
            rec.RippleDensityRange    = plan.RippleDensityRange;
            rec.ModulationRateRange   = plan.ModulationRateRange;
            rec.RippleKnotRate        = plan.RippleKnotRate;
            rec.RateKnotRate          = plan.RateKnotRate;
            rec.Envelope              = plan.Envelope;
            rec.QuadratureNodes       = xi;
            rec.QuadratureWeights     = wq;
            rec.Rules                 = plan.Rules;
            rec.RawRms                = rawRms;
            rec.RawPeak               = rawPeak;
            rec.Gate                  = gate;
            rec.NyquistMarginHz       = plan.Fs/2 - plan.CarrierFrequencies(end);
            rec.GenerationSeconds     = seconds;
            rec.CacheHit              = cacheHit;
        end


        function log_nyquist_margin_(~, plan)
            % log_nyquist_margin_(plan)
            % Say so, once per synthesis, when the room between the top
            % carrier and Nyquist is less than the fastest modulation rate:
            % the first-order modulation sidebands of the top carriers then
            % reach past Fs/2 and alias. (Higher-order sidebands of the
            % exponential envelope reach further; this checks only the first.)
            margin = plan.Fs/2 - plan.CarrierFrequencies(end);
            fastest = max(abs(plan.ModulationRateRange));
            if margin < fastest
                stimgen.util.vprintf(1, ...
                    ['DMR: the top carrier (%.0f Hz) is %.0f Hz below Nyquist, less than the ' ...
                     'fastest modulation rate (%.0f Hz); modulation sidebands of the top ' ...
                     'carriers alias. Lower HighFrequency or raise Fs.'], ...
                    plan.CarrierFrequencies(end), margin, fastest);
            end
        end

    end % methods (Access = private)


    methods (Static, Access = private)

        function plan = plan_from_(p)
            % plan = plan_from_(p)
            % Draw every random quantity and lay out everything synthesis
            % reads, without synthesizing. p is resolve_parameters_'s struct.
            %
            % THE DRAW CONTRACT LIVES HERE (and in the class help). Changing
            % anything below changes the waveform a seed produces: bump
            % GeneratorVersion.
            rs = RandStream('mrg32k3a', 'Seed', p.Seed, 'NormalTransform', 'Inversion');

            % --- Carriers: geometric steps of alpha from LowFrequency ---
            nC = p.NumCarriers;
            X  = log2(p.HighFrequency / p.LowFrequency);   % octaves spanned
            x  = (0:nC-1) .* (X / nC);                     % X_k = log2(f_k/f_1)
            fc = p.LowFrequency .* 2.^x;                   % f_k = alpha^(k-1) f_1

            rs.Substream = 1;
            phi = 2*pi*rand(rs, 1, nC);

            % --- Parameter knots ---
            % Knots sit at j/rate for j = -1, 0, 1, ...; the interpolant at a
            % time in [j, j+1)/rate reads knots j-1 .. j+2, so one knot
            % before zero and enough after the end keep every stimulus
            % sample on the interior formula.
            T       = p.N / p.Fs;
            omRate  = 2 * p.RippleDensityChangeRate;
            fmRate  = 2 * p.ModulationRateChangeRate;
            nOm     = floor(T * omRate) + 5;
            nFm     = floor(T * fmRate) + 5;
            c       = stimgen.DMR.erf_divisor_(p.ErfScaling);
            dTraj   = stimgen.DMR.trajectory_divisor_(p.ErfScaling);
            fmRange = [p.ModulationRateMin, p.ModulationRateMax];
            [xi, wq] = stimgen.DMR.gauss_legendre_();

            L = p.NumEnvelopes;
            env = repmat(struct('RippleKnotTimes', [], 'RippleKnots', [], ...
                                'RateKnotTimes', [], 'RateKnots', [], ...
                                'RateKnotCycles', []), 1, L);
            for l = 1:L
                rs.Substream = 10*l + 1;
                zOm = randn(rs, 1, nOm);
                rs.Substream = 10*l + 2;
                zFm = randn(rs, 1, nFm);

                % Integral of Fm over each whole knot interval, in cycles,
                % accumulated: RateKnotCycles(j+1) is the integral from 0 to
                % the start of interval j.
                nI = nFm - 3;                        % intervals j = 0 .. nI-1
                J  = repmat(0:nI-1, numel(xi), 1);
                S  = repmat(xi(:), 1, nI);
                F  = stimgen.DMR.map_(stimgen.DMR.kernel_(zFm, J, S), dTraj, fmRange);
                cycles = [0, cumsum((wq * F) ./ fmRate)];

                env(l).RippleKnotTimes = (-1:nOm-2) ./ omRate;
                env(l).RippleKnots     = zOm;
                env(l).RateKnotTimes   = (-1:nFm-2) ./ fmRate;
                env(l).RateKnots       = zFm;
                env(l).RateKnotCycles  = cycles;
            end

            if p.EnvelopeMode == "RippleNoise"
                combination = sprintf(['ripple noise: Sbar = sum of %d DMR envelopes / sqrt(%d) (Eq. 2); ' ...
                    'S = M/2 * erf(Sbar / (ErfDivisor * M/sqrt(8))) (Eq. 3)'], L, L);
            else
                combination = "DMR: S = M/2 * sin(2*pi*Omega(t)*X_k + Phi(t)) (Eq. 1)";
            end

            plan = struct();
            plan.GeneratorVersion    = p.GeneratorVersion;
            plan.Fs                  = p.Fs;
            plan.N                   = p.N;
            plan.Seed                = p.Seed;
            plan.Generator           = "mrg32k3a";
            plan.NormalTransform     = string(rs.NormalTransform);
            plan.Substreams          = struct('CarrierPhases', 1, ...
                                              'RippleKnots', "10*l + 1", 'RateKnots', "10*l + 2");
            plan.EnvelopeMode        = p.EnvelopeMode;
            plan.NumEnvelopes        = L;
            plan.ErfScaling          = p.ErfScaling;
            plan.ErfDivisor          = c;
            plan.TrajectoryErfDivisor = dTraj;
            plan.ModulationDepth     = p.ModulationDepth;
            plan.LowFrequency        = p.LowFrequency;
            plan.HighFrequency       = p.HighFrequency;
            plan.CarrierFrequencies  = fc;
            plan.CarrierPhases       = phi;
            plan.OctaveAxis          = x;
            plan.RippleDensityRange  = [p.RippleDensityMin, p.RippleDensityMax];
            plan.ModulationRateRange = fmRange;
            plan.RippleKnotRate      = omRate;
            plan.RateKnotRate        = fmRate;
            plan.Envelope            = env;
            plan.Rules               = struct( ...
                'Interpolation',    "cubic convolution (Keys, a = -1/2) over knots j-1..j+2, knot j at j/KnotRate", ...
                'ErfMapping',       "value = min + (max - min) * (erf(knot interpolant / TrajectoryErfDivisor) + 1) / 2", ...
                'PhaseIntegration', sprintf("%d-point Gauss-Legendre per knot interval, accumulated at the knots (RateKnotCycles)", numel(xi)), ...
                'Phase',            "Phi(t) = 2*pi * integral of Fm from 0 to t; Phi(0) = 0", ...
                'AmplitudeMapping', "10^((S - M/2)/20), evaluated as exp(log(10)/20 * (S - M/2))", ...
                'Combination',      string(combination));
        end


        function y = render_(plan)
            % y = render_(plan)
            % Eq. 4: sum over carriers of linear envelope times carrier.
            % Blocks of BlockSize samples bound the working memory; one
            % carrier at a time within a block, so nothing of size
            % carriers-by-samples is ever held.
            N   = plan.N;
            fs  = plan.Fs;
            fc  = plan.CarrierFrequencies;
            phi = plan.CarrierPhases;
            x   = plan.OctaveAxis;
            M   = plan.ModulationDepth;
            dbToNeper = log(10) / 20;

            y = zeros(1, N);
            B = stimgen.DMR.BlockSize;
            for n0 = 0:B:N-1
                n = n0:min(n0 + B, N) - 1;
                t = n ./ fs;                 % the sample times (0:N-1)/Fs, block by block
                [om, cyc] = stimgen.DMR.trajectories_(plan, t);

                yb = zeros(1, numel(t));
                for k = 1:numel(fc)
                    S  = stimgen.DMR.envelope_db_(plan, x(k), om, cyc);
                    yb = yb + exp(dbToNeper .* (S - M/2)) .* sin(2*pi*fc(k).*t + phi(k));
                end
                y(n + 1) = yb;
            end
        end


        function [om, cyc, fm] = trajectories_(plan, t)
            % [om, cyc, fm] = trajectories_(plan, t)
            % Ripple density, integrated modulation rate and modulation rate
            % of every envelope at the times t (a row). Each is a function of
            % t alone.
            %
            % Returns (L-by-numel(t), one row per envelope):
            %   om  - ripple density, cycles/octave
            %   cyc - integral of Fm from 0 to t, cycles; Phi = 2*pi*cyc
            %   fm  - temporal modulation rate, Hz
            L  = plan.NumEnvelopes;
            c  = plan.TrajectoryErfDivisor;
            [xi, wq] = stimgen.DMR.gauss_legendre_();

            om  = zeros(L, numel(t));
            cyc = zeros(L, numel(t));
            fm  = zeros(L, numel(t));

            % Knot interval j and position s in [0,1) within it.
            uOm = t .* plan.RippleKnotRate;
            jOm = floor(uOm);
            sOm = uOm - jOm;

            uFm = t .* plan.RateKnotRate;
            jFm = floor(uFm);
            sFm = uFm - jFm;
            % Quadrature points of the partial interval [0, s] for every t.
            SQ = xi(:) * sFm;
            JQ = repmat(jFm, numel(xi), 1);

            for l = 1:L
                e = plan.Envelope(l);
                om(l, :) = stimgen.DMR.map_(stimgen.DMR.kernel_(e.RippleKnots, jOm, sOm), ...
                    c, plan.RippleDensityRange);
                fm(l, :) = stimgen.DMR.map_(stimgen.DMR.kernel_(e.RateKnots, jFm, sFm), ...
                    c, plan.ModulationRateRange);
                F = stimgen.DMR.map_(stimgen.DMR.kernel_(e.RateKnots, JQ, SQ), ...
                    c, plan.ModulationRateRange);
                cyc(l, :) = e.RateKnotCycles(jFm + 1) + (sFm ./ plan.RateKnotRate) .* (wq * F);
            end
        end


        function S = envelope_db_(plan, xk, om, cyc)
            % S = envelope_db_(plan, xk, om, cyc)
            % The envelope in dB at one tonotopic position, from the
            % trajectories of every envelope (L-by-n): Eq. 1 for a DMR,
            % Eq. 2-3 for ripple noise.
            M = plan.ModulationDepth;
            ripples = sin(2*pi .* (om .* xk + cyc));
            if plan.EnvelopeMode == "RippleNoise"
                L        = plan.NumEnvelopes;
                sigmaDmr = M / sqrt(8);
                sBar     = (M/2) .* sum(ripples, 1) ./ sqrt(L);
                S        = (M/2) .* erf(sBar ./ (plan.ErfDivisor .* sigmaDmr));
            else
                S = (M/2) .* ripples;
            end
        end


        function g = kernel_(z, j, s)
            % g = kernel_(z, j, s)
            % Cubic convolution (Keys, a = -1/2) between knots.
            %
            % Parameters:
            %   z - row of knot values; z(1) is knot j = -1, z(2) is j = 0, ...
            %   j - zero-based index of the knot interval each point lies in
            %   s - position within that interval, 0 <= s < 1 (same size as j)
            %
            % Returns the interpolant at each point: z_j at s = 0, z_(j+1) at
            % s = 1, with a continuous first derivative.
            i  = j + 2;
            zm = z(i - 1);
            z0 = z(i);
            z1 = z(i + 1);
            z2 = z(i + 2);
            g = z0 + 0.5 .* s .* ((z1 - zm) ...
                + s .* ((2.*zm - 5.*z0 + 4.*z1 - z2) ...
                + s .* (-zm + 3.*z0 - 3.*z1 + z2)));
        end


        function v = map_(g, c, range)
            % v = map_(g, c, range)
            % erf, then a linear rescale onto [range(1), range(2)].
            v = range(1) + (range(2) - range(1)) .* (erf(g ./ c) + 1) ./ 2;
        end


        function c = erf_divisor_(scaling)
            % c = erf_divisor_(scaling)
            % The c of erf(x / (c sigma)). sqrt(2) maps a normal variable of
            % standard deviation sigma onto a uniform one; 1 is the paper's
            % equations as printed.
            if scaling == "AsPrinted"
                c = 1;
            else
                c = sqrt(2);
            end
        end


        function d = trajectory_divisor_(scaling)
            % d = trajectory_divisor_(scaling)
            % What the interpolated knot sequence is divided by before erf.
            % "Uniform": sqrt(2) times that sequence's own standard
            % deviation, sqrt(KnotInterpolantVariance), so the mapped values
            % are flat over their range. "AsPrinted": 1, the paper's erf(x).
            if scaling == "AsPrinted"
                d = 1;
            else
                d = sqrt(2 * stimgen.DMR.KnotInterpolantVariance);
            end
        end


        function assert_times_in_range_(plan, t)
            T = plan.N / plan.Fs;
            if any(~isfinite(t)) || any(t < 0) || any(t > T)
                error('stimgen:DMR:TimeOutOfRange', ...
                    'Times must lie within the signal, 0 to %g s.', T);
            end
        end


        function [xi, wq] = gauss_legendre_()
            % [xi, wq] = gauss_legendre_()
            % The 32-point Gauss-Legendre rule on (0,1): nodes xi, weights wq
            % (summing to 1), both rows. Tabulated rather than computed so
            % the phase does not depend on an eigenvalue solver. The values
            % are the rule on (-1,1), computed to 50 digits and rounded to
            % double, mapped to (0,1) below.
            xp = [ ...
                0.04830766568773832, 0.1444719615827965, 0.23928736225213706, 0.33186860228212767, ...
                0.42135127613063533, 0.5068999089322294, 0.5877157572407623,  0.6630442669302152, ...
                0.7321821187402897,  0.7944837959679424, 0.84936761373257,    0.8963211557660521, ...
                0.9349060759377397,  0.9647622555875064, 0.9856115115452684,  0.9972638618494816];
            wp = [ ...
                0.0965400885147278,  0.09563872007927486, 0.09384439908080457,  0.09117387869576389, ...
                0.08765209300440381, 0.08331192422694675, 0.07819389578707031,  0.0723457941088485, ...
                0.06582222277636185, 0.058684093478535544, 0.050998059262376175, 0.04283589802222668, ...
                0.03427386291302143, 0.02539206530926206, 0.01627439473090567,  0.007018610009470096];
            xi = ([-fliplr(xp), xp] + 1) ./ 2;
            wq = [fliplr(wp), wp] ./ 2;
        end

    end % methods (Static, Access = private)

end
