classdef FileSource < stimgen.components.Component
% stimgen.components.FileSource
% Plays a waveform read from an audio file (or an embedded buffer).
%
% Shares the catalog shape and the LRU waveform cache of stimgen.SoundFile, and
% reads through the same stimgen.util.read_audio helper, but differs in one
% important way: it does NOT slave the patch Duration to the selected file.
% A patch has one global timebase, so the file is truncated or zero-padded to
% it. That is what lets a file be mixed with, gated by, or modulated against
% synthesized sources.
%
% Catalog is a scalar struct of parallel arrays, deliberately matching
% stimgen.SoundFile.Catalog so the two can share tooling:
%   Label, Path, SourceFs, NativeSamples, NChannels, Embedded, Data
%
% Parameters:
%   Catalog   - the file catalog (edited in the patch editor, not the panel)
%   FileIndex - 1-based index into the catalog (vectorizable -> variants)
%   Channel   - 0 to mix all channels to mono, else a 1-based channel index
%   Amplitude - linear gain (modulatable)

    properties (Constant)
        Kind        = "FileSource";
        Description = "Waveform read from an audio file, fitted to the patch timebase";
    end

    properties (Access = private)
        waveformCache_ = struct('key', {{}}, 'data', {{}});
    end

    properties (Constant, Access = private)
        MaxCachedWaveforms = 32;
    end

    methods

        function d = param_defs(~)
            pd = @stimgen.components.Component.pdef;
            d = struct();
            % Catalog carries no widget: it is a struct, and the panel has no
            % way to edit one. Browsing happens in the patch editor's node
            % inspector, which knows which node it is acting on. (A propMeta
            % 'button' callback is a bare no-argument method name, so the
            % StimPlayer panel could not tell one FileSource from another.)
            d.Catalog = pd('Catalog', stimgen.components.FileSource.empty_catalog(), ...
                'widget','none', 'order',5);
            d.FileIndex = pd('File Index', 1, 'format','%d', ...
                'limits',[1 1e6], 'order',10, ...
                'doc','Vectorize this (e.g. 1:8) to sweep files across variants.');
            d.Channel = pd('Channel (0 = mix)', 0, 'format','%d', ...
                'limits',[0 64], 'order',20);
            d.Amplitude = pd('Amplitude', 1, 'format','%.3f', ...
                'modulatable',true, 'order',30);
        end

        function y = render(obj, ctx, p)
            N   = ctx.N;
            cat = p.Catalog;

            if ~isstruct(cat) || ~isfield(cat, 'Path') || isempty(cat.Path)
                % An empty catalog is normal right after a node is added, and
                % the patch still has to produce a signal for the panel plot.
                y = zeros(1, N);
                return
            end

            i = round(double(p.FileIndex));
            if i < 1 || i > numel(cat.Path)
                error('stimgen:components:FileSource:IndexOutOfRange', ...
                    'File index %d is outside the catalog (%d file(s)).', i, numel(cat.Path));
            end

            y = obj.load_waveform_(cat, i, round(double(p.Channel)), ctx.Fs);
            y = obj.fit(y, N);
            y = obj.fit(y .* obj.expand(p.Amplitude, N), N);
        end

        function clear_cache(obj)
            % clear_cache(obj) - Drop cached waveforms after a catalog edit.
            obj.waveformCache_ = struct('key', {{}}, 'data', {{}});
        end

    end % methods

    methods (Access = private)

        function y = load_waveform_(obj, cat, i, ch, fs)
            % Cache key includes the file's modification date so an edited file
            % on disk is re-read rather than served stale.
            if cat.Embedded(i)
                key = sprintf('embedded|%d|%d|%.6f', i, ch, fs);
            else
                d = dir(cat.Path{i});
                if isempty(d)
                    error('stimgen:components:FileSource:FileNotFound', ...
                        'Audio file not found: %s', cat.Path{i});
                end
                key = sprintf('%s|%.10f|%d|%.6f', cat.Path{i}, d.datenum, ch, fs);
            end

            idx = find(strcmp(obj.waveformCache_.key, key), 1);
            if ~isempty(idx)
                y = obj.waveformCache_.data{idx};
                return
            end

            if cat.Embedded(i)
                y = stimgen.util.read_audio(cat.Data{i}, ch, fs, cat.SourceFs(i));
            else
                y = stimgen.util.read_audio(cat.Path{i}, ch, fs);
            end

            obj.waveformCache_.key{end+1}  = key;
            obj.waveformCache_.data{end+1} = y;
            if numel(obj.waveformCache_.key) > obj.MaxCachedWaveforms
                obj.waveformCache_.key(1)  = [];
                obj.waveformCache_.data(1) = [];
            end
        end

    end % methods (Access = private)

    methods (Static)

        function c = empty_catalog()
            % c = stimgen.components.FileSource.empty_catalog()
            % An empty catalog with the canonical field set.
            c = struct('Label', {{}}, 'Path', {{}}, 'SourceFs', [], ...
                       'NativeSamples', [], 'NChannels', [], ...
                       'Embedded', logical([]), 'Data', {{}});
        end

    end % methods (Static)

end
