classdef NoiseSource < stimgen.components.Component
% stimgen.components.NoiseSource
% Band-limited Gaussian noise with a modulatable amplitude.
%
% Ports the designfilt construction from stimgen.Noise, with two changes:
%   - the digitalFilter is cached on (HighPass, LowPass, FilterOrder, Fs), so a
%     variant sweep over band edges does not redesign the filter on every
%     render the way stimgen.Noise does;
%   - Seed makes a token reproducible, which stimgen.Noise has no way to do.
%
% Filtering uses filter() rather than filtfilt(), matching stimgen.Noise, so
% the token carries the FIR's FilterOrder/2 group delay.
%
% Parameters:
%   HighPass, LowPass - passband edges in Hz
%   FilterOrder       - FIR order
%   Amplitude         - linear gain (modulatable)
%   Seed              - 0 for a fresh token each render, or a fixed RNG seed

    properties (Constant)
        Kind        = "NoiseSource";
        Description = "Band-limited Gaussian noise with modulatable amplitude";
    end

    properties (Access = private)
        filterCache_ = struct('key', {{}}, 'filt', {{}});
    end

    properties (Constant, Access = private)
        MaxCachedFilters = 8;
    end

    methods

        function d = param_defs(~)
            pd = @stimgen.components.Component.pdef;
            d = struct();
            d.HighPass = pd('High Pass (Hz)', 500, 'format','%.1f Hz', ...
                'limits',[1 1e6], 'order',10);
            d.LowPass = pd('Low Pass (Hz)', 20000, 'format','%.1f Hz', ...
                'limits',[1 1e6], 'order',20);
            d.FilterOrder = pd('Filter Order', 40, 'format','%d', ...
                'limits',[2 4096], 'order',30);
            d.Amplitude = pd('Amplitude', 1, 'format','%.3f', ...
                'modulatable',true, 'order',40, ...
                'doc','Linear gain. Modulate this for AM or ramped/damped noise.');
            d.Seed = pd('Seed (0 = random)', 0, 'format','%d', ...
                'limits',[0 2^31-1], 'order',50, ...
                'doc','Fixed seed reproduces the same noise token every render.');
        end

        function y = render(obj, ctx, p)
            N    = ctx.N;
            hp   = double(p.HighPass);
            lp   = double(p.LowPass);
            ord  = round(double(p.FilterOrder));
            seed = round(double(p.Seed));

            if lp <= hp
                error('stimgen:components:NoiseSource:InvalidBand', ...
                    'Low pass (%.1f Hz) must be above high pass (%.1f Hz).', lp, hp);
            end
            if lp >= ctx.Fs/2
                error('stimgen:components:NoiseSource:InvalidBand', ...
                    'Low pass (%.1f Hz) must be below Nyquist (%.1f Hz).', lp, ctx.Fs/2);
            end

            if seed > 0
                y = randn(RandStream('twister', 'Seed', seed), 1, N);
            else
                y = randn(1, N);
            end

            y = filter(obj.filter_for_(hp, lp, ord, ctx.Fs), y);
            y = obj.fit(y .* obj.expand(p.Amplitude, N), N);
        end

    end % methods

    methods (Access = private)

        function Hd = filter_for_(obj, hp, lp, ord, fs)
            % Hd = filter_for_(obj, hp, lp, ord, fs)
            % Cached designfilt lookup. designfilt is expensive relative to the
            % filtering itself, and a variant sweep re-renders constantly.
            key = sprintf('%.6f|%.6f|%d|%.6f', hp, lp, ord, fs);
            idx = find(strcmp(obj.filterCache_.key, key), 1);
            if ~isempty(idx)
                Hd = obj.filterCache_.filt{idx};
                return
            end

            Hd = designfilt('bandpassfir', ...
                'FilterOrder',      ord, ...
                'CutoffFrequency1', hp, ...
                'CutoffFrequency2', lp, ...
                'SampleRate',       fs);

            obj.filterCache_.key{end+1}  = key;
            obj.filterCache_.filt{end+1} = Hd;
            if numel(obj.filterCache_.key) > obj.MaxCachedFilters
                obj.filterCache_.key(1)  = [];
                obj.filterCache_.filt(1) = [];
            end
        end

    end % methods (Access = private)

end
