classdef Patch < stimgen.StimType & dynamicprops
% obj = stimgen.Patch
% Stimulus whose signal chain is a user-editable graph of components.
%
% Package guide: documentation/stimgen_overview.md
% Class guide: documentation/stimgen_Patch.md
%
% Every other stimulus class in this package hardcodes one recipe. A Patch
% instead holds a set of stimgen.components nodes and a set of connections,
% where a connection routes one node's output into another node's PARAMETER.
% That single mechanism covers the usual families:
%
%   modulator -> carrier Amplitude   = AM tone / AM noise / tremolo
%   modulator -> carrier Frequency   = FM tone / vibrato
%   pulse train -> carrier Amplitude = pulsed tone / gated noise
%   envelope -> noise Amplitude      = ramped or damped noise
%   several sources -> Mixer inputs  = two-tone complexes, noise plus tone
%
% Example:
%   p = stimgen.Patch;
%   p.add_node("LFO1", "Oscillator", Frequency = 10);
%   p.add_connection("LFO1", "Osc1", "Amplitude", Mode = "AM", Depth = 1);
%   p.update_signal; p.plot
%
% or start from a preset:
%   p = stimgen.Patch.preset("PulsedTone");
%
% HOW THE GRAPH REACHES THE REST OF THE TOOLBOX
% Each component parameter is exposed on the Patch as a dynamic property named
% <NodeLabel>_<ParamName>, e.g. Osc1_Frequency. Everything in stimgen that
% walks properties -- the variant expander, toStruct/fromStruct, both GUI
% generators, the expression evaluator, StimInspector -- addresses properties
% by name through isprop and dynamic field access, all of which accept dynamic
% properties. So a graph parameter is a first-class stimulus parameter for
% free: it can be vectorized into variants
%
%   p.Osc1_Frequency = [1000 2000 4000];   % crossed with any other vector
%
% it round-trips through .spl banks, and it can be typed as an expression that
% references its siblings. The underscore separator is deliberate: it keeps the
% name a legal MATLAB identifier and a legal struct fieldname, and it avoids
% StimType.rewrite_qualified_property_refs_, which would strip a dotted prefix.
%
% Graph holds topology only -- labels, kinds, canvas positions and
% connections. Parameter VALUES live solely in the dynamic properties, so
% there is no second copy to keep in sync. Graph is listed first in
% UserProperties because all three restore paths (StimType.fromStruct,
% StimPlayer.load_bank, and the Patch constructor) assign in UserProperties
% order, and the nodes must exist before their parameters can be written.

    properties (SetObservable, AbortSet)
        % Topology only. Assigning this rebuilds the component objects and the
        % dynamic parameter properties, preserving the values of any parameter
        % that still exists afterwards.
        Graph (1,1) struct = stimgen.Patch.empty_graph();

        % Label of the node whose output becomes Signal.
        OutputNode (1,1) string = "";

        % Calibration and level policy. CalibrationType is an Abstract Constant
        % on StimType and so cannot vary per instance; a patch can contain
        % anything, so it declares "filter" and overrides apply_calibration to
        % offer a per-instance choice, the same way stimgen.SoundFile does.
        CalibrationMode (1,1) string ...
            {mustBeMember(CalibrationMode,["Filtered","Tone","None"])} = "Filtered"
        AnchorFrequency (1,1) double {mustBeNonnegative,mustBeFinite} = 0
        LevelReference  (1,1) string ...
            {mustBeMember(LevelReference,["absmax","rms","peak"])} = "absmax"
    end

    properties (Constant)
        IsMultiObj      = false;
        CalibrationType = "filter";
        Normalization   = "absmax";   % overridden per instance by LevelReference
    end

    properties (Access = private)
        components_      = {};                 % 1-by-N cell, parallel to Graph.Nodes
        componentLabels_ = string.empty(1,0);  % label each components_ entry is held under
        paramProps_     = string.empty(1,0);  % dynamic property names we own
        paramListeners_ = {};                 % parallel PostSet listeners
        rebuilding_     (1,1) logical = false;
        lastOutputs_    = {};                 % per-node waveform from the last render
    end

    methods

        function obj = Patch(varargin)
            obj = obj@stimgen.StimType(varargin{:});

            obj.DisplayName = 'Patch';

            % A bare Patch is a plain 1 kHz tone: something audible and
            % plottable exists the moment StimPlayer adds one to a bank.
            g = stimgen.Patch.empty_graph();
            g.Nodes(1) = struct('Label',"Osc1", 'Kind',"Oscillator", 'Position',[0.20 0.50]);
            obj.Graph      = g;
            obj.OutputNode = "Osc1";
        end

        function set.Graph(obj, g)
            g = stimgen.Patch.validate_graph_(g);
            % Dragging a node on the canvas changes Position but not topology.
            % Skip the parameter rebuild in that case: adding and deleting
            % dynamic properties is the expensive part, and it would also
            % churn UserProperties for a purely cosmetic change.
            same = stimgen.Patch.topology_signature_(obj.Graph) == ...
                   stimgen.Patch.topology_signature_(g);
            obj.Graph = g;
            if ~same
                obj.rebuild_params_();
            end
        end

        function set.OutputNode(obj, label)
            label = string(label);
            if strlength(label) > 0 && ~any(obj.node_labels() == label)
                error('stimgen:Patch:UnknownNode', ...
                    'No node labelled "%s" in this patch.', label);
            end
            obj.OutputNode = label;
        end

        function labels = node_labels(obj)
            % labels = node_labels(obj) - String array of node labels, in graph order.
            if isempty(obj.Graph.Nodes)
                labels = string.empty(1,0);
            else
                labels = string({obj.Graph.Nodes.Label});
            end
        end

        function c = component(obj, label)
            % c = component(obj, label) - The component object for a node label.
            i = obj.node_index_(label);
            c = obj.components_{i};
        end

        function y = node_output(obj, label)
            % y = node_output(obj, label)
            % Waveform produced by one node during the most recent render.
            % Used by the patch editor to preview an intermediate signal.
            if isempty(obj.lastOutputs_)
                obj.update_signal();
            end
            y = obj.lastOutputs_{obj.node_index_(label)};
        end

    end % methods (inline)

    % --- Public external method declarations ---
    methods
        add_node(obj, label, kind, varargin)                  % Add a component node
        remove_node(obj, label)                               % Remove a node and its connections
        add_connection(obj, from, to, param, varargin)        % Route a node into a parameter
        remove_connection(obj, from, to, param)               % Remove one connection
        set_node_position(obj, label, pos)                    % Move a node on the editor canvas
        rename_node(obj, oldLabel, newLabel)                  % Rename a node, preserving values
        edit_graph(obj)                                       % propMeta button: open the patch editor
        update_signal(obj)                                    % Render the graph into Signal
        text = current_parameter_summary(obj)                 % Non-default parameter summary
    end

    % --- Protected external method declarations ---
    methods (Access = protected)
        m = propMeta(obj)                                     % GUI metadata, one section per node
        apply_calibration(obj)                                % Per-instance calibration mode
        apply_normalization(obj)                              % Per-instance level reference
        rebuild_params_(obj)                                  % Sync dynamic props to the graph
        p = resolve_params_(obj, idx, ctx, outputs, resolved) % Base values plus inbound modulation
        order = topo_order_(obj)                              % Evaluation order; detects cycles
        i = node_index_(obj, label)                           % Index of a node label
        value = anchor_frequency_(obj, y, fs)                 % LUT key for calibration mode "Tone"
        cp = copyElement(obj)                                 % Deep copy components and dyn props
    end

    % --- Static ---
    methods (Static)
        obj = preset(name)                                    % Build a named example patch
        names = preset_names()                                % Available preset names
        g = empty_graph()                                     % Empty topology struct
        [modes, descriptions] = mode_names()                  % Connection modes and their math
        name = flat_name_(label, param)                       % <Label>_<Param>
        g = validate_graph_(g)                                % Normalize and check a topology
        s = topology_signature_(g)                            % Graph identity ignoring positions
        order = topo_order_for_(g)                            % Evaluation order for a raw graph
        v = apply_mode_(mode, base, m, range, depth, powerComp) % One connection's parameter math
    end

end
