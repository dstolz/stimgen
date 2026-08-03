classdef ClickTrain < stimgen.StimType

    % obj = stimgen.ClickTrain(Name,Value,...)
    % Click-train stimulus generator.
    %
    % Generates a train of short-duration clicks at a specified Rate,
    % polarity pattern, and duration.
    
    
    properties (AbortSet,SetObservable)
        Rate        (1,:) double {mustBePositive,mustBeFinite} = 10; % Hz
        Polarity    (1,:) double {mustBeMember(Polarity,[-1 0 1])} = 1;
        ClickDuration (1,:) double {mustBePositive,mustBeFinite} = 20e-6; % s
        OnsetDelay  (1,:) double {mustBeNonnegative,mustBeFinite} = 0; % sec
        Truncate    (1,:) logical = false;
    end
    
    properties (Dependent)
        ClickInterval
    end

    
    properties (Constant)
        IsMultiObj      = false;
        CalibrationType = "click";
        Normalization   = "absmax"
    end
    
    methods
        
        function obj = ClickTrain(varargin)
            
            obj = obj@stimgen.StimType(varargin{:});

            obj.DisplayName = 'Click Train';

            obj.UserProperties = ["SoundLevel","Duration","WindowDuration","ApplyWindow","Rate","Polarity","ClickDuration","OnsetDelay","Truncate"];

            % override some default StimType property values
            obj.Duration = 1;
            obj.ApplyWindow = false;
            obj.WindowFcn = "";
            
            
        end
        
        
        function ci = get.ClickInterval(obj)
            ci = 1/obj.Rate;
        end
        
        function update_signal(obj)
            if ~obj.variantCycleActive_
                obj.call_update_signal_with_variant_cycle_();
                return
            end

            fsValue = double(obj.selected_value("Fs"));
            d = double(obj.selected_value("Duration"));
            rate = double(obj.selected_value("Rate"));
            polarity = double(obj.selected_value("Polarity"));
            clickDuration = double(obj.selected_value("ClickDuration"));
            onsetDelay = double(obj.selected_value("OnsetDelay"));
            truncateValue = logical(obj.selected_value("Truncate"));

            p = 1 / rate;

            assert(clickDuration <= p,'stimgen:ClickTrain:ClickDuration:InvalidValue', ...
                'Click duration is too long for the selected click Rate');
            assert(round(fsValue*clickDuration) > 0,'stimgen:ClickTrain:ClickDuration:InvalidValue', ...
                'Click duration is less than 1 sample at the current sampling rate');
            
            y = ones(1,round(fsValue*clickDuration));
            
            
            yoff = zeros(1,round(fsValue*p)-length(y));
            y = [y yoff];
            
            yd = length(y)/fsValue;
            n = max(floor(d / yd),1);
            
            if polarity == 0
                x = -1;
                yx = y;
                for i = 2:n
                    y = [y x*yx];
                    x = -x;
                end
            else
                y = polarity .* y;
                y = repmat(y,1,n);
            end
            
            yon  = zeros(1,max(round(fsValue*onsetDelay-1/fsValue),0));
            y = [yon y];
            
            if ~truncateValue && obj.N > length(y)
                y = [y,zeros(1,obj.N-length(y))];
            elseif obj.N < length(y)
                y(obj.N+1:end) = [];
            end
            
            obj.Signal = y;
            
            
            obj.apply_normalization;
            
            obj.apply_calibration;
            
            obj.apply_gate;
        end
    end

    methods (Access = protected)
        function m = propMeta(obj)
            % propMeta() - Display metadata for ClickTrain GUI properties.
            m = struct();
            m.Rate          = struct('label', 'Rate',                'format', '%.1f Hz',  'limits', [0.1 1e6], ...
                'tooltip', 'Clicks per second. The click interval 1/Rate must be at least Click Duration. Vectorizable.');
            m.ClickDuration = struct('label', 'Click Duration (ms)', 'format', '%.4f ms',  'limits', [0.001 1000], ...
                                     'scale', 1000, ...
                'tooltip', 'Width of a single click in ms; also the key used to look up the calibrated level. Must be at least one sample at the current Fs.');
            m.Polarity      = struct('label', 'Polarity', 'widget', 'dropdown', ...
                                    'items',     {{'+ Positive', '+/- Alternate', '- Negative'}}, ...
                                    'itemsData', {{1, 0, -1}}, ...
                                    'tooltip', 'Sign of each click. Alternate flips polarity click by click, which cancels stimulus artifact when responses are averaged.');
            m.OnsetDelay    = struct('label', 'Onset Delay (ms)',    'format', '%.2f ms',  'limits', [0 10000], ...
                                     'scale', 1000, ...
                'tooltip', 'Silence inserted in ms before the first click. The train shifts later within Train Duration rather than extending it.');
            m.Truncate      = struct('label', 'Truncate', ...
                'tooltip', 'Cut the train at Train Duration instead of zero-padding to it, so a train that does not fit a whole number of clicks ends early.');
            base = propMeta@stimgen.StimType(obj);
            base.Duration.label = 'Train Duration (ms)';
            base.Duration.tooltip = 'Total length of the click train in ms. Clicks that do not fit a whole interval are dropped; the remainder is zero-padded unless Truncate is on.';
            m = stimgen.StimType.merge_prop_meta(m, base);
        end
    end

end