classdef Tone < stimgen.StimType

    % obj = stimgen.Tone(Name,Value,...)
    % Pure-tone stimulus generator.
    %
    % Generates a sine tone at Frequency for Duration seconds, optionally
    % windowed/gated and calibrated.
    
    properties (SetObservable,AbortSet)
        Frequency  (1,:) double {mustBePositive,mustBeFinite} = 1000; % Hz
        OnsetPhase (1,:) double = 0; % degrees

        % Sign of the waveform: 1 positive, -1 inverted, 0 alternating. The
        % alternation is ACROSS PRESENTATIONS -- a tone pip has no train to
        % flip within, unlike ClickTrain -- so 0 generates the positive
        % waveform and leaves the flipping to whoever presents it (see
        % alternates_polarity). Unlike OnsetPhase = [0 180], which makes two
        % variants and so doubles the presentations, alternating keeps one
        % variant and splits its repetitions between the two signs.
        Polarity   (1,:) double {mustBeMember(Polarity,[-1 0 1])} = 1;
        
        % How WindowDuration is interpreted: as a time in seconds
        % ("Duration"), as a percentage of Duration ("Proportional"), or as
        % a number of carrier periods per ramp ("#Periods"). The conversion
        % to seconds happens in effective_window_duration_, so the stored
        % WindowDuration always stays in the units the user typed.
        WindowMethod  (1,1) string {mustBeMember(WindowMethod,["Duration" "Proportional" "#Periods"])} = "Duration"
    end

    
    
    properties (Constant)
        CalibrationType = "tone";
        Normalization   = "absmax";
    end
    
    methods
        function obj = Tone(varargin)
            % Defaults first, caller's pairs last, so a caller's value wins.
            obj = obj@stimgen.StimType( ...
                'DisplayName', 'Tone', ...
                'UserProperties', ["Frequency","SoundLevel","Duration","WindowDuration","ApplyWindow","OnsetPhase","Polarity","WindowMethod"], ...
                varargin{:});
        end
        
        function update_signal(obj)
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            t = obj.Time;
            freq = double(obj.selected_value("Frequency"));
            onsetPhase = double(obj.selected_value("OnsetPhase"));
            polarity = double(obj.selected_value("Polarity"));
            
            % OnsetPhase is in degrees (label, tooltip and docs all say so),
            % the same convention AMnoise follows.
            obj.Signal = sin(2.*pi.*freq.*t+deg2rad(onsetPhase));

            % Alternating (0) is generated positive; the presenter inverts
            % every other presentation (alternates_polarity).
            if polarity == -1
                obj.Signal = -obj.Signal;
            end


            obj.apply_normalization;
            
            obj.apply_calibration;
            
            obj.apply_gate;
        end

        function tf = alternates_polarity(obj)
            % tf = alternates_polarity(obj) - True when the active variant
            % asks for alternating polarity (Polarity = 0), i.e. the
            % presenter should invert every other presentation of it.
            % Reads the active combination without reselecting, so it
            % describes the waveform currently in Signal.
            v = obj.active_variant_values();
            if isfield(v, 'Polarity')
                p = v.Polarity;
            else
                p = obj.Polarity;
            end
            tf = double(p(1)) == 0;
        end
        
    end

    methods (Access = protected)
        function m = propMeta(obj)
            % propMeta() - Display metadata for Tone GUI properties.
            m = struct();
            m.Frequency    = struct('label', 'Frequency (Hz)', 'format', '%.1f Hz',  'limits', [100 40000], ...
                'tooltip', stimgen.util.tooltip(obj, 'Frequency'));
            m.OnsetPhase   = struct('label', 'Onset Phase (deg)', 'format', '%.1f deg', ...
                'tooltip', stimgen.util.tooltip(obj, 'OnsetPhase'));
            m.Polarity     = struct('label', 'Polarity', 'widget', 'dropdown', ...
                'items',     {{'+ Positive', '+/- Alternate', '- Negative'}}, ...
                'itemsData', {{1, 0, -1}}, ...
                'tooltip', stimgen.util.tooltip(obj, 'Polarity'));
            % Grouped with Timing (order 20) so it sits next to Duration
            % (order 10) and WindowDuration (order 30), which it controls.
            m.WindowMethod = struct('label', 'Window Method', 'widget', 'dropdown', ...
                'items', ["Duration" "Proportional" "#Periods"], 'group', 'Timing', 'order', 20, ...
                'tooltip', stimgen.util.tooltip(obj, 'WindowMethod'));
            base = propMeta@stimgen.StimType(obj);

            % WindowMethod reinterprets WindowDuration: only the "Duration"
            % method treats it as a time, so only that one is shown in ms.
            % Each case carries its own tooltip, keyed by method in the
            % catalog since one property name covers three sets of units.
            switch obj.WindowMethod
                case "Proportional"
                    base.WindowDuration = struct('label', 'Window Duration (%)', ...
                        'format', '%.2f %%', 'limits', [0 100], 'group', 'Timing', 'order', 30, ...
                        'tooltip', stimgen.util.tooltip(obj, 'WindowDuration_Proportional'));
                case "#Periods"
                    base.WindowDuration = struct('label', 'Window Duration (periods)', ...
                        'format', '%.1f periods', 'limits', [0 1e4], 'group', 'Timing', 'order', 30, ...
                        'tooltip', stimgen.util.tooltip(obj, 'WindowDuration_Periods'));
            end

            m = stimgen.StimType.merge_prop_meta(m, base);
        end

        function d = effective_window_duration_(obj)
            % Convert WindowDuration from the units WindowMethod declares
            % into the total onset+offset gate length in seconds.
            % apply_gate splits the window in half, so a per-ramp figure
            % such as "#Periods" is doubled here.
            d = double(obj.selected_value("WindowDuration"));

            switch obj.WindowMethod
                case "Proportional"
                    d = d / 100 * double(obj.selected_value("Duration"));
                case "#Periods"
                    d = 2 * d / double(obj.selected_value("Frequency"));
            end
        end

        function d = default_window_duration_(obj)
            % Default WindowDuration for the current WindowMethod, in that
            % method's units. A value carried over from another method is
            % meaningless (2 ms is not a sensible 2 %), so switching methods
            % resets the field rather than reinterpreting the old number.
            switch obj.WindowMethod
                case "Proportional"
                    d = 10;    % percent of Duration, both ramps together
                case "#Periods"
                    d = 5;     % carrier periods per ramp
                otherwise
                    d = 0.002; % seconds -> 2 ms, the base-class default
            end
        end

        function on_gui_changed(obj, propName, ~)
            % Re-render the WindowDuration widget when WindowMethod changes:
            % the method redefines its units, so its label, display scale
            % and value all have to follow.
            if ~strcmp(propName, 'WindowMethod')
                return
            end
            obj.WindowDuration = obj.default_window_duration_();
            obj.refresh_gui_widget('WindowDuration');
        end
    end
end