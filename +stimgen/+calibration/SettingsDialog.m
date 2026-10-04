classdef SettingsDialog < handle
    % d = stimgen.calibration.SettingsDialog(title, size, offset, rowHeights, buildFcn, syncFcn)
    % One of CalibrationGui's Options windows: opened on demand (raised if
    % it is already open), filled by its owner, kept in step with the engine
    % by its owner, and gone when its owner is.
    %
    % CalibrationGui's three settings windows (Hardware and Analysis,
    % Conduction Delay, Excitation) each repeated the same trio -- open or
    % refocus and build a modal figure with a two-column grid and a Close
    % row, sync its fields from the engine, delete it on close -- with only
    % the rows differing. The trio lives here; the owner supplies the rows
    % (buildFcn) and how to read them back from the engine (syncFcn).
    %
    % Modal does not make the fields pending. They apply as they are
    % committed (each field's ValueChangedFcn, set by buildFcn), because the
    % engine, not the window, is what a sweep reads: a value has to be in the
    % engine whether the operator closed the window or MATLAB did. The cost
    % of modality is that a measurement cannot be started or watched from
    % behind one, which is why the delay window's instruction says to close
    % it first.
    %
    % Parameters:
    %   title      - window name
    %   size       - [width height] in pixels
    %   offset     - [dx dy]: the window's left edge sits dx right of the
    %                parent's, its bottom edge dy below the parent's top
    %   rowHeights - grid RowHeight; the LAST row holds the Close button
    %   buildFcn   - @(grid) creating the field rows (all but the last)
    %   syncFcn    - @() writing the engine's values into the open fields

    properties (SetAccess = private)
        Title      (1,1) string
        Size       (1,2) double
        Offset     (1,2) double
        RowHeights cell
        Figure     = []   % the open uifigure, or [] / a deleted handle
    end

    properties (Access = private)
        BuildFcn
        SyncFcn
    end

    methods
        function obj = SettingsDialog(title, size, offset, rowHeights, buildFcn, syncFcn)
            obj.Title      = title;
            obj.Size       = size;
            obj.Offset     = offset;
            obj.RowHeights = rowHeights;
            obj.BuildFcn   = buildFcn;
            obj.SyncFcn    = syncFcn;
        end

        function open(obj, parent)
            % open(obj, parent) - Show the window over parent, or raise it.
            if obj.isOpen()
                figure(obj.Figure);
                return
            end

            pos = parent.Position;
            obj.Figure = uifigure(Name=obj.Title, Resize='off', WindowStyle='modal', ...
                Position=[pos(1) + obj.Offset(1), pos(2) + pos(4) - obj.Offset(2), obj.Size]);

            n = numel(obj.RowHeights);
            g = uigridlayout(obj.Figure, [n 2]);
            g.RowHeight = obj.RowHeights;
            % Same split as the controls column's sections: captions carry
            % the units, the fields hold a few digits.
            g.ColumnWidth = {'1.3x', '1x'};
            g.Padding = [8 8 8 8];
            g.RowSpacing = 4;
            g.ColumnSpacing = 8;

            obj.BuildFcn(g);
            obj.add_close_row_(g, n);
            obj.sync();
        end

        function tf = isOpen(obj)
            % tf = isOpen(obj) - True while the window is on screen.
            tf = ~isempty(obj.Figure) && isvalid(obj.Figure);
        end

        function sync(obj)
            % sync(obj) - Rewrite the open fields from the engine. Called
            % wherever the engine may have changed under the window --
            % construction, load, engine swap. A no-op when closed.
            if obj.isOpen()
                obj.SyncFcn();
            end
        end

        function close(obj)
            % close(obj) - Take the window down if it is up.
            if obj.isOpen()
                delete(obj.Figure);
            end
            obj.Figure = [];
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Access = private)
        function add_close_row_(obj, g, row)
            % Dismiss button, in the field column so it lines up under the
            % fields instead of stretching the width of the window. It only
            % closes: every field reaches the engine as it is committed, so
            % there is nothing pending to confirm and nothing staged to
            % cancel. It exists because a window with no button at all reads
            % as unfinished -- an operator looks for the one that makes the
            % typed value count -- and because these windows are modal, which
            % makes dismissing one the way back to the rest of the GUI.
            fig = obj.Figure;
            btn = uibutton(g, Text='Close', ButtonPushedFcn=@(~,~) delete(fig));
            btn.Layout.Row = row;
            btn.Layout.Column = 2;
            btn.Tooltip = stimgen.util.tooltip('CalibrationGui', 'SettingsClose');

            % Escape does the same, which is what a window carrying a single
            % dismiss button invites. Not Return: these windows are numeric
            % edit fields, where Return commits the field being typed in.
            fig.WindowKeyPressFcn = @(~,evt) close_on_escape_(fig, evt);
        end
    end
end


function close_on_escape_(fig, evt)
if strcmp(evt.Key, 'escape')
    delete(fig)
end
end
