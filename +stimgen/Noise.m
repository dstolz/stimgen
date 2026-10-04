classdef Noise < stimgen.StimType

    % obj = stimgen.Noise(Name,Value,...)
    % Band-limited noise stimulus generator.
    %
    % Generates Gaussian noise filtered between HighPass and LowPass.
    % The waveform is optionally windowed/gated and calibrated.
    %
    % The band-pass is a linear-phase FIR designed from what the band edges
    % have to achieve rather than from a fixed length: each cutoff sits in the
    % middle of a transition band TransitionWidth wide, with at least
    % StopbandAttenuation dB of rejection outside it (Kaiser window, order
    % from kaiserord). HighPass and LowPass are therefore the -6 dB points,
    % and everything more than TransitionWidth/2 outside the band is down by
    % StopbandAttenuation. A fixed 40-tap filter, which this replaced, has a
    % transition several kHz wide at 97.7 kHz, so its band edges were
    % nominal: a 500 Hz high-pass left most of the energy below 500 Hz in
    % place.
    %
    % Edges that sharp need long filters (thousands of taps at a 500 Hz
    % edge), so the filter runs through fftfilt, and enough extra noise is
    % generated to discard the filter's start-up: every sample kept has a
    % full filter history, so the record does not fade in.

    properties (SetObservable,AbortSet)
        HighPass  (1,:) double {mustBeNonnegative,mustBeFinite} = 500; % Hz
        LowPass   (1,:) double {mustBeNonnegative,mustBeFinite} = 20000; % Hz

        % Full width (Hz) of the transition band centred on each cutoff.
        % 0 = automatic: a tenth of the narrowest of HighPass, the bandwidth
        % LowPass - HighPass, and the room above LowPass (Fs/2 - LowPass).
        TransitionWidth (1,1) double {mustBeNonnegative,mustBeFinite} = 0;

        % Minimum rejection (dB) outside the transition bands.
        StopbandAttenuation (1,1) double {mustBePositive,mustBeFinite} = 60;

        % 0 = design from TransitionWidth and StopbandAttenuation (default).
        % A positive order is used as given with a Hamming window at the two
        % cutoffs -- the design earlier versions used, at 40 -- so a saved
        % stimulus that names an order regenerates the filter it was made
        % with. Order + 1 taps either way.
        FilterOrder (1,1) double {mustBeNonnegative,mustBeInteger,mustBeFinite} = 0;
    end

    % The filter the last waveform was made with. Written by update_signal;
    % not observable, so writing it cannot re-enter update_signal.
    properties (SetAccess = protected)
        FilterCoefficients (1,:) double = []  % FIR taps
        DesignedOrder      (1,1) double = NaN % numel(FilterCoefficients) - 1
        DesignedTransition (1,1) double = NaN % Hz; NaN for an explicit FilterOrder
    end

    properties (Access = private)
        filterKey_ (1,:) double = []   % [hp lp fs tw att order] the taps were designed for
    end

    properties (Constant)
        CalibrationType = "filter";
        Normalization   = "rms";
    end

    properties (Constant, Hidden)
        MaxFilterOrder = 2^20   % refuse a design that would not fit a sane FFT
    end

    methods

        function obj = Noise(varargin)
            % Defaults first, caller's pairs last, so a caller's value wins.
            obj = obj@stimgen.StimType( ...
                'DisplayName', 'Noise', ...
                'UserProperties', ["SoundLevel","Duration","WindowDuration","ApplyWindow", ...
                                   "HighPass","LowPass","TransitionWidth","StopbandAttenuation","FilterOrder"], ...
                varargin{:});
        end

        function update_signal(obj)
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            n = numel(obj.Time);
            highPass = double(obj.selected_value("HighPass"));
            lowPass  = double(obj.selected_value("LowPass"));

            b  = obj.design_band_filter_(highPass, lowPass, double(obj.selected_value("Fs")));
            nb = numel(b);

            % nb - 1 extra samples are the filter's start-up; dropping them
            % leaves n samples that all saw a full filter history.
            y = fftfilt(b, randn(n + nb - 1, 1));
            obj.Signal = y(nb:end).';

            obj.apply_normalization;

            obj.apply_calibration;

            obj.apply_gate;
        end

    end

    methods (Access = protected)

        function b = design_band_filter_(obj, highPass, lowPass, fs)
            % b = design_band_filter_(obj, highPass, lowPass, fs)
            % FIR taps for the band, reused while nothing that shapes them
            % changes (a variant step on another axis regenerates the noise,
            % not the filter).
            nyq = fs / 2;
            if ~(highPass > 0)
                error('stimgen:Noise:InvalidBand', ...
                    'HighPass must be above 0 Hz (it is %g Hz).', highPass);
            end
            if lowPass <= highPass
                error('stimgen:Noise:InvalidBand', 'LowPass must be greater than HighPass.');
            end
            if lowPass >= nyq
                error('stimgen:Noise:InvalidBand', ...
                    'LowPass (%g Hz) must be below Fs/2 (%g Hz).', lowPass, nyq);
            end

            key = [highPass lowPass fs obj.TransitionWidth obj.StopbandAttenuation obj.FilterOrder];
            if isequal(key, obj.filterKey_) && ~isempty(obj.FilterCoefficients)
                b = obj.FilterCoefficients;
                return
            end

            if obj.FilterOrder > 0
                b  = fir1(obj.FilterOrder, [highPass lowPass] / nyq, 'bandpass');
                tw = NaN;
            else
                tw = obj.TransitionWidth;
                if tw == 0
                    tw = 0.1 * min([highPass, lowPass - highPass, nyq - lowPass]);
                end
                edges = [highPass - tw/2, highPass + tw/2, lowPass - tw/2, lowPass + tw/2];
                if edges(1) <= 0 || edges(4) >= nyq || edges(2) >= edges(3)
                    error('stimgen:Noise:InvalidTransition', ...
                        ['A %g Hz transition does not fit the %g-%g Hz band at Fs = %g Hz: ' ...
                         'it must be narrower than HighPass, the bandwidth and the room ' ...
                         'above LowPass (each times two at the edges). Use 0 for automatic.'], ...
                        tw, highPass, lowPass, fs);
                end
                % One dB of margin: kaiserord's order estimate can land a
                % fraction of a dB short of the attenuation it was asked for.
                dev = 10 ^ (-(obj.StopbandAttenuation + 1) / 20);
                [order, wn, beta, ftype] = kaiserord(edges, [0 1 0], [dev dev dev], fs);
                if order > obj.MaxFilterOrder
                    error('stimgen:Noise:FilterTooLong', ...
                        ['Band edges this sharp need a %d-tap filter. Widen ' ...
                         'TransitionWidth or lower StopbandAttenuation.'], order + 1);
                end
                b = fir1(order, wn, ftype, kaiser(order + 1, beta));
            end

            obj.FilterCoefficients = b;
            obj.DesignedOrder      = numel(b) - 1;
            obj.DesignedTransition = tw;
            obj.filterKey_         = key;
        end

        function m = propMeta(obj)
            % propMeta() - Display metadata for Noise GUI properties.
            m = struct();
            m.HighPass = struct('label', 'High Pass Fc (Hz)', 'format', '%.1f Hz', 'limits', [100 40000], ...
                'tooltip', stimgen.util.tooltip(obj, 'HighPass'));
            m.LowPass  = struct('label', 'Low Pass Fc (Hz)',  'format', '%.1f Hz', 'limits', [100 40000], ...
                'tooltip', stimgen.util.tooltip(obj, 'LowPass'));
            m.TransitionWidth = struct('label', 'Transition Width (Hz, 0 = auto)', ...
                'format', '%g', 'limits', [0 20000], ...
                'tooltip', stimgen.util.tooltip(obj, 'TransitionWidth'));
            m.StopbandAttenuation = struct('label', 'Stopband Attenuation (dB)', ...
                'format', '%g', 'limits', [10 150], ...
                'tooltip', stimgen.util.tooltip(obj, 'StopbandAttenuation'));
            m.FilterOrder = struct('label', 'Filter Order (0 = auto)', 'format', '%d', ...
                'limits', [0 2^20], ...
                'tooltip', stimgen.util.tooltip(obj, 'FilterOrder'));
            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.StimType(obj));
        end
    end

end
