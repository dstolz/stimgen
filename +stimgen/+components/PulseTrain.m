classdef PulseTrain < stimgen.components.Component
% stimgen.components.PulseTrain
% Periodic pulse / envelope generator.
%
% Covers three things the monolithic classes each solve separately:
%   - Shape "rect" reproduces stimgen.ClickTrain, including its +/-/alternating
%     polarity pattern and onset delay;
%   - Shape "ramped" reproduces the t^(1-|Z|)*(1-t) attack envelope of
%     stimgen.AttackModNoise, with Z < 0 ramped and Z > 0 damped;
%   - Rate 0 emits a single pulse spanning the whole timebase, which makes this
%     a one-shot envelope generator rather than a train.
%
% Connect the output to another node's Amplitude to gate or modulate it: a
% rect train into an Oscillator's Amplitude is a pulsed tone, a ramped train
% into a NoiseSource's Amplitude is ramped/damped noise.
%
% DELIBERATE DIVERGENCE FROM stimgen.ClickTrain
% ClickTrain tiles floor(Duration / periodDuration) whole periods and zero-pads
% the rest, where periodDuration is the period after rounding to an integer
% number of samples. When Duration is not an exact multiple of that rounded
% period it silently drops the last pulse -- a 200 ms train at 20 Hz yields 3
% pulses, not 4. This node instead tiles through the end of the timebase, so
% the pulse count follows Rate and Duration as written. That matters when the
% train is used as a gate: a pulsed tone should not lose its final pulse.
%
% Parameters:
%   Rate       - pulses per second, or 0 for a single pulse over the timebase
%   Width      - pulse width in seconds (ignored when Shape is "ramped",
%                which always fills its period)
%   Shape      - rect | cos2 | ramped
%   Z          - ramped-shape skew in [-1 1]; negative ramps, positive damps
%   Polarity   - +1, alternating, or -1
%   Amplitude  - linear gain (modulatable)
%   OnsetDelay - leading silence in seconds

    properties (Constant)
        Kind        = "PulseTrain";
        Description = "Rect/cos2/ramped pulse train or one-shot envelope";
    end

    methods

        function d = param_defs(~)
            pd = @stimgen.components.Component.pdef;
            d = struct();
            d.Rate = pd('Rate (Hz)', 10, 'format','%.3f Hz', ...
                'limits',[0 1e6], 'order',10, ...
                'doc','Pulses per second. 0 emits one pulse spanning the whole duration.');
            d.Width = pd('Width (ms)', 0.005, 'format','%.4f ms', ...
                'limits',[0 1e5], 'scale',1000, 'order',20, ...
                'doc','Pulse width. Ignored for the "ramped" shape, which fills its period.');
            d.Shape = pd('Shape', "rect", ...
                'items',["rect" "cos2" "ramped"], 'order',30);
            d.Z = pd('Z (ramp/damp)', 0.4, 'format','%.3f', ...
                'limits',[-1 1], 'order',40, ...
                'doc','Ramped-shape skew: negative ramps up, positive damps down.');
            % Single braces: pdef parses its arguments with inputParser, which
            % does not unwrap a cell the way the struct() constructor does.
            d.Polarity = pd('Polarity', 1, 'widget','dropdown', ...
                'items',{'+ Positive','+/- Alternate','- Negative'}, ...
                'itemsData',{1, 0, -1}, 'order',50);
            d.Amplitude = pd('Amplitude', 1, 'format','%.3f', ...
                'modulatable',true, 'order',60);
            d.OnsetDelay = pd('Onset Delay (ms)', 0, 'format','%.2f ms', ...
                'limits',[0 1e5], 'scale',1000, 'order',70);
        end

        function r = nominal_range(~, p)
            % A unipolar train sits in [0 1] or [-1 0]; an alternating one
            % spans [-1 1]. Declaring this lets a connection map the output to
            % unipolar or bipolar form without measuring the data.
            switch round(double(p.Polarity))
                case 0,  r = [-1 1];
                case -1, r = [-1 0];
                otherwise, r = [0 1];
            end
        end

        function y = render(obj, ctx, p)
            N     = ctx.N;
            fs    = ctx.Fs;
            rate  = double(p.Rate);
            width = double(p.Width);
            shape = string(p.Shape);
            z     = double(p.Z);
            pol   = round(double(p.Polarity));

            % --- One period ---
            if rate <= 0
                nPeriod = N;             % single shot spanning the timebase
            else
                nPeriod = max(1, round(fs / rate));
            end

            if shape == "ramped"
                % Fills the period by construction; Width does not apply.
                nPulse = nPeriod;
            else
                nPulse = round(fs * width);
                if nPulse < 1
                    error('stimgen:components:PulseTrain:WidthTooShort', ...
                        'Pulse width is less than one sample at %.4f Hz.', fs);
                end
                if nPulse > nPeriod
                    error('stimgen:components:PulseTrain:WidthExceedsPeriod', ...
                        'Pulse width (%.4f ms) exceeds the period (%.4f ms) at %.3f Hz.', ...
                        width*1e3, nPeriod/fs*1e3, rate);
                end
            end

            switch shape
                case "rect"
                    pulse = ones(1, nPulse);
                case "cos2"
                    pulse = sin(pi .* (0:nPulse-1) ./ max(1, nPulse-1)).^2;
                case "ramped"
                    % t^(1-|z|)*(1-t) on normalized time, peak-normalized.
                    % Ported from stimgen.AttackModNoise.
                    tt    = linspace(0, 1, nPulse);
                    pulse = tt.^(1-abs(z)) .* (1 - tt);
                    if z < 0
                        pulse = fliplr(pulse);
                    end
                    pk = max(pulse);
                    if pk > 0
                        pulse = pulse ./ pk;
                    end
                otherwise
                    error('stimgen:components:PulseTrain:UnknownShape', ...
                        'Unknown pulse shape "%s".', shape);
            end

            period = zeros(1, nPeriod);
            period(1:numel(pulse)) = pulse;

            % --- Tile, applying the polarity pattern ---
            nRep = max(1, ceil(N / nPeriod) + 1);
            if pol == 0
                signs = ones(1, nRep);
                signs(2:2:end) = -1;   % first period stays positive
                % Column-major reshape concatenates the signed periods in order.
                y = reshape(repmat(period(:), 1, nRep) .* repmat(signs, nPeriod, 1), 1, []);
            else
                y = repmat(pol .* period, 1, nRep);
            end

            % --- Onset delay, then conform to the global timebase ---
            nDelay = max(0, round(fs * double(p.OnsetDelay)));
            if nDelay > 0
                y = [zeros(1, nDelay) y];
            end
            y = obj.fit(y, N);

            y = obj.fit(y .* obj.expand(p.Amplitude, N), N);
        end

    end % methods

end
