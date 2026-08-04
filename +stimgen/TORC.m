classdef TORC < stimgen.StimType

    % obj = stimgen.TORC(Name,Value,...)
    % Temporally Orthogonal Ripple Combination (TORC) stimulus generator.
    %
    % Class guide: documentation/stimgen_StimTypes.md#torc
    %
    % A TORC is a broadband sound whose dynamic spectrum is the sum of N moving
    % ripples whose temporal modulation rates all differ in absolute value.
    % Because no two components share a rate, each evokes a distinct response
    % frequency, the cross-terms of the spectrotemporal cross-correlation vanish
    % identically, and the STRF is recovered from a single stimulus-response
    % pair with no averaging.
    %
    % Reference:
    %   Klein DJ, Depireux DA, Simon JZ, Shamma SA (2000) "Robust
    %   spectrotemporal reverse correlation for the auditory system: optimizing
    %   stimulus design." J Comput Neurosci 9:85-111.
    %   Equation numbers in the comments below refer to that paper.
    %
    % Synthesis follows Eq. (28): the dynamic spectrum over the log-frequency
    % (tonotopic) axis x, in octaves above LowFrequency, is
    %
    %   S(t,x) = sum_i 2a cos(2 pi (w_i t + Omega_i x) + psi_i)         [dB]
    %
    % and the delivered waveform is the sum of ComponentsPerOctave carriers per
    % octave, each a random-phase tone whose level is driven by S at its own
    % tonotopic position:
    %
    %   s(t) = sum_j 10^(S(t,x_j)/20) sin(2 pi f_j t + phi_j)
    %
    % Component amplitudes are held constant at a for all i (Section 4.1), so
    % the deconvolution that recovers the STRF from the reverse-correlation
    % function C reduces to a division by the scalar a^2:
    %
    %   STRF_est = C / RippleAmplitude^2                                [Eq. 38]
    %
    % Ripple geometry. Rates are always positive here and ripple densities are
    % signed, which spans the same set of physical ripples as the paper's
    % signed-rate convention because (w,-Omega) is the complex conjugate of
    % (-w,Omega). The direction of travel is therefore set by the sign of
    % RippleDensity: positive is downward-moving (quadrant 1 of Fig. 3),
    % negative is upward-moving.
    %
    % Tonotopic axis. Carriers occupy the half-open octave range [0,Bandwidth),
    % because Eq. (10)-(11) treat that range as one period of a Fourier series:
    % x = 0 and x = Bandwidth are the same phase of every ripple. The top
    % carrier therefore sits one step below LowFrequency * 2^Bandwidth. For the
    % same reason a ripple density that is a whole multiple of 1/Bandwidth
    % (Omega_l = l/X) completes an integer number of cycles across the band and
    % lands exactly on the Fourier grid; other densities are permitted and do
    % not affect temporal orthogonality, but their ripple spectra straddle
    % neighbouring grid points.
    %
    % Rate quantization. Rates must be commensurate with the ripple period T so
    % that the envelope is exactly periodic and can be period-averaged against
    % the PSTH (Eq. 11, w_k = k/T). Requested rates are snapped to the nearest
    % multiple of 1/T; T is Duration/NumPeriods, so NumPeriods > 1 delivers
    % several ripple periods within one stimulus.
    %
    % ComponentMode selects how the component list is built:
    %   "Range"    - TORC method I (Section 4.3): one ripple density, and every
    %                rate from LowestRate to HighestRate at the 1/T spacing.
    %                Vectorizing RippleDensity turns the M rows of the ripple
    %                domain into M variants, which is the full method I
    %                ensemble.
    %   "Explicit" - TORC method II: arbitrary (rate, density) pairs listed in
    %                ComponentRates and ComponentDensities, for the denser
    %                single-stimulus designs a longer T makes possible. A
    %                shorter density list is recycled across the rates, so a
    %                single density covers them all.
    %
    % Vectorizing Seed instead reproduces the phase-averaging method of
    % Section 4.2: Seed = 1:25 yields 25 stimuli that share a ripple set but
    % draw new random phases, whose cross-correlation functions average toward
    % the STRF as 1/sqrt(M).
    %
    % ApplyWindow defaults to false. An onset/offset gate would break the exact
    % periodicity the method relies on; enable it only for single, unrepeated
    % presentations.
    %
    % Example:
    %   s = stimgen.TORC;                 % 250 ms, 5 oct from 125 Hz
    %   s.RippleDensity = -1.6:0.4:1.6;   % 9-TORC method I ensemble
    %   s.update_signal;
    %   s.plot_dynamic_spectrum

    properties (SetObservable,AbortSet)
        LowFrequency        (1,:) double {mustBePositive,mustBeFinite} = 125; % Hz, f0
        Bandwidth           (1,:) double {mustBePositive,mustBeFinite} = 5;   % octaves, X
        ComponentsPerOctave (1,:) double {mustBePositive,mustBeFinite} = 20;  % carriers per octave

        ComponentMode (1,1) string {mustBeMember(ComponentMode,["Range","Explicit"])} = "Range";

        % "Range" mode: one signed density, all rates from LowestRate to
        % HighestRate at the 1/T spacing.
        RippleDensity (1,:) double {mustBeFinite} = 0.8;                      % c/o, signed
        LowestRate    (1,:) double {mustBePositive,mustBeFinite} = 4;         % Hz
        HighestRate   (1,:) double {mustBePositive,mustBeFinite} = 24;        % Hz

        % "Explicit" mode: parallel lists, entered as numeric text. A scalar
        % density is expanded across every rate.
        ComponentRates     (1,1) string = "4 8 12 16 20 24";                  % Hz
        ComponentDensities (1,1) string = "0.2 0.6 1.0 -0.2 -0.6 -1.0";       % c/o

        ModulationDepth (1,:) double {mustBePositive,mustBeFinite} = 30;      % dB peak-to-peak
        NumPeriods      (1,:) double {mustBePositive,mustBeInteger,mustBeFinite} = 1;

        RandomizeRipplePhase (1,1) logical = true;
        Seed (1,:) double {mustBeFinite} = 1; % negative reseeds randomly each update
    end

    % Derived by update_signal. Deliberately neither SetObservable (writing
    % them must not retrigger the update) nor listed in UserProperties (they
    % are recomputed, not restored). RippleAmplitude is the scalar a that
    % scales the reverse-correlation function into an STRF estimate.
    properties (SetAccess = protected)
        RippleRates        (1,:) double = [];  % Hz, positive, multiples of 1/RipplePeriod
        RippleDensities    (1,:) double = [];  % c/o, signed
        RipplePhases       (1,:) double = [];  % rad
        RippleAmplitude    (1,1) double = 0;   % dB, the constant a of Eq. (28)
        RipplePeriod       (1,1) double = 0;   % s, T = Duration/NumPeriods
        CarrierFrequencies (1,:) double = [];  % Hz
        CarrierPhases      (1,:) double = [];  % rad
        OctaveAxis         (1,:) double = [];  % octaves above LowFrequency
    end

    properties (Constant)
        IsMultiObj      = false;
        CalibrationType = "filter";
        Normalization   = "rms";
    end

    methods

        function obj = TORC(varargin)
            % Defaults first, caller's pairs last, so a caller's value wins.
            obj = obj@stimgen.StimType( ...
                'DisplayName', 'TORC', ...
                'UserProperties', ["SoundLevel","Duration","WindowDuration","ApplyWindow", ...
                    "LowFrequency","Bandwidth","ComponentsPerOctave","ComponentMode", ...
                    "RippleDensity","LowestRate","HighestRate", ...
                    "ComponentRates","ComponentDensities", ...
                    "ModulationDepth","NumPeriods","RandomizeRipplePhase","Seed"], ...
                ... % 250 ms is the stimulus duration used throughout the paper.
                'Duration', 0.25, ...
                ... % Gating breaks the periodicity the reverse correlation relies on.
                'ApplyWindow', false, ...
                'WindowFcn', "", ...
                varargin{:});
        end


        function update_signal(obj)
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            t   = obj.Time;
            fs  = double(obj.selected_value("Fs"));
            dur = double(obj.selected_value("Duration"));

            f0    = double(obj.selected_value("LowFrequency"));
            X     = double(obj.selected_value("Bandwidth"));
            cpo   = double(obj.selected_value("ComponentsPerOctave"));
            depth = double(obj.selected_value("ModulationDepth"));

            % --- Ripple period, Eq. (11): available rates are multiples of 1/T ---
            T = dur / double(obj.selected_value("NumPeriods"));

            [w, Om] = obj.resolve_ripple_components_(T);

            % --- Tonotopic axis and carriers ---
            % Equal carrier spacing on the octave axis x = log2(f/f0), so the
            % dynamic spectrum is sampled uniformly in the domain it is defined
            % on (Section 3.1). The grid is half-open, [0,X) rather than [0,X],
            % because Eq. (10)-(11) treat x as one period of a Fourier series:
            % x = 0 and x = X are the same phase of every ripple, so including
            % both would double-count a period point and leave a residual in
            % the reverse correlation.
            nCarriers = max(2, round(X * cpo));
            x  = (0:nCarriers-1) .* (X/nCarriers);
            fc = f0 .* 2.^x;

            if f0 * 2^X >= fs/2
                error('stimgen:TORC:BandwidthExceedsNyquist', ...
                    ['LowFrequency * 2^Bandwidth = %.0f Hz reaches or exceeds the ' ...
                     'Nyquist frequency (%.0f Hz). Lower LowFrequency or Bandwidth, ' ...
                     'or raise Fs.'], f0 * 2^X, fs/2);
            end

            % --- Phases ---
            % Drawn from a private stream so that seeding a TORC never
            % perturbs the global RNG state.
            rs  = obj.phase_stream_();
            phi = 2*pi*rand(rs, 1, nCarriers);
            if obj.RandomizeRipplePhase
                % Randomized to reduce the peakiness of the dynamic spectrum,
                % which packs more power into the available dynamic range
                % (Section 4.1).
                psi = 2*pi*rand(rs, 1, numel(w));
            else
                psi = zeros(1, numel(w));
            end

            % --- Ripple amplitude a ---
            % Components are equal-amplitude, so a is fixed by the requested
            % peak-to-peak excursion of the dynamic spectrum. Computed against
            % the realized envelope rather than the 2Na worst case, which the
            % randomized phases never approach.
            %
            % a depends on the whole envelope, so this is a separate pass over
            % the carriers rather than a cached S. Caching would be twice as
            % fast but would hold an nCarriers-by-N matrix -- hundreds of MB
            % for the multi-second stimuli that TORC method II calls for.
            peak = 0;
            for j = 1:nCarriers
                peak = max(peak, max(abs(stimgen.TORC.ripple_envelope_(t, x(j), w, Om, psi, 1))));
            end
            if peak <= 0
                a = 0;
            else
                a = (depth/2) / peak;
            end

            % --- Waveform ---
            y = zeros(1, numel(t));
            for j = 1:nCarriers
                S = stimgen.TORC.ripple_envelope_(t, x(j), w, Om, psi, a); % dB re mean level
                y = y + 10.^(S/20) .* sin(2*pi*fc(j)*t + phi(j));
            end

            obj.RippleRates        = w;
            obj.RippleDensities    = Om;
            obj.RipplePhases       = psi;
            obj.RippleAmplitude    = a;
            obj.RipplePeriod       = T;
            obj.CarrierFrequencies = fc;
            obj.CarrierPhases      = phi;
            obj.OctaveAxis         = x;

            obj.Signal = y;

            obj.apply_normalization;

            obj.apply_calibration;

            obj.apply_gate;
        end


        function [S, t, x] = dynamic_spectrum(obj, nTime)
            % [S, t, x] = dynamic_spectrum(obj)
            % [S, t, x] = dynamic_spectrum(obj, nTime)
            % Reconstruct the dynamic spectrum S(t,x) that drove the current
            % Signal, for cross-correlation against a response (Eq. 19).
            %
            % The full-rate envelope is large and is not retained by
            % update_signal, so it is recomputed here at whatever temporal
            % resolution the analysis needs -- typically the PSTH bin rate,
            % not Fs.
            %
            % Parameters:
            %   nTime - Number of time samples (default: the signal length).
            %
            % Returns:
            %   S - nCarriers-by-nTime dynamic spectrum, dB about the mean level.
            %   t - 1-by-nTime time axis, seconds.
            %   x - 1-by-nCarriers tonotopic axis, octaves above LowFrequency.

            if isempty(obj.OctaveAxis) || isempty(obj.Signal)
                obj.update_signal();
            end

            % Duration comes from the rendered signal, not from selected_value:
            % reading a vectorized property outside a variant cycle can advance
            % the variant index, which would decouple S from the Signal that
            % is actually on the object.
            nSignal = numel(obj.Signal);
            if nargin < 2 || isempty(nTime)
                nTime = nSignal;
            end
            dur = nSignal / obj.Fs;
            t   = (0:nTime-1) .* (dur/nTime);

            x = obj.OctaveAxis;
            S = zeros(numel(x), numel(t));
            for j = 1:numel(x)
                S(j,:) = stimgen.TORC.ripple_envelope_(t, x(j), obj.RippleRates, ...
                    obj.RippleDensities, obj.RipplePhases, obj.RippleAmplitude);
            end
        end


        function h = plot_dynamic_spectrum(obj, ax, nTime)
            % h = plot_dynamic_spectrum(obj)
            % h = plot_dynamic_spectrum(obj, ax, nTime)
            % Display the dynamic spectrum as an image, time in ms on the
            % x-axis and octaves above LowFrequency on the y-axis.
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
            c.Label.String = 'level (dB re mean)';
        end

    end % methods (public)


    methods (Access = protected)

        function [w, Om] = resolve_ripple_components_(obj, T)
            % [w, Om] = resolve_ripple_components_(obj, T)
            % Build the ripple component list for the current ComponentMode and
            % snap it to the rate grid k/T set by the ripple period.
            %
            % Returns:
            %   w  - 1-by-N positive rates, Hz.
            %   Om - 1-by-N signed ripple densities, c/o.

            switch obj.ComponentMode
                case "Range"
                    lo = double(obj.selected_value("LowestRate"));
                    hi = double(obj.selected_value("HighestRate"));
                    if hi < lo
                        error('stimgen:TORC:InvalidRateRange', ...
                            'HighestRate (%.3g Hz) must be greater than or equal to LowestRate (%.3g Hz).', hi, lo);
                    end
                    % Contiguous run of harmonics of 1/T, i.e. a single row of
                    % the ripple domain (TORC method I).
                    k  = round(lo*T):round(hi*T);
                    Om = repmat(double(obj.selected_value("RippleDensity")), 1, numel(k));

                case "Explicit"
                    w  = stimgen.TORC.parse_numeric_list_(obj.ComponentRates, 'ComponentRates');
                    if any(w <= 0)
                        error('stimgen:TORC:InvalidRate', ...
                            ['ComponentRates must all be positive. Direction of travel is set by ' ...
                             'the sign of the ripple density, not the rate.']);
                    end
                    Om = stimgen.TORC.parse_numeric_list_(obj.ComponentDensities, 'ComponentDensities');
                    if numel(Om) ~= numel(w)
                        % The two lists are edited one at a time, so an unequal
                        % pair is a normal transient -- a GUI edit in progress,
                        % or fromStruct restoring them in either order. Recycle
                        % to fit rather than failing, the same way apply_gate
                        % shrinks an oversized window. A lone density expanding
                        % across every rate is the common case and stays quiet.
                        if ~isscalar(Om)
                            stimgen.util.vprintf(1, ...
                                'TORC: %d ripple rates but %d densities; densities recycled to fit.', ...
                                numel(w), numel(Om));
                        end
                        Om = Om(mod(0:numel(w)-1, numel(Om)) + 1);
                    end
                    k = round(w*T);
            end

            if any(k < 1)
                error('stimgen:TORC:RateBelowFundamental', ...
                    ['Every ripple rate must be at least 1/T = %.3g Hz, the fundamental of the ' ...
                     '%.4g s ripple period. Raise the rate, lengthen Duration, or lower NumPeriods.'], ...
                    1/T, T);
            end

            % Temporal orthogonality (Eq. 36): no two components may share a
            % rate, or their responses overlap in frequency and cross-terms
            % reappear in the cross-correlation function.
            if numel(unique(k)) < numel(k)
                error('stimgen:TORC:TemporalOrthogonality', ...
                    ['Two or more ripple components resolve to the same rate on the %.3g Hz grid ' ...
                     'set by the ripple period, which breaks temporal orthogonality. Separate the ' ...
                     'rates or lengthen Duration to refine the grid.'], 1/T);
            end

            w = k / T;
        end


        function rs = phase_stream_(obj)
            % rs = phase_stream_(obj)
            % Random stream for the ripple and carrier phases. A negative Seed
            % reseeds from the system entropy source on every update; any other
            % value makes the stimulus exactly reproducible.
            seedValue = double(obj.selected_value("Seed"));
            if seedValue < 0
                rs = RandStream('mt19937ar','Seed','shuffle');
            else
                rs = RandStream('mt19937ar','Seed', mod(round(seedValue), 2^32-1));
            end
        end


        function m = propMeta(obj)
            % propMeta() - Display metadata for TORC GUI properties.
            m = struct();
            m.LowFrequency        = struct('label','Low Frequency (f0)','format','%.1f Hz','limits',[1 40000], ...
                                           'tooltip',stimgen.util.tooltip(obj,'LowFrequency'),'order',10);
            m.Bandwidth           = struct('label','Bandwidth (oct)',   'format','%.2f oct','limits',[0.1 12], ...
                                           'tooltip',stimgen.util.tooltip(obj,'Bandwidth'),'order',20);
            m.ComponentsPerOctave = struct('label','Carriers / Octave', 'format','%.0f',    'limits',[1 200], ...
                                           'tooltip',stimgen.util.tooltip(obj,'ComponentsPerOctave'),'order',30);
            m.ComponentMode       = struct('label','Component Mode','widget','dropdown', ...
                                           'items',["Range","Explicit"],'tooltip',stimgen.util.tooltip(obj,'ComponentMode'),'order',40);
            m.RippleDensity       = struct('label','Ripple Density (c/o, signed)','format','%.2f c/o','limits',[-8 8], ...
                                           'tooltip',stimgen.util.tooltip(obj,'RippleDensity'),'order',50);
            m.LowestRate          = struct('label','Lowest Rate (Hz)', 'format','%.2f Hz','limits',[0.01 2000], ...
                                           'tooltip',stimgen.util.tooltip(obj,'LowestRate'),'order',60);
            m.HighestRate         = struct('label','Highest Rate (Hz)','format','%.2f Hz','limits',[0.01 2000], ...
                                           'tooltip',stimgen.util.tooltip(obj,'HighestRate'),'order',70);
            m.ComponentRates      = struct('label','Component Rates (Hz)',      'widget','text', ...
                                           'tooltip',stimgen.util.tooltip(obj,'ComponentRates'),'order',80);
            m.ComponentDensities  = struct('label','Component Densities (c/o)', 'widget','text', ...
                                           'tooltip',stimgen.util.tooltip(obj,'ComponentDensities'),'order',90);
            m.RandomizeRipplePhase = struct('label','Randomize Ripple Phase', ...
                                            'tooltip',stimgen.util.tooltip(obj,'RandomizeRipplePhase'),'order',100);
            m.Seed                = struct('label','Phase Seed','format','%.0f','limits',[-1 4294967295], ...
                                           'tooltip',stimgen.util.tooltip(obj,'Seed'),'order',110);

            m.ModulationDepth = struct('label','Modulation Depth (dB pk-pk)','format','%.1f dB', ...
                                       'limits',[0.1 120],'tooltip',stimgen.util.tooltip(obj,'ModulationDepth'),'group','Level','order',15);
            m.NumPeriods      = struct('label','Ripple Periods','format','%.0f','limits',[1 1000], ...
                                       'tooltip',stimgen.util.tooltip(obj,'NumPeriods'),'group','Timing','order',20);

            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.StimType(obj));
        end

    end % methods (Access = protected)


    methods (Static, Access = protected)

        function S = ripple_envelope_(t, xOct, w, Om, psi, a)
            % S = ripple_envelope_(t, xOct, w, Om, psi, a)
            % Dynamic spectrum at a single tonotopic position, Eq. (28):
            %   S(t,x) = sum_i 2a cos(2 pi (w_i t + Omega_i x) + psi_i)
            % The factor of two is the ripple's complex-conjugate pair; a is the
            % amplitude of a single ripple-spectrum component.
            S = zeros(1, numel(t));
            for i = 1:numel(w)
                S = S + 2*a*cos(2*pi*(w(i)*t + Om(i)*xOct) + psi(i));
            end
        end


        function v = parse_numeric_list_(text, propName)
            % v = parse_numeric_list_(text, propName)
            % Parse a numeric-list property into a row vector. Accepts vector
            % and range literals; anything that is not a number, whitespace or
            % an arithmetic/range operator is rejected rather than evaluated.
            s = strtrim(char(text));
            if isempty(s)
                error('stimgen:TORC:EmptyComponentList','%s is empty.', propName);
            end
            if ~isempty(regexp(s, '[^0-9eE.+\-*/\s,;:\[\]()]', 'once'))
                error('stimgen:TORC:InvalidComponentList', ...
                    ['%s may contain only numbers, whitespace and the characters ' ...
                     '+ - * / : , ; [ ] ( ).'], propName);
            end
            v = str2num(s); %#ok<ST2NM>
            if isempty(v) || ~isnumeric(v) || ~all(isfinite(v(:)))
                error('stimgen:TORC:InvalidComponentList', ...
                    '%s must evaluate to a nonempty vector of finite numbers.', propName);
            end
            v = reshape(double(v), 1, []);
        end

    end % methods (Static, Access = protected)

end
