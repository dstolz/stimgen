classdef BackgroundFM < stimgen.BackgroundModulation

    % obj = stimgen.BackgroundFM(Name,Value,...)
    % Frequency modulation OF AN ONGOING TONE, for Duration seconds.
    %
    % Class guide: documentation/stimgen_Background.md
    %
    % The background is a steady tone (Background = "Tone", at
    % BackgroundFrequency); for this stimulus's Duration its instantaneous
    % frequency deviates by
    %
    %   df(t) = FMDeviation * w(t) * sin(2*pi*FMRate*t + OnsetPhase)     [Hz]
    %
    % and the phase deviation handed to a presenter is its running integral,
    % theta(n) = 2*pi/Fs * sum(df(1:n-1)), which starts at 0. w is the gate,
    % applied to the deviation: the tone itself never stops, and its
    % amplitude never changes. Whatever phase the modulation ends on is where
    % the tone carries on from, so the waveform is continuous at both ends.
    %
    % Unlike stimgen.FMtone -- a gated FM tone BURST -- this has no onset of
    % its own. It needs a tone to act on and refuses a noise background.
    %
    % Example:
    %   fm = stimgen.BackgroundFM('BackgroundFrequency', [4000 8000 16000], ...
    %       'FMRate', 10, 'FMDeviation', 200, 'Duration', 0.5);

    properties (SetObservable,AbortSet)
        FMRate      (1,:) double {mustBePositive,mustBeFinite} = 10;      % Hz
        FMDeviation (1,:) double {mustBeNonnegative,mustBeFinite} = 100;  % Hz, peak
        OnsetPhase  (1,:) double {mustBeFinite} = 0; % degrees, of the modulator
    end

    methods

        function obj = BackgroundFM(varargin)
            % Defaults first, caller's pairs last, so a caller's value wins.
            obj = obj@stimgen.BackgroundModulation( ...
                'DisplayName', 'Background FM', ...
                'UserProperties', ["SoundLevel","Duration","WindowDuration","ApplyWindow", ...
                                   "FMRate","FMDeviation","OnsetPhase"], ...
                'Duration', 0.5, ...   % five cycles at the default rate
                'Background', "Tone", ...
                varargin{:});
        end

    end

    methods (Access = protected)

        function [g, phi] = modulation_(obj, t, w)
            if obj.Background ~= "Tone"
                error('stimgen:BackgroundFM:NeedsToneBackground', ...
                    ['Frequency modulation needs a tone to act on: set Background ' ...
                     'to "Tone" (it is "%s").'], obj.Background);
            end
            rate  = double(obj.selected_value("FMRate"));
            dev   = double(obj.selected_value("FMDeviation"));
            phase = deg2rad(double(obj.selected_value("OnsetPhase")));
            fs    = double(obj.Fs);

            df  = dev .* w .* sin(2*pi .* rate .* t + phase);
            phi = (2*pi / fs) .* [0, cumsum(df(1:end-1))];
            g   = [];
        end

        function c = background_choices_(~)
            c = "Tone";
        end

        function m = propMeta(obj)
            % propMeta() - Display metadata for BackgroundFM GUI properties.
            m = struct();
            m.FMRate = struct('label', 'FM Rate (Hz)', 'format', '%.1f Hz', 'limits', [0.1 2000], ...
                'tooltip', stimgen.util.tooltip(obj, 'FMRate'));
            m.FMDeviation = struct('label', 'FM Deviation (Hz)', 'format', '%.1f Hz', 'limits', [0 20000], ...
                'tooltip', stimgen.util.tooltip(obj, 'FMDeviation'));
            m.OnsetPhase = struct('label', 'Onset Phase (deg)', 'format', '%.1f deg', ...
                'tooltip', stimgen.util.tooltip(obj, 'OnsetPhase'));
            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.BackgroundModulation(obj));
        end

    end

end
