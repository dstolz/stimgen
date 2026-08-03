classdef PatchEditor < handle
% stimgen.PatchEditor(patchObj)
% Drag-and-drop editor for a stimgen.Patch signal graph.
%
% Class guide: documentation/stimgen_PatchEditor.md
%
% Nodes are boxes with one labelled input port per modulatable parameter and
% one output port. Drag from an output port to an input port to create a
% connection; drag to the OUT terminal to choose which node's signal becomes
% the stimulus. Select a node or a wire to edit it in the inspector on the
% right, and watch the result in the preview underneath.
%
% Edits apply to the patch immediately. "Revert" restores the graph and every
% parameter value captured when the window opened.
%
% The window is MODAL. StimPlayer rebuilds its whole parameter panel after a
% propMeta button action (@StimPlayer/on_bank_selection_changed.m,
% run_action_), and the new node set has to exist by the time it does.
%
% Example:
%   p = stimgen.Patch.preset("AMTone");
%   stimgen.PatchEditor(p);       % or press "Edit Graph..." in StimPlayer

    properties (SetAccess = private)
        Patch                  % the stimgen.Patch being edited
    end

    properties (Access = private)
        fig
        ax                     % canvas axes, data coordinates 0..1
        h = struct();          % named UI handles
        geom = struct([]);     % per-node geometry from node_geometry_
        gfx  = struct();       % handles of drawn canvas primitives

        % Selection is either a node or a connection, never both.
        selKind = "";          % "" | "node" | "conn"
        selIdx  = 0;

        % Drag state machine: "idle" | "node" | "wire"
        dragMode  = "idle";
        dragIdx   = 0;
        dragOff   = [0 0];
        dragPos   = [0 0];
        dragPoint = [0 0];

        snapshot = struct();   % graph + values captured at open, for Revert
        closing (1,1) logical = false;
    end

    properties (Constant)
        % Canvas layout, in axes data units. Public because the geometry and
        % hit-test statics are, and because they define the drawing contract.
        NODE_W   = 0.185;   % node box width
        HEAD_H   = 0.052;   % header band height
        PORT_H   = 0.040;   % height of one input-port row
        OUT_X    = 0.955;   % x of the OUT terminal
        PORT_R   = 0.010;   % port marker radius
    end

    methods

        function obj = PatchEditor(patchObj, modal)
            % obj = stimgen.PatchEditor(patchObj)
            % obj = stimgen.PatchEditor(patchObj, false)
            %
            % modal defaults to true. Patch.edit_graph needs the modal form,
            % because StimPlayer rebuilds its parameter panel as soon as the
            % button action returns. Pass false to keep the editor open
            % alongside other windows, or to drive it from a script.
            if nargin < 1 || ~isa(patchObj, 'stimgen.Patch')
                error('stimgen:PatchEditor:InvalidInput', ...
                    'stimgen.PatchEditor requires a stimgen.Patch object.');
            end
            if nargin < 2
                modal = true;
            end

            obj.Patch = patchObj;

            obj.snapshot = obj.capture_();
            obj.build_ui_();

            % Start with the output node selected, so the inspector and the
            % preview show something useful rather than an empty pane.
            if ~isempty(obj.Patch.Graph.Nodes)
                i = find(obj.Patch.node_labels() == obj.Patch.OutputNode, 1);
                if isempty(i), i = 1; end
                obj.selKind = "node";
                obj.selIdx  = i;
            end

            obj.refresh_all_();

            if modal
                uiwait(obj.fig);
            end
        end

        function f = figure_handle(obj)
            % f = figure_handle(obj) - The editor's uifigure.
            f = obj.fig;
        end

        function close(obj)
            % close(obj) - Close the editor programmatically.
            obj.close_request_();
        end

        function select_node(obj, label)
            % select_node(obj, label)
            % Select a node, showing it in the inspector and the preview.
            i = find(obj.Patch.node_labels() == string(label), 1);
            if isempty(i)
                error('stimgen:PatchEditor:UnknownNode', ...
                    'No node labelled "%s" in this patch.', string(label));
            end
            obj.selKind = "node";
            obj.selIdx  = i;
            obj.refresh_all_();
        end

    end % methods

    % --- Private external method declarations ---
    methods (Access = private)
        build_ui_(obj)                          % Construct the window
        refresh_all_(obj)                       % Geometry, canvas, inspector, preview
        redraw_canvas_(obj)                     % Draw nodes, wires and the OUT terminal
        hit = hit_test_(obj, pt)                % What is under a canvas point
        on_mouse_down_(obj, src, event)         % Begin a drag or change selection
        on_mouse_move_(obj, src, event)         % Track an in-progress drag
        on_mouse_up_(obj, src, event)           % Commit a drag
        on_key_(obj, src, event)                % Delete key removes the selection
        close_request_(obj)                     % Close and release the modal wait
        build_inspector_(obj)                   % Parameter editor for the selection
        update_preview_(obj)                    % Plot the selected node's output
        add_node_ui_(obj)                       % Palette "Add" button
        delete_selection_(obj)                  % Remove selected node or wire
        auto_layout_(obj)                       % Arrange nodes by graph depth
        apply_preset_(obj, name)                % Replace the graph with a preset
        revert_(obj)                            % Restore the opening snapshot
        s = capture_(obj)                       % Snapshot graph and parameter values
        restore_(obj, s)                        % Apply a snapshot
        set_status_(obj, msg, kind)             % Status line at the bottom
        p = canvas_point_(obj)                  % Current pointer position in canvas units
    end

    % --- Pure layout helpers ---
    % Static and free of editor state, so the canvas layout and hit testing
    % can be verified without opening a window.
    methods (Static)
        g = node_geometry_for_(patchObj, dragIdx, dragPos) % Box and port positions
        hit = hit_test_at_(geom, graph, pt)                % What is under a canvas point
        [x, y] = wire_path_(p1, p2)                        % Connection wire polyline
    end

end
