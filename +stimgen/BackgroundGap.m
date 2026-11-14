classdef BackgroundGap < stimgen.BackgroundModulation

    % obj = stimgen.BackgroundGap(Name,Value,...)
    % A gap IN AN ONGOING BACKGROUND: its level drops for Duration seconds.
    %
    % Class guide: documentation/stimgen_Background.md
    %
    % The background (base-class Background, by default band-passed noise) is
    % steady; for this stimulus's Duration its gain is
    %
    %   G(t) = 1 - GapDepth * w(t)
    %
    % GapDepth = 1 is silence; a smaller depth is a level decrement of
    % 20*log10(1 - GapDepth) dB. w is the gate: WindowDuration is the fall
    % plus the rise (each ramp half of it), inside Duration and not added to
    % it, and Apply Window off makes the gap rectangular.
    %
    % Example:
    %   gap = stimgen.BackgroundGap('Duration', [0.002 0.005 0.01 0.02 0.05], ...
    %       'WindowDuration', 0.001, 'SoundLevel', 60);

    properties (SetObservable,AbortSet)
        GapDepth (1,:) double {mustBeGreaterThanOrEqual(GapDepth,0),mustBeLessThanOrEqual(GapDepth,1)} = 1; % [0 1]
    end

    methods

        function obj = BackgroundGap(varargin)
            % Defaults first, caller's pairs last, so a caller's value wins.
            obj = obj@stimgen.BackgroundModulation( ...
                'DisplayName', 'Background Gap', ...
                'UserProperties', ["SoundLevel","Duration","WindowDuration","ApplyWindow","GapDepth"], ...
                'Duration', 0.02, ...
                varargin{:});
        end

    end

    methods (Access = protected)

        function [g, phi] = modulation_(obj, ~, w)
            depth = double(obj.selected_value("GapDepth"));
            g   = 1 - depth .* w;
            phi = [];
        end

        function m = propMeta(obj)
            % propMeta() - Display metadata for BackgroundGap GUI properties.
            m = struct();
            m.GapDepth = struct('label', 'Gap Depth (0-1)', 'format', '%.2f', 'limits', [0 1], ...
                'tooltip', stimgen.util.tooltip(obj, 'GapDepth'));
            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.BackgroundModulation(obj));
        end

    end

end
