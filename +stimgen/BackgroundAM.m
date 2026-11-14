classdef BackgroundAM < stimgen.BackgroundModulation

    % obj = stimgen.BackgroundAM(Name,Value,...)
    % Amplitude modulation OF AN ONGOING BACKGROUND, for Duration seconds.
    %
    % Class guide: documentation/stimgen_Background.md
    %
    % The background (base-class Background, by default band-passed noise) is
    % steady; for this stimulus's Duration its amplitude is modulated
    % sinusoidally about its steady value:
    %
    %   G(t) = 1 + AMDepth * w(t) * sin(2*pi*AMRate*t + OnsetPhase)
    %
    % w is the gate (WindowDuration, WindowFcn), applied to the modulation and
    % not to the carrier. With OnsetPhase = 0 the envelope leaves 1 rising and,
    % over a whole number of cycles, returns to it; any other phase or cycle
    % count is carried in and out by the gate.
    %
    % Unlike stimgen.AMnoise -- a gated AM noise BURST, renormalized so its
    % overall rms is SoundLevel -- nothing here is renormalized: SoundLevel is
    % the level of the steady background, and the modulated epoch is louder
    % than it by 10*log10(1 + AMDepth^2/2) (1.76 dB at full depth).
    %
    % Example:
    %   am = stimgen.BackgroundAM('AMRate', 10, 'AMDepth', [0.25 0.5 1], ...
    %       'Duration', 0.5, 'BackgroundHighPass', 4000, 'BackgroundLowPass', 16000);
    %   E  = am.get_embedding();     % E.Gain is the envelope, E.Signal zeros

    properties (SetObservable,AbortSet)
        AMRate     (1,:) double {mustBePositive,mustBeFinite} = 10; % Hz
        AMDepth    (1,:) double {mustBeGreaterThanOrEqual(AMDepth,0),mustBeLessThanOrEqual(AMDepth,1)} = 1; % [0 1]
        OnsetPhase (1,:) double {mustBeFinite} = 0; % degrees
    end

    methods

        function obj = BackgroundAM(varargin)
            % Defaults first, caller's pairs last, so a caller's value wins.
            obj = obj@stimgen.BackgroundModulation( ...
                'DisplayName', 'Background AM', ...
                'UserProperties', ["SoundLevel","Duration","WindowDuration","ApplyWindow", ...
                                   "AMRate","AMDepth","OnsetPhase"], ...
                'Duration', 0.5, ...   % five cycles at the default rate
                varargin{:});
        end

    end

    methods (Access = protected)

        function [g, phi] = modulation_(obj, t, w)
            rate  = double(obj.selected_value("AMRate"));
            depth = double(obj.selected_value("AMDepth"));
            phase = deg2rad(double(obj.selected_value("OnsetPhase")));
            g   = 1 + depth .* w .* sin(2*pi .* rate .* t + phase);
            phi = [];
        end

        function m = propMeta(obj)
            % propMeta() - Display metadata for BackgroundAM GUI properties.
            m = struct();
            m.AMRate = struct('label', 'AM Rate (Hz)', 'format', '%.1f Hz', 'limits', [0.1 2000], ...
                'tooltip', stimgen.util.tooltip(obj, 'AMRate'));
            m.AMDepth = struct('label', 'AM Depth (0-1)', 'format', '%.2f', 'limits', [0 1], ...
                'tooltip', stimgen.util.tooltip(obj, 'AMDepth'));
            m.OnsetPhase = struct('label', 'Onset Phase (deg)', 'format', '%.1f deg', ...
                'tooltip', stimgen.util.tooltip(obj, 'OnsetPhase'));
            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.BackgroundModulation(obj));
        end

    end

end
