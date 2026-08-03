classdef TORC < stimgen.components.Component
% stimgen.components.TORC
% Temporally Orthogonal Ripple Combination -- a broadband dynamic-spectrum
% carrier for STRF estimation.
%
% Ports the synthesis of stimgen.TORC, which is where the method, the equation
% numbers and the reasoning behind every parameter are documented. Read that
% class first; this header covers only what changes when a TORC becomes a graph
% node.
%
% Reference:
%   Klein DJ, Depireux DA, Simon JZ, Shamma SA (2000) J Comput Neurosci 9:85-111.
%
% As a node the TORC can be gated, mixed, level-swept or amplitude-modulated
% against other sources, which the monolithic class cannot do -- a TORC gated by
% a PulseTrain, or summed with a tone in a Mixer, needs no new class.
%
% Parameters:
%   LowFrequency, Bandwidth   - tonotopic axis; carriers span [0,Bandwidth)
%                               octaves above LowFrequency
%   ComponentsPerOctave       - carrier density on that axis
%   ComponentMode             - Range (method I) | Explicit (method II)
%   RippleDensity             - signed c/o, Range mode
%   LowestRate, HighestRate   - Hz, Range mode
%   ComponentRates,
%   ComponentDensities        - parallel numeric lists, Explicit mode
%   ModulationDepth           - peak-to-peak excursion of the dynamic spectrum, dB
%   NumPeriods                - ripple periods within the timebase
%   RandomizeRipplePhase      - randomize psi_i to flatten the envelope
%   Seed                      - phase seed
%   Amplitude                 - linear gain (modulatable)
%
% DELIBERATE DIVERGENCES FROM stimgen.TORC
%
% - Timebase. There is no Duration parameter: the ripple period is
%   T = (ctx.N/ctx.Fs)/NumPeriods, taken from the patch's global timebase. The
%   sample count is what the reverse correlation is periodic in, so it is a
%   sounder source for T than a nominal duration. The defaults are chosen to
%   render at the default patch Duration of 100 ms, whose 10 Hz fundamental
%   rules out the paper's slow ripples; for the canonical configuration set the
%   patch Duration to 250 ms and the rate band to 4-24 Hz.
%
% - In Range mode a Lowest Rate below the 1/T fundamental is clamped up to it,
%   with a note through vprintf, instead of raising an error. stimgen.TORC owns
%   its Duration and can insist the band fit; a node's ripple period is set by
%   the patch, so an unrelated Duration edit would otherwise break it. Explicit
%   mode still errors, because there each entry is a specific requested ripple
%   rather than the edge of a band.
%
% - Level. The waveform is divided by sqrt(nCarriers). Carriers add
%   incoherently, so a raw sum grows as sqrt(nCarriers) and ComponentsPerOctave
%   -- a resolution knob -- would double as a level knob. stimgen.TORC does not
%   need this because StimType renormalizes the finished waveform; a patch node
%   is mixed against its siblings before any normalization happens. An overall
%   gain does not touch the dynamic spectrum, which is defined in dB about the
%   mean level, so the STRF math is unaffected.
%
% - Seed. 0 draws fresh phases each render and any positive value is
%   reproducible, matching stimgen.components.NoiseSource. stimgen.TORC instead
%   reseeds on a NEGATIVE Seed, so 0 means something different in the two.
%
% - The envelope is evaluated by the angle-sum identity (see ripple_envelope_)
%   rather than by looping over ripples per carrier. The result is the same to
%   within floating-point rounding, not bit-identical.
%
% USING IT FOR REVERSE CORRELATION
% Recovering an STRF needs the dynamic spectrum that drove the waveform, so the
% realized ripple set is recorded on LastRipples after every render and
% dynamic_spectrum() reconstructs S(t,x) from it:
%
%   p = stimgen.Patch;
%   p.add_node("Torc1", "TORC");
%   p.OutputNode = "Torc1";
%   p.LevelReference = "rms";       % broadband: normalize on rms, not absmax
%   p.ApplyWindow    = false;       % gating breaks the periodicity the method needs
%   p.update_signal;
%   [S, t, x] = p.component("Torc1").dynamic_spectrum(500);
%   STRF = C ./ p.component("Torc1").LastRipples.Amplitude^2;   % Eq. (38)
%
% Vectorize Seed on the patch (p.Torc1_Seed = 1:25) for the phase-averaging
% ensemble of Section 4.2; vectorize Torc1_RippleDensity for the method I
% ensemble.
%
% nominal_range is left at the inherited [-1 1]. Like NoiseSource, this node is
% a broadband zero-mean carrier whose true peak depends on the render, and the
% declared range is only consulted when it drives another node's parameter.
%
% Calibration: a patch containing a TORC should stay on CalibrationMode
% "Filtered". Patch.anchor_frequency_ has no carrier frequency to read from a
% TORC node, so mode "Tone" falls back to the spectral centroid.

    properties (Constant)
        Kind        = "TORC";
        Description = "Temporally orthogonal ripple combination, for STRF estimation";
    end

    properties (SetAccess = private)
        % Ripple set realized by the most recent render, so that the dynamic
        % spectrum can be reconstructed for reverse correlation. This is a
        % description of the last render, not retained signal state -- nothing
        % in render() reads it -- and under variants it describes whichever
        % combination rendered last.
        %
        % Amplitude is the scalar a of Eq. (28); the STRF estimate is the
        % reverse-correlation function divided by a^2 (Eq. 38).
        LastRipples (1,1) struct = struct( ...
            'Rates', [], 'Densities', [], 'Phases', [], 'Amplitude', 0, ...
            'Period', 0, 'CarrierFrequencies', [], 'CarrierPhases', [], ...
            'OctaveAxis', [], 'Fs', 0, 'NumSamples', 0);
    end

    methods

        function d = param_defs(~)
            pd = @stimgen.components.Component.pdef;
            d = struct();
            d.LowFrequency = pd('Low Frequency (Hz)', 125, 'format','%.1f Hz', ...
                'limits',[1 40000], 'order',10, ...
                'doc','f0: the bottom of the tonotopic axis, 0 octaves.');
            d.Bandwidth = pd('Bandwidth (oct)', 5, 'format','%.2f oct', ...
                'limits',[0.1 12], 'order',20, ...
                'doc','Octaves spanned above Low Frequency. Carriers fill [0,Bandwidth).');
            d.ComponentsPerOctave = pd('Carriers / Octave', 20, 'format','%d', ...
                'limits',[1 200], 'order',30, ...
                'doc','Carrier density. Raising it costs render time but not level.');
            d.ComponentMode = pd('Component Mode', "Range", ...
                'items',["Range" "Explicit"], 'order',40, ...
                'doc','Range: one density, every rate in a band. Explicit: listed (rate, density) pairs.');
            d.RippleDensity = pd('Ripple Density (c/o)', 0.8, 'format','%.2f c/o', ...
                'limits',[-8 8], 'order',50, ...
                'doc','Range mode. Signed: positive moves downward, negative upward.');
            d.LowestRate = pd('Lowest Rate (Hz)', 10, 'format','%.2f Hz', ...
                'limits',[0.01 2000], 'order',60, ...
                'doc','Range mode. Snapped to a multiple of 1/T, and raised to 1/T if below it.');
            d.HighestRate = pd('Highest Rate (Hz)', 40, 'format','%.2f Hz', ...
                'limits',[0.01 2000], 'order',70, ...
                'doc','Range mode. Snapped to the nearest multiple of 1/T.');
            d.ComponentRates = pd('Component Rates (Hz)', "10 20 30 40", ...
                'widget','text', 'order',80, ...
                'doc','Explicit mode. Positive rates, e.g. 10 20 30 40 or 4:4:24.');
            d.ComponentDensities = pd('Component Densities (c/o)', "0.4 -0.4 0.8 -0.8", ...
                'widget','text', 'order',90, ...
                'doc','Explicit mode. Signed densities; a shorter list is recycled across the rates.');
            d.ModulationDepth = pd('Modulation Depth (dB pk-pk)', 30, 'format','%.1f dB', ...
                'limits',[0.1 120], 'order',100, ...
                'doc','Peak-to-peak excursion of the dynamic spectrum about the mean level.');
            d.NumPeriods = pd('Ripple Periods', 1, 'format','%d', ...
                'limits',[1 1000], 'order',110, ...
                'doc','Ripple periods within the patch duration. T = Duration / this.');
            d.RandomizeRipplePhase = pd('Randomize Ripple Phase', true, 'order',120, ...
                'doc','Flattens the envelope so more power fits in the dynamic range.');
            d.Seed = pd('Seed (0 = random)', 1, 'format','%d', ...
                'limits',[0 2^31-1], 'order',130, ...
                'doc','Fixed seed reproduces the same phases. Vectorize it for phase averaging.');
            d.Amplitude = pd('Amplitude', 1, 'format','%.3f', ...
                'modulatable',true, 'order',140, ...
                'doc','Linear gain. Modulate this to gate or amplitude-modulate the TORC.');
        end

        function y = render(obj, ctx, p)
            N  = ctx.N;
            fs = double(ctx.Fs);
            t  = ctx.t;

            if N < 1
                y = zeros(1, max(0, N));
                return
            end

            f0    = double(p.LowFrequency);
            X     = double(p.Bandwidth);
            cpo   = double(p.ComponentsPerOctave);
            depth = double(p.ModulationDepth);

            % Duration comes from the sample count, not from t(end): ctx.t runs
            % to Duration - 1/Fs, and it is the N samples that have to hold a
            % whole number of ripple periods.
            dur = N / fs;
            if dur <= 0
                y = zeros(1, N);
                return
            end

            if f0 * 2^X >= fs/2
                error('stimgen:components:TORC:BandwidthExceedsNyquist', ...
                    ['Low Frequency * 2^Bandwidth = %.0f Hz reaches or exceeds the Nyquist ' ...
                     'frequency (%.0f Hz). Lower Low Frequency or Bandwidth, or raise Fs.'], ...
                    f0 * 2^X, fs/2);
            end

            % --- Ripple period, Eq. (11): available rates are multiples of 1/T ---
            T = dur / max(1, round(double(p.NumPeriods)));
            [w, Om] = obj.resolve_ripples_(T, p);

            % --- Tonotopic axis and carriers ---
            % Half-open [0,X), because Eq. (10)-(11) treat x as one period of a
            % Fourier series: x = 0 and x = X are the same phase of every
            % ripple, so including both would double-count a period point.
            nC = max(2, round(X * cpo));
            x  = (0:nC-1) .* (X/nC);
            fc = f0 .* 2.^x;

            % --- Phases ---
            % Drawn from a private stream, so seeding a TORC node never
            % perturbs the global RNG state.
            R   = numel(w);
            rs  = obj.phase_stream_(p);
            phi = 2*pi*rand(rs, 1, nC);
            if logical(p.RandomizeRipplePhase)
                psi = 2*pi*rand(rs, 1, R);
            else
                psi = zeros(1, R);
            end

            % Time is processed in blocks so that the intermediate
            % nCarriers-by-block envelope stays bounded however long the patch
            % is: the multi-second stimuli TORC method II calls for would
            % otherwise need hundreds of MB for a matrix that is used once.
            blk = max(1, floor(2^19 / max(R, nC)));

            % --- Ripple amplitude a ---
            % Components are equal-amplitude (Section 4.1), so a is fixed by
            % the requested peak-to-peak excursion. Measured against the
            % realized envelope rather than the 2Na worst case, which the
            % randomized phases never approach. That takes a separate pass,
            % because a is not known until the whole envelope has been seen and
            % the envelope is too large to keep.
            peak = 0;
            for i0 = 1:blk:N
                i1 = min(i0 + blk - 1, N);
                E  = stimgen.components.TORC.ripple_envelope_(t(i0:i1), x, w, Om, psi);
                peak = max(peak, max(abs(E), [], 'all'));
            end
            if peak <= 0
                a = 0;
            else
                a = (depth/2) / peak;
            end

            % --- Waveform: each carrier's level driven by S at its own x ---
            %   s(t) = sum_j 10^(S(t,x_j)/20) sin(2 pi f_j t + phi_j)
            y = zeros(1, N);
            for i0 = 1:blk:N
                i1 = min(i0 + blk - 1, N);
                tb = t(i0:i1);
                E  = stimgen.components.TORC.ripple_envelope_(tb, x, w, Om, psi);
                y(i0:i1) = sum(10.^((a/20) .* E) .* sin(2*pi .* (fc(:)*tb) + phi(:)), 1);
            end

            % Level independent of carrier density -- see the class header.
            y = y ./ sqrt(nC);

            obj.LastRipples = struct( ...
                'Rates', w, 'Densities', Om, 'Phases', psi, 'Amplitude', a, ...
                'Period', T, 'CarrierFrequencies', fc, 'CarrierPhases', phi, ...
                'OctaveAxis', x, 'Fs', fs, 'NumSamples', N);

            y = obj.fit(y .* obj.expand(p.Amplitude, N), N);
        end

        function [S, t, x] = dynamic_spectrum(obj, nTime)
            % [S, t, x] = dynamic_spectrum(obj)
            % [S, t, x] = dynamic_spectrum(obj, nTime)
            % Reconstruct the dynamic spectrum S(t,x) that drove the most
            % recent render, for cross-correlation against a response (Eq. 19).
            %
            % The full-rate envelope is large and is not retained, so it is
            % rebuilt here from LastRipples at whatever temporal resolution the
            % analysis needs -- typically the PSTH bin rate, not Fs.
            %
            % Parameters:
            %   nTime - Number of time samples (default: the rendered length).
            %
            % Returns:
            %   S - nCarriers-by-nTime dynamic spectrum, dB about the mean level.
            %   t - 1-by-nTime time axis, seconds.
            %   x - 1-by-nCarriers tonotopic axis, octaves above LowFrequency.

            r = obj.LastRipples;
            if isempty(r.OctaveAxis)
                error('stimgen:components:TORC:NotRendered', ...
                    ['This TORC node has not rendered yet. Call update_signal on the ' ...
                     'patch that owns it first.']);
            end

            if nargin < 2 || isempty(nTime)
                nTime = r.NumSamples;
            end
            dur = r.NumSamples / r.Fs;
            t   = (0:nTime-1) .* (dur/nTime);
            x   = r.OctaveAxis;

            S = r.Amplitude .* stimgen.components.TORC.ripple_envelope_( ...
                t, x, r.Rates, r.Densities, r.Phases);
        end

    end % methods

    methods (Access = private)

        function [w, Om] = resolve_ripples_(obj, T, p)
            % [w, Om] = resolve_ripples_(obj, T, p)
            % Build the ripple component list for the current ComponentMode and
            % snap it to the rate grid k/T set by the ripple period.
            %
            % Returns:
            %   w  - 1-by-R positive rates, Hz.
            %   Om - 1-by-R signed ripple densities, c/o.

            switch string(p.ComponentMode)
                case "Range"
                    lo = double(p.LowestRate);
                    hi = double(p.HighestRate);
                    if hi < lo
                        error('stimgen:components:TORC:InvalidRateRange', ...
                            ['Highest Rate (%.3g Hz) must be greater than or equal to ' ...
                             'Lowest Rate (%.3g Hz).'], hi, lo);
                    end
                    % Contiguous run of harmonics of 1/T, i.e. a single row of
                    % the ripple domain (TORC method I).
                    kLo = round(lo*T);
                    kHi = round(hi*T);
                    if kHi < 1
                        error('stimgen:components:TORC:RateBelowFundamental', ...
                            ['The whole rate band (%.3g to %.3g Hz) lies below 1/T = %.3g Hz, ' ...
                             'the fundamental of the %.4g s ripple period. Raise the rates, ' ...
                             'lengthen the patch Duration, or lower Ripple Periods.'], ...
                            lo, hi, 1/T, T);
                    end
                    if kLo < 1
                        % stimgen.TORC owns its Duration and so can insist the
                        % band fit the grid. A node cannot: the ripple period
                        % comes from the patch, and a Duration edit elsewhere
                        % must not break an otherwise valid node. Lowest Rate
                        % describes the bottom of a band rather than one
                        % requested ripple, so clamp it to the fundamental --
                        % the same accommodation apply_gate makes for an
                        % oversized window -- and say so.
                        stimgen.util.vprintf(1, ...
                            ['TORC: Lowest Rate %.3g Hz is below the %.3g Hz fundamental of the ' ...
                             '%.4g s ripple period; the band starts at the fundamental instead.'], ...
                            lo, 1/T, T);
                        kLo = 1;
                    end
                    k  = kLo:kHi;
                    Om = repmat(double(p.RippleDensity), 1, numel(k));

                case "Explicit"
                    w = obj.parse_numeric_list_(p.ComponentRates, 'Component Rates');
                    if any(w <= 0)
                        error('stimgen:components:TORC:InvalidRate', ...
                            ['Component Rates must all be positive. Direction of travel is ' ...
                             'set by the sign of the ripple density, not the rate.']);
                    end
                    Om = obj.parse_numeric_list_(p.ComponentDensities, 'Component Densities');
                    if numel(Om) ~= numel(w)
                        % The two lists are edited one at a time, so an unequal
                        % pair is a normal transient -- an inspector edit in
                        % progress, or fromStruct restoring them in either
                        % order. Recycle to fit rather than failing. A lone
                        % density expanding across every rate is the common
                        % case and stays quiet.
                        if ~isscalar(Om)
                            stimgen.util.vprintf(1, ...
                                'TORC: %d ripple rates but %d densities; densities recycled to fit.', ...
                                numel(w), numel(Om));
                        end
                        Om = Om(mod(0:numel(w)-1, numel(Om)) + 1);
                    end
                    k = round(w*T);

                otherwise
                    error('stimgen:components:TORC:UnknownComponentMode', ...
                        'Unknown component mode "%s".', string(p.ComponentMode));
            end

            % Reachable only from Explicit mode, where each entry is a specific
            % requested ripple rather than the edge of a band, so there is
            % nothing to clamp it to without silently changing the design.
            if any(k < 1)
                error('stimgen:components:TORC:RateBelowFundamental', ...
                    ['Every ripple rate must be at least 1/T = %.3g Hz, the fundamental of ' ...
                     'the %.4g s ripple period. Raise the rate, lengthen the patch Duration, ' ...
                     'or lower Ripple Periods.'], 1/T, T);
            end

            % Temporal orthogonality (Eq. 36): no two components may share a
            % rate, or their responses overlap in frequency and cross-terms
            % reappear in the cross-correlation function.
            if numel(unique(k)) < numel(k)
                error('stimgen:components:TORC:TemporalOrthogonality', ...
                    ['Two or more ripple components resolve to the same rate on the %.3g Hz ' ...
                     'grid set by the ripple period, which breaks temporal orthogonality. ' ...
                     'Separate the rates or lengthen the patch Duration to refine the grid.'], 1/T);
            end

            w = k / T;
        end

        function rs = phase_stream_(~, p)
            % rs = phase_stream_(obj, p)
            % Random stream for the ripple and carrier phases. Seed 0 draws
            % from the system entropy source on every render; any positive
            % value makes the node exactly reproducible.
            seed = round(double(p.Seed));
            if seed > 0
                rs = RandStream('twister', 'Seed', mod(seed, 2^32-1));
            else
                rs = RandStream('twister', 'Seed', 'shuffle');
            end
        end

        function v = parse_numeric_list_(~, text, propName)
            % v = parse_numeric_list_(obj, text, propName)
            % Parse a numeric-list parameter into a row vector. Accepts vector
            % and range literals; anything that is not a number, whitespace or
            % an arithmetic/range operator is rejected rather than evaluated.
            if isnumeric(text) || islogical(text)
                % A patch parameter is an untyped dynamic property, so a
                % numeric assignment is accepted and then read as a variant
                % axis -- p.Torc1_ComponentRates = [4 8 12] would become three
                % variants of a single rate, not one list of three. Caught here
                % because the whitelist below would otherwise reject the same
                % mistake with a message about illegal characters.
                error('stimgen:components:TORC:InvalidComponentList', ...
                    ['%s must be entered as text, for example "4 8 12 16". A numeric ' ...
                     'assignment is read as a variant sweep over single rates instead ' ...
                     'of as one component list.'], propName);
            end

            s = strtrim(char(text));
            if isempty(s)
                error('stimgen:components:TORC:EmptyComponentList', '%s is empty.', propName);
            end
            if ~isempty(regexp(s, '[^0-9eE.+\-*/\s,;:\[\]()]', 'once'))
                error('stimgen:components:TORC:InvalidComponentList', ...
                    ['%s may contain only numbers, whitespace and the characters ' ...
                     '+ - * / : , ; [ ] ( ).'], propName);
            end
            v = str2num(s); %#ok<ST2NM>
            if isempty(v) || ~isnumeric(v) || ~all(isfinite(v(:)))
                error('stimgen:components:TORC:InvalidComponentList', ...
                    '%s must evaluate to a nonempty vector of finite numbers.', propName);
            end
            v = reshape(double(v), 1, []);
        end

    end % methods (Access = private)

    methods (Static, Access = private)

        function E = ripple_envelope_(t, x, w, Om, psi)
            % E = ripple_envelope_(t, x, w, Om, psi)
            % Unit-amplitude dynamic spectrum over a whole tonotopic axis,
            % Eq. (28) with a = 1:
            %
            %   E(t,x) = sum_i 2 cos(2 pi (w_i t + Omega_i x) + psi_i)
            %
            % The factor of two is the ripple's complex-conjugate pair.
            %
            % Expanding by the angle-sum identity separates the two axes,
            %
            %   cos(A_i(t) + B_i(x)) = cos A_i cos B_i - sin A_i sin B_i
            %   A_i(t) = 2 pi w_i t + psi_i,   B_i(x) = 2 pi Omega_i x
            %
            % so the transcendentals are evaluated once per ripple (R-by-numel(t))
            % and once per carrier (numel(x)-by-R) instead of once per
            % (carrier, ripple) pair, and the sum over ripples becomes a single
            % matrix product. Same value, but the cost stops scaling with the
            % product of the two axes.
            %
            % Returns:
            %   E - numel(x)-by-numel(t), dB about the mean level per unit a.

            t = reshape(t, 1, []);
            A = 2*pi .* (w(:) * t) + psi(:);              % R-by-numel(t)
            B = 2*pi .* (x(:) * Om(:).');                 % numel(x)-by-R
            E = 2 .* (cos(B) * cos(A) - sin(B) * sin(A));
        end

    end % methods (Static, Access = private)

end
