classdef Tone < stimgen.StimType

    % obj = stimgen.Tone(Name,Value,...)
    % Pure-tone stimulus generator.
    %
    % Generates a sine tone at Frequency for Duration seconds, optionally
    % windowed/gated and calibrated.
    
    properties (SetObservable,AbortSet)
        Frequency  (1,:) double {mustBePositive,mustBeFinite} = 1000; % Hz
        OnsetPhase (1,:) double = 0;
        
        % How WindowDuration is interpreted: as a time in seconds
        % ("Duration"), as a percentage of Duration ("Proportional"), or as
        % a number of carrier periods per ramp ("#Periods"). The conversion
        % to seconds happens in effective_window_duration_, so the stored
        % WindowDuration always stays in the units the user typed.
        WindowMethod  (1,1) string {mustBeMember(WindowMethod,["Duration" "Proportional" "#Periods"])} = "Duration"
    end

    
    
    properties (Constant)
        IsMultiObj      = false;
        CalibrationType = "tone";
        Normalization   = "absmax";
    end
    
    methods
        function obj = Tone(varargin)
            obj = obj@stimgen.StimType(varargin{:});

            obj.DisplayName = 'Tone';

            obj.UserProperties = ["Frequency","SoundLevel","Duration","WindowDuration","ApplyWindow","OnsetPhase","WindowMethod"];
        end
        
        function update_signal(obj)
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            t = obj.Time;
            freq = double(obj.selected_value("Frequency"));
            onsetPhase = double(obj.selected_value("OnsetPhase"));
            
            obj.Signal = sin(2.*pi.*freq.*t+onsetPhase);


            obj.apply_normalization;
            
            obj.apply_calibration;
            
            obj.apply_gate;
        end
        
    end

    methods (Access = protected)
        function m = propMeta(obj)
            % propMeta() - Display metadata for Tone GUI properties.
            m = struct();
            m.Frequency    = struct('label', 'Frequency',     'format', '%.1f Hz',  'limits', [100 40000], ...
                'tooltip', 'Tone frequency in Hz. Also the key used to look up the calibrated level. Enter a vector, e.g. 2000:1000:8000, to make one variant per frequency.');
            m.OnsetPhase   = struct('label', 'Onset Phase',   'format', '%.1f deg', ...
                'tooltip', 'Starting phase of the carrier in degrees. 0 starts at zero crossing, 90 at the positive peak.');
            % Grouped with Timing (order 20) so it sits next to Duration
            % (order 10) and WindowDuration (order 30), which it controls.
            m.WindowMethod = struct('label', 'Window Method', 'widget', 'dropdown', ...
                'items', ["Duration" "Proportional" "#Periods"], 'group', 'Timing', 'order', 20, ...
                'tooltip', 'Units for Window Duration: Duration = milliseconds; Proportional = percent of Duration; #Periods = carrier periods per ramp. Changing this resets Window Duration.');
            base = propMeta@stimgen.StimType(obj);

            % WindowMethod reinterprets WindowDuration: only the "Duration"
            % method treats it as a time, so only that one is shown in ms.
            switch obj.WindowMethod
                case "Proportional"
                    base.WindowDuration = struct('label', 'Window Duration (%)', ...
                        'format', '%.2f %%', 'limits', [0 100], 'group', 'Timing', 'order', 30, ...
                        'tooltip', 'Combined onset + offset gate length as a percent of Duration; each ramp is half this value. Ignored when Apply Window is off.');
                case "#Periods"
                    base.WindowDuration = struct('label', 'Window Duration (periods)', ...
                        'format', '%.1f periods', 'limits', [0 1e4], 'group', 'Timing', 'order', 30, ...
                        'tooltip', 'Length of each onset and offset ramp in carrier periods, so the ramp scales with Frequency. Ignored when Apply Window is off.');
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