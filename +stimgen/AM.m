classdef AM < stimgen.StimType

    % obj = stimgen.AM(Name,Value,...)
    % Amplitude-modulation envelope, carrier-free.
    %
    % Generates the sinusoidal AM envelope itself (no carrier), for use as a
    % standalone stimulus or as a live modulator via
    % stimgen.continuous.Playable's EnvelopeSourceClass. Equivalent to
    % stimgen.AMnoise with its noise carrier removed.

    properties (SetObservable,AbortSet)
        AMDepth (1,:) double {mustBeGreaterThanOrEqual(AMDepth,0),mustBeLessThanOrEqual(AMDepth,1)} = 1; % [0 1]
        AMRate  (1,:) double {mustBePositive,mustBeFinite} = 5; % Hz

        OnsetPhase (1,:) double = 180; % degrees

        ApplyViemeisterCorrection (1,1) logical = true;
    end



    properties (Constant)
        IsMultiObj      = false;
        CalibrationType = "filter";
        Normalization   = "rms";
    end

    methods

        function obj = AM(varargin)
            obj = obj@stimgen.StimType(varargin{:});

            obj.DisplayName = 'AM';
            obj.UserProperties = ["SoundLevel","Duration","WindowDuration","ApplyWindow","AMDepth","AMRate","OnsetPhase","ApplyViemeisterCorrection"];

            obj.Duration = 1;

            % No carrier means no spectral content to equalize; only the
            % scalar LUT level scaling (anchored at ReferenceFrequency,
            % since value resolves to NaN for "filter") applies.
            obj.suppressCalFilter_ = true;
        end


        function update_signal(obj)
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            % x(t) = A(t) sin(2 pi fc t)
            % A(t) = A [1 + m sin(2 pi fm t)]

            amDepth = double(obj.selected_value("AMDepth"));
            amRate = double(obj.selected_value("AMRate"));
            onsetPhase = double(obj.selected_value("OnsetPhase"));

            am = cos(2.*pi.*amRate.*obj.Time+deg2rad(onsetPhase));
            am = (am + 1)./2;
            am = am .* amDepth + 1 - amDepth;

            if obj.ApplyViemeisterCorrection
                am = am .* sqrt(1/(amDepth^2/2+1));
            end

            obj.Signal = am;

            obj.apply_normalization;

            obj.apply_calibration;

            obj.apply_gate;
        end
    end

    methods (Access = protected)
        function m = propMeta(obj)
            % propMeta() - Display metadata for AM GUI properties.
            m = struct();
            m.AMDepth    = struct('label', 'AM Depth',              'format', '%.2f',     'limits', [0 1]);
            m.AMRate     = struct('label', 'AM Rate',               'format', '%.1f Hz',  'limits', [0.1 500]);
            m.OnsetPhase = struct('label', 'Onset Phase',           'format', '%.1f deg');
            m.ApplyViemeisterCorrection  = struct('label', 'Viemeister Correction');
            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.StimType(obj));
        end
    end

end
