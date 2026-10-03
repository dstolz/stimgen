classdef ClickTrain < stimgen.StimType

    % obj = stimgen.ClickTrain(Name,Value,...)
    % Click-train stimulus generator.
    %
    % Generates a train of short-duration clicks at a specified Rate,
    % polarity pattern, and duration.
    
    
    properties (AbortSet,SetObservable)
        Rate        (1,:) double {mustBePositive,mustBeFinite} = 10; % Hz
        % 1 positive, -1 negative, 0 alternating click by click WITHIN the
        % train, 2 alternating whole PRESENTATIONS: the train is generated
        % positive and the presenter inverts every other presentation of
        % it (see alternates_polarity). 2 is the one a single-click
        % stimulus needs -- with one click there is nothing to alternate
        % within, so 0 plays every presentation positive.
        Polarity    (1,:) double {mustBeMember(Polarity,[-1 0 1 2])} = 1;
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
            
            % Defaults first, caller's pairs last, so a caller's value wins.
            obj = obj@stimgen.StimType( ...
                'DisplayName', 'Click Train', ...
                'UserProperties', ["SoundLevel","Duration","WindowDuration","ApplyWindow","Rate","Polarity","ClickDuration","OnsetDelay","Truncate"], ...
                ... % override some default StimType property values
                'Duration', 1, ...
                'ApplyWindow', false, ...
                'WindowFcn', "", ...
                varargin{:});

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
            elseif polarity == 2
                % Alternating presentations: generated positive, flipped
                % by the presenter (alternates_polarity).
                y = repmat(y,1,n);
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

        function tf = alternates_polarity(obj)
            % tf = alternates_polarity(obj) - True when the active variant
            % asks for alternating PRESENTATIONS (Polarity = 2). Within-train
            % alternation (Polarity = 0) is already in the waveform, so the
            % presenter has nothing to add and this stays false for it.
            % Reads the active combination without reselecting.
            v = obj.active_variant_values();
            if isfield(v, 'Polarity')
                p = v.Polarity;
            else
                p = obj.Polarity;
            end
            tf = double(p(1)) == 2;
        end
    end

    methods (Access = protected)
        function m = propMeta(obj)
            % propMeta() - Display metadata for ClickTrain GUI properties.
            m = struct();
            m.Rate          = struct('label', 'Rate (Hz)',           'format', '%.1f Hz',  'limits', [0.1 1e6], ...
                'tooltip', stimgen.util.tooltip(obj, 'Rate'));
            m.ClickDuration = struct('label', 'Click Duration (ms)', 'format', '%.4f ms',  'limits', [0.001 1000], ...
                                     'scale', 1000, ...
                'tooltip', stimgen.util.tooltip(obj, 'ClickDuration'));
            m.Polarity      = struct('label', 'Polarity', 'widget', 'dropdown', ...
                                    'items',     {{'+ Positive', '+/- Alternate clicks', '+/- Alternate presentations', '- Negative'}}, ...
                                    'itemsData', {{1, 0, 2, -1}}, ...
                                    'tooltip', stimgen.util.tooltip(obj, 'Polarity'));
            m.OnsetDelay    = struct('label', 'Onset Delay (ms)',    'format', '%.2f ms',  'limits', [0 10000], ...
                                     'scale', 1000, ...
                'tooltip', stimgen.util.tooltip(obj, 'OnsetDelay'));
            m.Truncate      = struct('label', 'Truncate', ...
                'tooltip', stimgen.util.tooltip(obj, 'Truncate'));
            base = propMeta@stimgen.StimType(obj);
            % Only the caption is retitled here: the ClickTrain section of the
            % tooltip catalog already overrides the inherited Duration text.
            base.Duration.label = 'Train Duration (ms)';
            % The click table is built from each click's peak, as the rms of a
            % sine with the same peak, so a click's level is peak-equivalent.
            % The unit goes in the label because the field is vectorizable and
            % renders as an expression, which ignores format.
            unit = stimgen.util.level_unit("peak");
            base.SoundLevel.label  = sprintf('Sound Level (%s)', unit);
            base.SoundLevel.format = ['%.1f ' unit];
            m = stimgen.StimType.merge_prop_meta(m, base);
        end
    end

end