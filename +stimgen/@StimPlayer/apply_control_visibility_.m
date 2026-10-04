function apply_control_visibility_(obj)
% apply_control_visibility_() - Push ControlVisibility onto the GUI.
% Hidden widgets are made invisible and their grid row/column is
% collapsed to zero so no empty space is left behind.

h   = obj.handles;
vis = obj.ControlVisibility;

% Bank panel rows: {visibility field, widgets, row index field}
rows = { ...
    'Reps',       {'RepsLabel','RepsField'},     'RepsRow'; ...
    'ISI',        {'ISILabel','ISIField'},       'ISIRow'; ...
    'SampleRate', {'FsLabel','FsField'},         'FsRow'; ...
    'PlayMode',   {'OrderDD'},                   'OrderRow'; ...
    'Output',     {'OutputLabel','OutputDD'},    'OutputRow'};

if isfield(h,'BankGrid') && ~isempty(h.BankGrid) && isvalid(h.BankGrid)
    heights = h.BankGrid.RowHeight;
    for i = 1:size(rows,1)
        show = vis.(rows{i,1});
        obj.set_widgets_visible_(rows{i,2}, show);
        if ~isfield(h, rows{i,3}), continue; end
        r = h.(rows{i,3});
        if show
            heights{r} = h.BankGridRowHeight{r};
        else
            heights{r} = 0;
        end
    end
    h.BankGrid.RowHeight = heights;
end

% Playback bar columns: {visibility field, widget, column index field}
cols = { ...
    'Run',   'RunBtn',   'RunCol'; ...
    'Pause', 'PauseBtn', 'PauseCol'};

if isfield(h,'ControlGrid') && ~isempty(h.ControlGrid) && isvalid(h.ControlGrid)
    widths = h.ControlGrid.ColumnWidth;
    for i = 1:size(cols,1)
        show = vis.(cols{i,1});
        obj.set_widgets_visible_(cols(i,2), show);
        if ~isfield(h, cols{i,3}), continue; end
        c = h.(cols{i,3});
        if show
            widths{c} = h.ControlGridColumnWidth{c};
        else
            widths{c} = 0;
        end
    end
    h.ControlGrid.ColumnWidth = widths;
end

% The Bank menu's Run/Stop item (and F5, which checks the same
% flag) belongs to whoever owns the Run button.
obj.set_widgets_visible_({'RunMenu'}, vis.Run);
end
