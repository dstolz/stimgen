classdef Component < handle & matlab.mixin.Heterogeneous & matlab.mixin.Copyable
% stimgen.components.Component
% Abstract base for the building blocks of a stimgen.Patch signal graph.
%
% Package guide: documentation/stimgen_Patch.md
%
% A component is a pure generator: given a timebase and a set of resolved
% parameter values it returns a waveform. It holds no signal state between
% renders, owns no GUI, and knows nothing about calibration, gating, levels or
% variants -- all of that stays in stimgen.StimType, exactly as it does for the
% monolithic stimulus classes.
%
% Subclasses implement:
%   Kind        - (Constant) short type name, e.g. "Oscillator"
%   Description - (Constant) one-line summary shown in the editor palette
%   param_defs  - struct of parameter descriptors (see pdef below)
%   render      - y = render(obj, ctx, p), returns exactly 1-by-ctx.N
%
% and may override:
%   nominal_range - the declared output range, used when this component drives
%                   another component's parameter. Default [-1 1].
%
% THE TIMEBASE CONTRACT
% ctx is a struct with fields Fs, N and t. Every render() must return a
% 1-by-ctx.N row vector: there is one global timebase per patch and nodes
% truncate or zero-pad to it. This is deliberately stricter than the monolithic
% classes, which each reconcile length ad hoc (compare AttackModNoise, which
% pads to obj.N after tiling, with ClickTrain, which does the same thing
% differently).
%
% THE PARAMETER CONTRACT
% p is a struct with one field per declared parameter. Each value is either a
% scalar or a 1-by-N row vector -- a parameter that some other node modulates
% arrives as a full-length vector. Use obj.expand(value, N) to normalize.
% Non-numeric parameters (dropdowns, catalogs) are always passed through
% unmodulated, as scalars.

    properties (Abstract, Constant)
        Kind        % (1,1) string - short type name used in Graph.Nodes.Kind
        Description % (1,1) string - one-line summary for the editor palette
    end

    methods (Abstract)
        d = param_defs(obj)     % struct: ParamName -> descriptor
        y = render(obj, ctx, p) % 1-by-ctx.N row vector
    end

    methods

        function r = nominal_range(~, ~)
            % r = nominal_range(obj, p)
            % Declared output range [lo hi] for this component under resolved
            % parameters p. The Patch uses it to map this node's output to
            % unipolar [0 1] or bipolar [-1 1] before applying a connection,
            % so the mapping is declared rather than measured from the data.
            r = [-1 1];
        end

        function d = defaults(obj)
            % d = defaults(obj)
            % Struct of parameter name -> default value.
            defs  = obj.param_defs();
            names = fieldnames(defs);
            d     = struct();
            for k = 1:numel(names)
                d.(names{k}) = defs.(names{k}).default;
            end
        end

        function tf = is_modulatable(obj, paramName)
            % tf = is_modulatable(obj, paramName)
            % True when paramName accepts an inbound connection.
            defs = obj.param_defs();
            tf = isfield(defs, char(paramName)) && defs.(char(paramName)).modulatable;
        end

        function names = modulatable_params(obj)
            % names = modulatable_params(obj)
            % String array of parameters that accept an inbound connection,
            % in declaration order. These become the input ports drawn on the
            % node in the patch editor.
            defs  = obj.param_defs();
            fn    = fieldnames(defs);
            keep  = cellfun(@(n) defs.(n).modulatable, fn);
            names = string(fn(keep))';
        end

    end % methods

    methods (Access = protected)

        function v = expand(~, value, N)
            % v = expand(obj, value, N)
            % Normalize a resolved parameter to a 1-by-N row vector.
            v = double(value);
            if isscalar(v)
                v = repmat(v, 1, N);
            else
                v = reshape(v, 1, []);
                if numel(v) ~= N
                    error('stimgen:components:Component:BadParamLength', ...
                        'Modulated parameter has %d samples but the timebase has %d.', ...
                        numel(v), N);
                end
            end
        end

        function y = fit(~, y, N)
            % y = fit(obj, y, N)
            % Truncate or zero-pad y to exactly 1-by-N, enforcing the timebase
            % contract for nodes that build a waveform by tiling.
            y = reshape(y, 1, []);
            if numel(y) > N
                y = y(1:N);
            elseif numel(y) < N
                y(end+1:N) = 0;
            end
        end

    end % methods (Access = protected)

    methods (Static)

        function d = pdef(label, default, varargin)
            % d = stimgen.components.Component.pdef(label, default, Name, Value, ...)
            % Build one parameter descriptor.
            %
            % The optional fields deliberately mirror the propMeta schema
            % (format, limits, scale, widget, items, itemsData, order) so that
            % stimgen.Patch can emit them into propMeta with only a name prefix
            % added -- there is no translation layer to keep in sync.
            %
            % Additional fields:
            %   modulatable - true if this parameter accepts an inbound
            %                 connection (default false)
            %   doc         - one-line description shown as a tooltip
            %
            % 'widget' is always resolved to an explicit value here, because
            % Patch exposes parameters as dynamic properties and dynamic
            % properties never appear in metaclass(obj).PropertyList -- so
            % StimType.resolve_widget_type's class-based fallback cannot see
            % them and would infer 'text' for every numeric parameter.
            ip = inputParser;
            ip.addParameter('format',      '');
            ip.addParameter('limits',      []);
            ip.addParameter('scale',       1);
            ip.addParameter('widget',      '');
            ip.addParameter('items',       string.empty);
            ip.addParameter('itemsData',   {});
            ip.addParameter('order',       inf);
            ip.addParameter('modulatable', false);
            ip.addParameter('doc',         '');
            ip.parse(varargin{:});
            r = ip.Results;

            d = struct();
            d.label       = char(label);
            d.default     = default;
            d.scale       = r.scale;
            d.order       = r.order;
            d.modulatable = logical(r.modulatable);
            d.doc         = char(r.doc);

            if isempty(r.widget)
                if ~isempty(r.items)
                    d.widget = 'dropdown';
                elseif islogical(default)
                    d.widget = 'checkbox';
                elseif isnumeric(default)
                    d.widget = 'numeric';
                else
                    d.widget = 'text';
                end
            else
                d.widget = char(r.widget);
            end

            if ~isempty(r.format),    d.format    = char(r.format); end
            if ~isempty(r.limits),    d.limits    = r.limits;       end

            if ~isempty(r.items)
                % uidropdown accepts only a string array or a cell of char
                % vectors. Checked here because the failure would otherwise
                % surface much later, as an error deep inside whichever GUI
                % first happened to build this particular widget. Note that
                % pdef parses with inputParser, which -- unlike the struct()
                % constructor used by the monolithic classes' propMeta -- does
                % NOT unwrap a cell, so items needs single braces here.
                if ~(isstring(r.items) || (iscell(r.items) && ...
                        all(cellfun(@(x) ischar(x) || isStringScalar(x), r.items))))
                    error('stimgen:components:Component:InvalidItems', ...
                        ['''items'' for "%s" must be a string array or a cell array of ' ...
                         'character vectors. Use single braces: ''items'', {''a'',''b''}.'], ...
                        d.label);
                end
                d.items = r.items;
            end

            if ~isempty(r.itemsData)
                if numel(r.itemsData) ~= numel(r.items)
                    error('stimgen:components:Component:InvalidItems', ...
                        '''itemsData'' for "%s" has %d entries but ''items'' has %d.', ...
                        d.label, numel(r.itemsData), numel(r.items));
                end
                d.itemsData = r.itemsData;
            end
        end

    end % methods (Static)

end
