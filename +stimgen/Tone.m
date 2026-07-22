classdef Tone < stimgen.StimType

    % obj = stimgen.Tone(Name,Value,...)
    % Pure-tone stimulus generator.
    %
    % Generates a sine tone at Frequency for Duration seconds, optionally
    % windowed/gated and calibrated.
    
    properties (SetObservable,AbortSet)
        Frequency  (1,:) double {mustBePositive,mustBeFinite} = 1000; % Hz
        OnsetPhase (1,:) double = 0;
        
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
            
            
            switch obj.WindowMethod
                case 'Duration'
                    % no conversion needed
                case 'Proportional'
                    obj.WindowDuration = obj.WindowDuration/100*t(end);
                case '#Periods'
                    obj.WindowDuration = 2*obj.WindowDuration/freq;
            end
            
            
            obj.apply_normalization;
            
            obj.apply_calibration;
            
            obj.apply_gate;
        end
        
    end

    methods (Access = protected)
        function m = propMeta(obj)
            % propMeta() - Display metadata for Tone GUI properties.
            m = struct();
            m.Frequency    = struct('label', 'Frequency',     'format', '%.1f Hz',  'limits', [100 40000]);
            m.OnsetPhase   = struct('label', 'Onset Phase',   'format', '%.1f deg');
            % Grouped with Timing (order 20) so it sits next to Duration
            % (order 10) and WindowDuration (order 30), which it controls.
            m.WindowMethod = struct('label', 'Window Method', 'widget', 'dropdown', ...
                'items', ["Duration" "Proportional" "#Periods"], 'group', 'Timing', 'order', 20);
            base = propMeta@stimgen.StimType(obj);

            % WindowMethod reinterprets WindowDuration: only the "Duration"
            % method treats it as a time, so only that one is shown in ms.
            switch obj.WindowMethod
                case "Proportional"
                    base.WindowDuration = struct('label', 'Window Duration (%)', ...
                        'format', '%.2f %%', 'limits', [0 100], 'group', 'Timing', 'order', 30);
                case "#Periods"
                    base.WindowDuration = struct('label', 'Window Duration (periods)', ...
                        'format', '%.1f periods', 'limits', [0 1e4], 'group', 'Timing', 'order', 30);
            end

            m = stimgen.StimType.merge_prop_meta(m, base);
        end

        function on_gui_changed(obj, propName, ~)
            % Re-render the WindowDuration widget when WindowMethod changes,
            % since the method changes both its units and its display scale.
            if ~strcmp(propName, 'WindowMethod')
                return
            end
            if ~isstruct(obj.GUIHandles) || ~isfield(obj.GUIHandles, 'WindowDuration') ...
                    || ~isvalid(obj.GUIHandles.WindowDuration)
                return
            end
            x  = obj.GUIHandles.WindowDuration;
            pm = obj.propMeta().WindowDuration;
            if isprop(x, 'ValueDisplayFormat')
                x.ValueDisplayFormat = pm.format;
                x.Value = obj.WindowDuration * stimgen.StimType.display_scale(pm);
            else
                x.UserData = struct('isNumericExpression', true, 'propMeta', pm);
                x.Value = stimgen.StimType.localFormatPropertyValue_( ...
                    obj.WindowDuration * stimgen.StimType.display_scale(pm));
            end
        end
    end
end