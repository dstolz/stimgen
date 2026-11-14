classdef (Abstract) BackgroundModulation < stimgen.StimType

    % stimgen.BackgroundModulation
    % Abstract base for a stimulus that is a MODULATION OF AN ONGOING
    % BACKGROUND rather than a sound of its own: amplitude modulation of a
    % continuous noise, a silent gap in it, frequency modulation of a steady
    % tone.
    %
    % Class guide: documentation/stimgen_Background.md
    %
    % The background is the base class's own (Background, BackgroundHighPass,
    % ...). What a subclass adds is the operator that acts on it for the
    % stimulus's Duration, returned by modulation_:
    %
    %   gain   G(t), multiplying the background     (BackgroundAM, BackgroundGap)
    %   phase  theta(t), added to a tone's phase    (BackgroundFM)
    %
    % A presenter that plays the background continuously (see
    % StimType.get_embedding) applies that operator at each presentation and
    % adds nothing. Signal is the stand-alone rendition -- the background over
    % the stimulus's Duration with the modulation applied -- which is what
    % Play, the inspector and a presenter without background support use.
    %
    % Three rules hold for every subclass:
    %
    %   - The gate shapes the MODULATION, never the carrier. WindowDuration
    %     and WindowFcn ramp the deviation (from gain 1, from zero frequency
    %     deviation) in and out, so an event joins the steady background
    %     smoothly whatever its phase or cycle count. The carrier itself is
    %     not gated: it is ongoing.
    %   - There is ONE level. SoundLevel is the level of the background being
    %     modulated; BackgroundLevel is unused and not shown.
    %   - The level is carrier-referenced. Signal is not renormalized after
    %     the modulation is applied, so a 100 % AM epoch has more power than
    %     the steady background by 10*log10(mean(G.^2)) = +1.76 dB and a gap
    %     has less; level_offset_db reports that figure, and
    %     stimgen.util.level_request passes it on so a level check does not
    %     read it as a calibration error.
    %
    % Kept in a class folder so StimType.list() -- which globs loose files --
    % cannot offer the abstract base as a stimulus.

    properties (Constant)
        % Declared once for the family: neither can follow the Background
        % type, which is a property. "filter"/"rms" make level_request
        % measure a broadband rms -- right for a noise carrier, and for a
        % tone the same rms dB SPL its table defines.
        CalibrationType = "filter";
        Normalization   = "rms";
    end

    % The operators of the waveform currently in Signal. Written by
    % update_signal in the same pass as Signal; not observable, so writing
    % them cannot re-enter it.
    properties (SetAccess = protected)
        Gain  (1,:) double = []   % gain envelope; [] when the modulation has none
        Phase (1,:) double = []   % phase deviation in radians, from 0; [] when none
    end

    methods (Abstract, Access = protected)
        % [g, phi] = modulation_(obj, t, w)
        % The operator for the active combination.
        %   t   - (1,N) time in seconds
        %   w   - (1,N) gate in [0,1] to multiply the DEVIATION by
        %   g   - (1,N) gain envelope, or []
        %   phi - (1,N) phase deviation in radians starting at 0, or []
        [g, phi] = modulation_(obj, t, w)
    end

    methods

        function obj = BackgroundModulation(varargin)
            % A modulation needs something to modulate: the default
            % background is Noise, ahead of varargin so a subclass or a
            % caller can name another.
            obj = obj@stimgen.StimType('Background', "Noise", varargin{:});
        end

        function update_signal(obj)
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            % Drop the waveform as well as raising. MATLAB downgrades an
            % error raised under a property listener to a warning, and a
            % stale Signal left behind would be played -- with the old
            % modulation -- by callers that regenerate only when Signal is
            % empty (the same reasoning as apply_calibration's rate check).
            try
                [y, g, phi] = obj.generate_();
            catch ME
                obj.Signal = [];
                obj.Gain   = [];
                obj.Phase  = [];
                rethrow(ME)
            end

            obj.Gain   = g;
            obj.Phase  = phi;
            obj.Signal = y;
        end

        function E = get_embedding(obj)
            % E = get_embedding(obj)
            % Mode "modulate": nothing is added to the background, and Gain
            % and/or Phase are applied to it over the stimulus. Signal is
            % zeros of the stimulus's length, so a presenter's timing,
            % duration and overlap arithmetic see an ordinary entry.
            if isempty(obj.Signal)
                obj.call_update_signal_with_variant_cycle_();
            end
            E = struct( ...
                'Mode',       "modulate", ...
                'Signal',     zeros(1, numel(obj.Signal)), ...
                'Gain',       [], ...
                'Phase',      [], ...
                'Background', []);
            E.Gain       = obj.Gain;
            E.Phase      = obj.Phase;
            E.Background = obj.get_background();
        end

        function d = level_offset_db(obj)
            % d = level_offset_db(obj)
            % How far the rms of Signal is expected to sit from SoundLevel,
            % in dB: 10*log10(mean(Gain.^2)). 0 for a phase modulation,
            % which leaves the rms alone.
            if isempty(obj.Gain)
                d = 0;
            else
                d = 10 * log10(max(mean(obj.Gain .^ 2), realmin));
            end
        end

    end

    methods (Access = protected)

        function [y, g, phi] = generate_(obj)
            % The stand-alone waveform and the operators it was made with.
            if obj.Background == "None"
                error('stimgen:BackgroundModulation:NoBackground', ...
                    ['%s is a modulation of a background and needs one: ' ...
                     'set Background to "Noise" or "Tone".'], class(obj));
            end

            t = obj.Time;
            n = numel(t);
            [g, phi] = obj.modulation_(t, obj.deviation_gate_(n));

            spec = obj.background_spec_();
            switch obj.Background
                case "Noise"
                    if ~isempty(phi)
                        error('stimgen:BackgroundModulation:PhaseNeedsTone', ...
                            ['A phase (frequency) modulation needs a tone to act on; ' ...
                             'the background is noise.']);
                    end
                    % Fresh noise of the stimulus's own length: the 10 s
                    % loop a presenter tiles is not built for a preview.
                    B = stimgen.util.background_source(spec, obj.Calibration, n);
                    y = B.Waveform;
                case "Tone"
                    B = stimgen.util.background_source(spec, obj.Calibration);
                    y = 2*pi .* B.Frequency .* t;
                    if ~isempty(phi)
                        y = y + phi;
                    end
                    y = B.Amplitude .* sin(y);
            end

            if ~isempty(g)
                y = y .* g;
            end
        end

        function w = deviation_gate_(obj, n)
            % w = deviation_gate_(obj, n)
            % The base class's gate as a 0..1 window over n samples: ones
            % run through apply_gate, so WindowDuration, WindowFcn,
            % ApplyWindow and the shrink-to-fit rule are apply_gate's own
            % and not a second reading of them.
            obj.Signal = ones(1, n);
            obj.apply_gate();
            w = obj.Signal;
        end

        function L = background_level_(obj)
            % One level: the carrier's is SoundLevel.
            L = double(obj.active_value_("SoundLevel"));
        end

        function tf = is_inactive_background_property_(obj, propName)
            % BackgroundLevel is never used here, so never a variant axis.
            tf = string(propName) == "BackgroundLevel" ...
                || is_inactive_background_property_@stimgen.StimType(obj, propName);
        end

        function c = background_choices_(~)
            % Background types this modulation can act on.
            c = ["Noise" "Tone"];
        end

        function m = propMeta(obj)
            % The base rows, with the background's level folded into Sound
            % Level and "None" taken off the list.
            m = propMeta@stimgen.StimType(obj);
            if isfield(m, 'BackgroundLevel')
                m = rmfield(m, 'BackgroundLevel');
            end
            % A value set from code that the list does not offer is appended:
            % a dropdown cannot show a value it has no item for (the same
            % rule propMeta applies to WindowFcn). update_signal is what
            % refuses it.
            items = obj.background_choices_();
            if ~any(items == obj.Background)
                items(end+1) = obj.Background;
            end
            m.Background.items = items;
            m.SoundLevel.label = 'Background Level (dB SPL)';
        end

    end

end
