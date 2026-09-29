classdef CombinationViewer < handle

    % obj = stimgen.CombinationViewer(stimObj)
    % obj = stimgen.CombinationViewer(stimObj, label)
    % Every variant combination of one stimulus, side by side.
    %
    % Developer guide: documentation/stimgen_CombinationViewer.md
    %
    % A stimulus with vectorized properties is a family of waveforms -- a Tone
    % with Frequency = [4000 8000 16000] and SoundLevel = [30 60] is six --
    % and StimPlayer's signal plot shows one of them at a time. This window
    % generates all of them and draws them together, so the family can be
    % compared at a glance: as small multiples (Tiles), on one axes
    % (Overlay), or offset down one axes with each trace named (Stacked),
    % in the time domain or as magnitude spectra. The table on the left lists
    % the combinations with the value of every varying property, the peak
    % and the rms; its Show column chooses which are drawn. Clicking a row or
    % a trace makes that combination current; Inspect (or double-clicking a
    % trace) opens it in a stimgen.StimInspector for the full analysis.
    %
    % THE SOURCE IS NEVER TOUCHED. The combinations are generated on copies
    % of the stimulus, each pinned to its combination with
    % VariantReselectOnUpdate forced off, so the source keeps its active
    % combination, its selection order and its use counts -- opening this
    % window from StimPlayer does not move the bank. The copies are kept, so
    % the waveform Inspect opens is the one on screen. For a noise stimulus
    % each copy is a fresh draw from the same parameters, which is also what
    % the bank would generate the next time round.
    %
    % Refresh regenerates from the same source object, so parameter edits
    % made since the window opened appear; the choice of which combinations
    % are shown is kept when the number of combinations has not changed.
    %
    % Usage:
    %   t = stimgen.Tone('Frequency', [4000 8000 16000], 'SoundLevel', [30 60]);
    %   v = stimgen.CombinationViewer(t, "tone family");
    %   v.View   = "Overlay";
    %   v.Domain = "Spectrum";
    %
    % Properties:
    %   View        - "Tiles" | "Overlay" | "Stacked"
    %   Domain      - "Waveform" | "Spectrum"
    %   SharedScale - true: every trace on one amplitude scale (level
    %                 differences stay visible); false: each on its own
    %   MaxTraces   - most combinations drawn at once (the table lists all)
    %
    % Properties (read-only):
    %   StimObj   - the source stimgen.StimType (never modified)
    %   Label     - display label
    %   Combos    - struct array, one element per combination: Index, Stim
    %               (the pinned copy), Signal, Fs, Values (varying
    %               properties, stored units), Short, Full (descriptions)
    %   PropNames - the varying properties, in table-column order
    %   Current   - index of the current combination (Inspect target)
    %
    % Window settings (view, domain, shared scale, position) persist in the
    % 'CombinationViewer' preference group.
    %
    % See also: stimgen.StimPlayer, stimgen.StimInspector, stimgen.StimType

    properties
        View        (1,1) string {mustBeMember(View, ["Tiles","Overlay","Stacked"])} = "Stacked"
        Domain      (1,1) string {mustBeMember(Domain, ["Waveform","Spectrum"])} = "Waveform"
        SharedScale (1,1) logical = false
        MaxTraces   (1,1) double {mustBeInteger, mustBePositive} = 64
    end

    properties (SetAccess = private)
        StimObj                               % source stimgen.StimType (never modified)
        Label     (1,1) string = ""           % display label
        Combos    (:,1) struct = struct('Index', {}, 'Stim', {}, 'Signal', {}, ...
                      'Fs', {}, 'Values', {}, 'Short', {}, 'Full', {})
        PropNames (1,:) string = strings(1,0) % varying properties, table-column order
        Current   (1,1) double = 1            % current combination (Inspect target)
        Figure                                % uifigure
    end

    properties (Access = private)
        Show_   (:,1) logical = logical.empty(0,1) % per-combination Show flag
        H_      struct = struct()                  % UI handles
        Axes_   = gobjects(0)                      % axes drawn by the last render
        Lines_  = gobjects(0)                      % one line per drawn combination
        Drawn_  (:,1) double = zeros(0,1)          % combination index behind each line
        Built_  (1,1) logical = false
        Inspectors_ = {}                           % StimInspectors opened from here
    end

    properties (Constant, Access = private)
        PrefGroup = 'CombinationViewer'
        PrefName  = 'Settings'
        Accent    = [0.16 0.38 0.58]
        FloorDb   = -100                           % spectrum floor, dB re reference
    end

    % =====================================================================
    methods

        function obj = CombinationViewer(stimObj, label)
            arguments
                stimObj (1,1) stimgen.StimType
                label   (1,1) string = ""
            end

            obj.StimObj = stimObj;
            if strlength(label) == 0
                parts = split(string(class(stimObj)), ".");
                label = parts(end);
            end
            obj.Label = label;

            obj.load_settings_();
            obj.build_ui_();
            obj.Built_ = true;
            obj.refresh();

            if nargout == 0, clear obj; end
        end

        % -----------------------------------------------------------------
        function delete(obj)
            % Close the window and any inspectors opened from it.
            for k = 1:numel(obj.Inspectors_)
                insp = obj.Inspectors_{k};
                if ~isempty(insp) && isvalid(insp)
                    delete(insp);
                end
            end
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                obj.save_settings_();
                obj.Figure.DeleteFcn = '';
                delete(obj.Figure);
            end
        end

        % -----------------------------------------------------------------
        function set.View(obj, value)
            obj.View = value;
            obj.settings_changed_();
        end

        function set.Domain(obj, value)
            obj.Domain = value;
            obj.settings_changed_();
        end

        function set.SharedScale(obj, value)
            obj.SharedScale = value;
            obj.settings_changed_();
        end

        function set.MaxTraces(obj, value)
            obj.MaxTraces = value;
            obj.settings_changed_();
        end

        % -----------------------------------------------------------------
        function refresh(obj)
            % refresh(obj) - Regenerate every combination from the source.
            if ~obj.is_open()
                return
            end
            if isempty(obj.StimObj) || ~isvalid(obj.StimObj)
                obj.set_status_("The source stimulus no longer exists; nothing to regenerate.", true);
                return
            end

            oldShow = obj.Show_;
            try
                obj.generate_();
            catch ME
                obj.set_status_("Could not generate the combinations: " + string(ME.message), true);
                stimgen.util.vprintf(1, 1, ME);
                return
            end

            n = numel(obj.Combos);
            if numel(oldShow) == n
                obj.Show_ = oldShow;
            else
                obj.Show_ = true(n, 1);
            end
            obj.Current = min(max(obj.Current, 1), max(n, 1));

            obj.fill_table_();
            obj.render_();
        end

        % -----------------------------------------------------------------
        function set_shown(obj, idx)
            % set_shown(obj, idx) - Draw exactly the combinations in idx.
            % idx is a vector of combination indices, or a logical mask.
            n = numel(obj.Combos);
            if islogical(idx)
                mask = false(n, 1);
                mask(1:min(n, numel(idx))) = idx(1:min(n, numel(idx)));
            else
                idx  = idx(idx >= 1 & idx <= n);
                mask = false(n, 1);
                mask(round(idx)) = true;
            end
            obj.Show_ = mask;
            obj.fill_table_();
            obj.render_();
        end

        % -----------------------------------------------------------------
        function select(obj, c)
            % select(obj, c) - Make combination c current (highlighted).
            if isempty(obj.Combos), return; end
            obj.Current = min(max(round(c), 1), numel(obj.Combos));
            obj.restyle_();
            obj.set_status_(obj.status_text_(), false);
        end

        % -----------------------------------------------------------------
        function insp = inspect(obj, c)
            % insp = inspect(obj)
            % insp = inspect(obj, c)
            % Open combination c (default: current) in a stimgen.StimInspector.
            insp = [];
            if isempty(obj.Combos), return; end
            if nargin < 2, c = obj.Current; end
            c = min(max(round(c), 1), numel(obj.Combos));
            obj.select(c);

            label = obj.Label + sprintf(" [combo %d/%d]", c, numel(obj.Combos));
            try
                insp = stimgen.StimInspector(obj.Combos(c).Stim, label);
                obj.Inspectors_ = [obj.Inspectors_(cellfun(@(x) ~isempty(x) && isvalid(x), ...
                    obj.Inspectors_)), {insp}];
            catch ME
                obj.set_status_("Could not open the inspector: " + string(ME.message), true);
                stimgen.util.vprintf(1, 1, ME);
            end
            if nargout == 0, clear insp; end
        end

        % -----------------------------------------------------------------
        function show(obj)
            % show(obj) - Bring the window to the foreground.
            if obj.is_open()
                figure(obj.Figure);
            end
        end

        % -----------------------------------------------------------------
        function tf = is_open(obj)
            % tf = is_open(obj) - True while the window exists.
            tf = isvalid(obj) && ~isempty(obj.Figure) && isvalid(obj.Figure);
        end
    end

    % =====================================================================
    methods (Access = private)

        function generate_(obj)
            % Build one pinned copy per combination. The source is copied
            % once and reselection is switched off on that copy, so every
            % further copy inherits the switch and set_variant_index
            % generates exactly the combination asked for.
            src  = obj.StimObj;
            base = copy(src);
            base.VariantReselectOnUpdate = false;

            info  = base.get_variant_info();
            n     = max(1, info.NumCombinations);
            names = string(info.PropertyNames);
            obj.PropNames = names(:).';
            meta  = base.get_prop_meta();

            dlg = [];
            if n > 16
                dlg = uiprogressdlg(obj.Figure, 'Title', 'Generating combinations', ...
                    'Message', sprintf('Generating %d combinations of %s...', n, obj.Label), ...
                    'Cancelable', 'on');
            end
            cleanup = onCleanup(@() close_dialog_(dlg));

            combos = repmat(struct('Index', 0, 'Stim', [], 'Signal', [], 'Fs', NaN, ...
                'Values', struct(), 'Short', "", 'Full', ""), n, 1);
            kept = n;
            for c = 1:n
                if ~isempty(dlg)
                    if dlg.CancelRequested
                        kept = c - 1;
                        break
                    end
                    dlg.Value   = (c - 1) / n;
                    dlg.Message = sprintf('Generating combination %d of %d...', c, n);
                end
                s = copy(base);
                s.set_variant_index(c);
                v = s.active_variant_values();

                combos(c).Index  = c;
                combos(c).Stim   = s;
                combos(c).Signal = double(s.Signal(:));
                combos(c).Fs     = double(s.Fs);
                combos(c).Values = v;
                [combos(c).Short, combos(c).Full] = describe_values_(v, obj.PropNames, meta);
                if strlength(combos(c).Short) == 0
                    combos(c).Short = sprintf("combo %d", c);
                    combos(c).Full  = combos(c).Short;
                end
            end
            obj.Combos = combos(1:kept);
            if kept < n
                stimgen.util.vprintf(1, 'CombinationViewer: generation cancelled after %d of %d combinations.', kept, n);
            end
        end

        % -----------------------------------------------------------------
        function build_ui_(obj)
            tip = @(key) stimgen.util.tooltip('CombinationViewer', key);

            f = uifigure('Name', "Combinations — " + obj.Label, ...
                'Tag', 'stimgen.CombinationViewer', 'Position', obj.initial_position_());
            f.DeleteFcn = @(~,~) delete(obj);
            obj.Figure  = f;

            tb = uitoolbar(f);
            uipushtool(tb, 'Tooltip', tip('RefreshTool'), ...
                'Icon', stimgen.util.toolbar_icon('refresh'), ...
                'ClickedCallback', @(~,~) obj.refresh());
            uipushtool(tb, 'Tooltip', tip('InspectTool'), ...
                'Icon', stimgen.util.toolbar_icon('inspect'), ...
                'ClickedCallback', @(~,~) obj.inspect());

            g = uigridlayout(f, [2 1]);
            g.RowHeight   = {30, '1x'};
            g.ColumnWidth = {'1x'};
            g.Padding     = [6 6 6 6];
            g.RowSpacing  = 4;

            % ---- Control strip -------------------------------------------
            s = uigridlayout(g, [1 9]);
            s.Layout.Row  = 1;
            s.ColumnWidth = {36, 90, 50, 100, 110, 60, 60, 80, '1x'};
            s.Padding     = [0 0 0 0];
            s.ColumnSpacing = 6;

            uilabel(s, 'Text', 'View:', 'HorizontalAlignment', 'right', 'Tooltip', tip('View'));
            obj.H_.View = uidropdown(s, 'Items', {'Tiles','Overlay','Stacked'}, ...
                'Value', char(obj.View), 'Tooltip', tip('View'), ...
                'ValueChangedFcn', @(src,~) set_prop_(obj, 'View', string(src.Value)));

            uilabel(s, 'Text', 'Show:', 'HorizontalAlignment', 'right', 'Tooltip', tip('Domain'));
            obj.H_.Domain = uidropdown(s, 'Items', {'Waveform','Spectrum'}, ...
                'Value', char(obj.Domain), 'Tooltip', tip('Domain'), ...
                'ValueChangedFcn', @(src,~) set_prop_(obj, 'Domain', string(src.Value)));

            obj.H_.Shared = uicheckbox(s, 'Text', 'Shared scale', ...
                'Value', obj.SharedScale, 'Tooltip', tip('SharedScale'), ...
                'ValueChangedFcn', @(src,~) set_prop_(obj, 'SharedScale', src.Value));

            uibutton(s, 'Text', 'All', 'Tooltip', tip('ShowAll'), ...
                'ButtonPushedFcn', @(~,~) obj.set_shown(true(numel(obj.Combos), 1)));
            uibutton(s, 'Text', 'None', 'Tooltip', tip('ShowNone'), ...
                'ButtonPushedFcn', @(~,~) obj.set_shown(false(numel(obj.Combos), 1)));
            uibutton(s, 'Text', 'Inspect', 'FontWeight', 'bold', 'Tooltip', tip('InspectTool'), ...
                'ButtonPushedFcn', @(~,~) obj.inspect());

            obj.H_.Status = uilabel(s, 'Text', '', 'FontColor', [0.35 0.35 0.35], ...
                'Tooltip', tip('Status'));

            % ---- Table + plot --------------------------------------------
            b = uigridlayout(g, [1 2]);
            b.Layout.Row    = 2;
            b.ColumnWidth   = {470, '1x'};
            b.RowHeight     = {'1x'};
            b.Padding       = [0 0 0 0];
            b.ColumnSpacing = 6;

            t = uitable(b, 'RowName', {}, 'Tooltip', tip('Table'), ...
                'CellEditCallback', @(~,evt) obj.on_table_edit_(evt), ...
                'CellSelectionCallback', @(~,evt) obj.on_table_select_(evt));
            t.Layout.Column = 1;
            obj.H_.Table = t;

            p = uipanel(b, 'BorderType', 'none', 'BackgroundColor', 'w');
            p.Layout.Column = 2;
            obj.H_.Plot = p;
        end

        % -----------------------------------------------------------------
        function fill_table_(obj)
            t = obj.H_.Table;
            if ~isvalid(t), return; end
            meta = [];
            if isvalid(obj.StimObj)
                meta = obj.StimObj.get_prop_meta();
            end

            names = obj.PropNames;
            heads = strings(1, numel(names));
            for k = 1:numel(names)
                [heads(k), ~, ~] = describe_prop_(meta, names(k));
            end

            n  = numel(obj.Combos);
            np = numel(names);
            data = cell(n, np + 4);
            for c = 1:n
                C = obj.Combos(c);
                data{c,1} = obj.Show_(c);
                data{c,2} = c;
                for k = 1:np
                    data{c,2+k} = char(value_text_(C.Values, names(k), meta));
                end
                y = C.Signal;
                if isempty(y)
                    data(c, np+3:np+4) = {NaN, NaN};
                else
                    data(c, np+3:np+4) = {max(abs(y)), sqrt(mean(y.^2))};
                end
            end

            % A column whose every value is a plain number is stored as one,
            % so sorting it is numeric ("10" would otherwise sort before "2").
            fmt = repmat({'char'}, 1, np);
            for k = 1:np
                col = str2double(data(:, 2+k));
                if n > 0 && all(isfinite(col))
                    data(:, 2+k) = num2cell(col);
                    fmt{k} = 'shortG';
                end
            end

            t.ColumnName     = [{'Show', '#'}, cellstr(heads), {'Peak', 'RMS'}];
            t.ColumnEditable = [true, false(1, np + 3)];
            t.ColumnSortable = true(1, np + 4);
            t.ColumnFormat   = [{'logical', 'numeric'}, fmt, {'shortG', 'shortG'}];
            widths = num2cell(max(60, round(7.4 * strlength(heads)) + 10));
            t.ColumnWidth    = [{50, 30}, widths, {55, 60}];
            t.Data           = data;
        end

        % -----------------------------------------------------------------
        function render_(obj)
            % Redraw the plot area from scratch for the current settings.
            if ~obj.Built_ || ~obj.is_open(), return; end
            p = obj.H_.Plot;
            delete(p.Children);
            obj.Axes_  = gobjects(0);
            obj.Lines_ = gobjects(0);
            obj.Drawn_ = zeros(0, 1);

            shown = find(obj.Show_);
            capped = numel(shown) > obj.MaxTraces;
            shown  = shown(1:min(end, obj.MaxTraces));
            if isempty(shown)
                uilabel(p, 'Text', 'No combination is selected to show. Tick Show in the table, or press All.', ...
                    'HorizontalAlignment', 'center', 'Position', [10 10 max(p.Position(3) - 20, 50) 40]);
                obj.set_status_(obj.status_text_(), false);
                return
            end

            [X, Y, xLab, yLab, ref] = obj.traces_(shown);
            k  = numel(shown);
            cm = trace_colors_(k);

            switch obj.View
                case "Tiles"
                    nc = ceil(sqrt(k * 4/3));
                    nr = ceil(k / nc);
                    tl = tiledlayout(p, nr, nc, 'TileSpacing', 'compact', 'Padding', 'compact');
                    axs = gobjects(k, 1);
                    for i = 1:k
                        ax = nexttile(tl);
                        obj.Lines_(i) = line(ax, X{i}, Y{i}, 'Color', obj.Accent, 'LineWidth', 0.8);
                        title(ax, obj.Combos(shown(i)).Short, 'FontSize', 8, ...
                            'FontWeight', 'normal', 'Interpreter', 'none');
                        grid(ax, 'on'); box(ax, 'on');
                        ax.FontSize = 7;
                        axs(i) = ax;
                    end
                    xlabel(tl, xLab); ylabel(tl, yLab);
                    obj.apply_limits_(axs, X, Y, ref);
                    obj.Axes_ = axs;

                case "Overlay"
                    tl = tiledlayout(p, 1, 1, 'Padding', 'compact');
                    ax = nexttile(tl);
                    hold(ax, 'on');
                    for i = 1:k
                        obj.Lines_(i) = line(ax, X{i}, Y{i}, 'Color', cm(i,:), 'LineWidth', 0.8, ...
                            'DisplayName', obj.Combos(shown(i)).Short);
                    end
                    hold(ax, 'off');
                    grid(ax, 'on'); box(ax, 'on');
                    xlabel(ax, xLab); ylabel(ax, yLab);
                    if k <= 16
                        % Explicit handles: restyle_ restacks the current
                        % trace, which would otherwise reorder the legend.
                        legend(ax, obj.Lines_, 'Location', 'eastoutside', 'Interpreter', 'none', ...
                            'FontSize', 8, 'Box', 'off', 'AutoUpdate', 'off');
                    end
                    obj.apply_limits_(ax, X, Y, ref);
                    obj.Axes_ = ax;

                case "Stacked"
                    tl = tiledlayout(p, 1, 1, 'Padding', 'compact');
                    ax = nexttile(tl);
                    hold(ax, 'on');
                    offsets = (k:-1:1).';
                    for i = 1:k
                        yn = obj.unit_trace_(Y{i}, ref) + offsets(i);
                        obj.Lines_(i) = line(ax, X{i}, yn, 'Color', cm(i,:), 'LineWidth', 0.8);
                    end
                    hold(ax, 'off');
                    grid(ax, 'on'); box(ax, 'on');
                    labels = arrayfun(@(c) char(obj.Combos(c).Short), shown, 'UniformOutput', false);
                    [ticks, order] = sort(offsets);
                    ax.YTick      = ticks;
                    ax.YTickLabel = labels(order);
                    ax.TickLabelInterpreter = 'none';
                    ylim(ax, [0.4, k + 0.6]);
                    xlabel(ax, xLab);
                    if obj.SharedScale
                        ylabel(ax, "each trace on one shared scale");
                    else
                        ylabel(ax, "each trace scaled to its own peak");
                    end
                    obj.Axes_ = ax;
            end

            obj.Drawn_ = shown(:);
            for i = 1:k
                obj.Lines_(i).ButtonDownFcn = @(~,~) obj.on_trace_click_(shown(i));
            end
            for a = 1:numel(obj.Axes_)
                obj.Axes_(a).ButtonDownFcn = @(~,~) obj.on_axes_click_(a);
                quiet_axes_(obj.Axes_(a));
            end

            obj.restyle_();
            msg = obj.status_text_();
            if capped
                msg = msg + sprintf(" Drawing the first %d; untick some in the table to see the rest.", obj.MaxTraces);
            end
            obj.set_status_(msg, capped);
        end

        % -----------------------------------------------------------------
        function [X, Y, xLab, yLab, ref] = traces_(obj, shown)
            % The traces to draw, in display units, and the reference level
            % a shared scale is taken from.
            k = numel(shown);
            X = cell(k, 1);
            Y = cell(k, 1);
            switch obj.Domain
                case "Waveform"
                    for i = 1:k
                        C = obj.Combos(shown(i));
                        n = numel(C.Signal);
                        X{i} = (0:n-1).' / C.Fs * 1e3;
                        Y{i} = C.Signal;
                    end
                    xLab = "time (ms)";
                    yLab = "amplitude";
                    ref  = max(cellfun(@(y) max([abs(y); 0]), Y));

                case "Spectrum"
                    mags = cell(k, 1);
                    for i = 1:k
                        C = obj.Combos(shown(i));
                        [X{i}, mags{i}] = magnitude_spectrum_(C.Signal, C.Fs);
                    end
                    % dB re the loudest shown (shared) or each trace's own peak.
                    peaks = cellfun(@(m) max([m; eps]), mags);
                    for i = 1:k
                        if obj.SharedScale
                            r = max(peaks);
                        else
                            r = peaks(i);
                        end
                        Y{i} = max(20*log10(mags{i} / r + eps), obj.FloorDb);
                    end
                    xLab = "frequency (kHz)";
                    if obj.SharedScale
                        yLab = "magnitude (dB re loudest shown)";
                    else
                        yLab = "magnitude (dB re own peak)";
                    end
                    ref = 0;
            end
        end

        % -----------------------------------------------------------------
        function apply_limits_(obj, axs, X, Y, ref)
            for i = 1:numel(axs)
                ax = axs(i);
                if numel(axs) == 1
                    xs = vertcat(X{:});
                else
                    xs = X{i};
                end
                if ~isempty(xs) && max(xs) > min(xs)
                    xlim(ax, [min(xs), max(xs)]);
                end
                switch obj.Domain
                    case "Waveform"
                        if obj.SharedScale || numel(axs) == 1
                            a = ref;
                        else
                            a = max([abs(Y{i}); 0]);
                        end
                        if a > 0
                            ylim(ax, 1.08 * [-a a]);
                        end
                    case "Spectrum"
                        ylim(ax, [obj.FloorDb, 5]);
                end
            end
            if numel(axs) > 1 && obj.SharedScale
                linkaxes(axs, 'y');
            end
        end

        % -----------------------------------------------------------------
        function y = unit_trace_(obj, y, ref)
            % Map one trace into a band of height ~0.9 centred on zero for
            % the stacked view.
            switch obj.Domain
                case "Waveform"
                    if obj.SharedScale
                        a = ref;
                    else
                        a = max([abs(y); 0]);
                    end
                    if a > 0
                        y = 0.45 * y / a;
                    end
                case "Spectrum"
                    % Already dB re the right reference; squeeze the displayed
                    % range [FloorDb 0] into the band.
                    y = 0.9 * (y - obj.FloorDb) / -obj.FloorDb - 0.45;
            end
        end

        % -----------------------------------------------------------------
        function restyle_(obj)
            % Highlight the current combination without redrawing.
            if isempty(obj.Lines_), return; end
            isCur = obj.Drawn_ == obj.Current;
            switch obj.View
                case "Tiles"
                    for i = 1:numel(obj.Lines_)
                        if ~isvalid(obj.Lines_(i)), continue; end
                        ax = obj.Axes_(i);
                        if isCur(i)
                            obj.Lines_(i).LineWidth = 1.6;
                            ax.LineWidth = 2;
                            ax.XColor = obj.Accent; ax.YColor = obj.Accent;
                        else
                            obj.Lines_(i).LineWidth = 0.8;
                            ax.LineWidth = 0.5;
                            ax.XColor = [0.15 0.15 0.15]; ax.YColor = [0.15 0.15 0.15];
                        end
                    end
                otherwise
                    for i = 1:numel(obj.Lines_)
                        if ~isvalid(obj.Lines_(i)), continue; end
                        if isCur(i)
                            obj.Lines_(i).LineWidth = 2.2;
                        elseif any(isCur)
                            obj.Lines_(i).LineWidth = 0.6;
                        else
                            obj.Lines_(i).LineWidth = 0.8;
                        end
                    end
                    if any(isCur) && isvalid(obj.Lines_(isCur))
                        uistack(obj.Lines_(isCur), 'top');
                    end
            end
        end

        % -----------------------------------------------------------------
        function on_table_edit_(obj, evt)
            % The Show column is the only editable one.
            if evt.Indices(2) ~= 1, return; end
            c = obj.combo_at_row_(evt.Indices(1));
            if isnan(c), return; end
            mask = obj.Show_;
            mask(c) = logical(evt.NewData);
            obj.set_shown(mask);
        end

        function on_table_select_(obj, evt)
            % Ticking Show also selects its cell; on_table_edit_ has that.
            if isempty(evt.Indices) || evt.Indices(end, 2) == 1, return; end
            c = obj.combo_at_row_(evt.Indices(end, 1));
            if ~isnan(c), obj.select(c); end
        end

        function c = combo_at_row_(obj, r)
            % The combination shown in table row r. Rows can be sorted, so
            % the row number is not the combination; the "#" column is.
            % Callback indices are into the sorted view where the release
            % has DisplayData, and into Data (unsorted) where it does not.
            t = obj.H_.Table;
            c = NaN;
            if isprop(t, 'DisplayData')
                d = t.DisplayData;
            else
                d = t.Data;
            end
            if iscell(d) && r >= 1 && r <= size(d, 1)
                c = double(d{r, 2});
            elseif istable(d) && r >= 1 && r <= height(d)
                c = double(d{r, 2});
            end
            if c < 1 || c > numel(obj.Combos), c = NaN; end
        end

        function on_trace_click_(obj, c)
            obj.select(c);
            if strcmp(obj.Figure.SelectionType, 'open')
                obj.inspect(c);
            end
        end

        function on_axes_click_(obj, a)
            % A click on a tile's background picks that tile; on a shared
            % axes it picks nothing, since there is no telling which trace
            % was meant.
            if obj.View == "Tiles" && a <= numel(obj.Drawn_)
                obj.on_trace_click_(obj.Drawn_(a));
            end
        end

        % -----------------------------------------------------------------
        function msg = status_text_(obj)
            n = numel(obj.Combos);
            if n == 0
                msg = "No combinations.";
                return
            end
            fs = obj.Combos(1).Fs;
            msg = sprintf("%d combination(s) at %.10g Hz; %d shown. Current: #%d %s.", ...
                n, fs, nnz(obj.Show_), obj.Current, obj.Combos(obj.Current).Full);
            % Without a calibration SoundLevel never reaches the amplitude,
            % so a level series draws as identical traces -- say why.
            s = obj.Combos(1).Stim;
            if any(obj.PropNames == "SoundLevel") && ~is_calibrated_(s)
                msg = msg + " Uncalibrated: Sound Level does not change the amplitude.";
            end
        end

        % -----------------------------------------------------------------
        function set_status_(obj, msg, isError)
            if ~isfield(obj.H_, 'Status') || ~isvalid(obj.H_.Status), return; end
            obj.H_.Status.Text    = char(msg);
            obj.H_.Status.Tooltip = char(msg);
            if isError
                obj.H_.Status.FontColor = [0.75 0.15 0.15];
            else
                obj.H_.Status.FontColor = [0.35 0.35 0.35];
            end
        end

        % -----------------------------------------------------------------
        function settings_changed_(obj)
            if ~obj.Built_ || ~obj.is_open(), return; end
            obj.H_.View.Value   = char(obj.View);
            obj.H_.Domain.Value = char(obj.Domain);
            obj.H_.Shared.Value = obj.SharedScale;
            obj.render_();
        end

        % -----------------------------------------------------------------
        function pos = initial_position_(obj)
            % The remembered position, cascaded past any viewer already
            % open so a second window does not land exactly on the first.
            pos = [160 110 1290 720];
            try
                s = obj.stored_settings_();
                if isfield(s, 'Position') && isnumeric(s.Position) && numel(s.Position) == 4 ...
                        && all(isfinite(s.Position)) && all(s.Position(3:4) >= 300)
                    pos = double(s.Position(:).');
                end
            catch
            end
            nOpen = numel(findall(groot, 'Type', 'figure', 'Tag', 'stimgen.CombinationViewer'));
            pos(1:2) = pos(1:2) + 24 * [nOpen, -nOpen];

            % Keep the title bar on a screen.
            scr = get(groot, 'MonitorPositions');
            onAny = any(pos(1) + 50 >= scr(:,1) & pos(1) + 50 <= scr(:,1) + scr(:,3) & ...
                pos(2) + pos(4) - 10 >= scr(:,2) & pos(2) + pos(4) - 10 <= scr(:,2) + scr(:,4));
            if ~onAny
                pos(1:2) = [160 110];
            end
        end

        % -----------------------------------------------------------------
        function load_settings_(obj)
            s = obj.stored_settings_();
            try, if isfield(s, 'View'),        obj.View        = string(s.View);    end, catch, end %#ok<*TRYNC>
            try, if isfield(s, 'Domain'),      obj.Domain      = string(s.Domain);  end, catch, end
            try, if isfield(s, 'SharedScale'), obj.SharedScale = logical(s.SharedScale); end, catch, end
        end

        function save_settings_(obj)
            try
                s = struct('View', obj.View, 'Domain', obj.Domain, ...
                    'SharedScale', obj.SharedScale, 'Position', obj.Figure.Position);
                setpref(obj.PrefGroup, obj.PrefName, s);
            catch ME
                stimgen.util.vprintf(2, 'CombinationViewer: could not save settings: %s', ME.message);
            end
        end

        function s = stored_settings_(obj)
            s = struct();
            try
                if ispref(obj.PrefGroup, obj.PrefName)
                    v = getpref(obj.PrefGroup, obj.PrefName);
                    if isstruct(v) && isscalar(v)
                        s = v;
                    end
                end
            catch
            end
        end
    end
end


% =========================================================================
% Local functions
% =========================================================================

function set_prop_(obj, name, value)
try
    obj.(name) = value;
catch ME
    stimgen.util.vprintf(1, 1, ME);
end
end

function tf = is_calibrated_(stimObj)
% The test StimPlayer's status label applies: calibration data present and
% the stimulus set to apply it.
try
    C  = stimObj.Calibration;
    tf = stimObj.ApplyCalibration && isa(C, 'stimgen.StimCalibration') ...
        && ~isempty(C.CalibrationData);
catch
    tf = false;
end
end

function close_dialog_(dlg)
if ~isempty(dlg) && isvalid(dlg)
    close(dlg);
end
end

function quiet_axes_(ax)
% The axes toolbar's zoom state fights the limits this window sets, and the
% default interactions would take the clicks that pick a combination.
try
    ax.Toolbar.Visible = 'off';
    disableDefaultInteractivity(ax);
catch
end
end

function [f, m] = magnitude_spectrum_(y, fs)
% Single-sided magnitude spectrum, amplitude-normalized, frequency in kHz.
n = numel(y);
if n < 2
    f = 0; m = 0;
    return
end
nfft = max(1024, 2^nextpow2(n));
Y = abs(fft(y(:), nfft)) / n;
Y = Y(1:floor(nfft/2) + 1);
Y(2:end-1) = 2 * Y(2:end-1);
f = (0:numel(Y)-1).' * fs / nfft / 1e3;
m = Y;
end

function cm = trace_colors_(k)
% Categorical colours while they can still be told apart, a sequential map
% beyond that -- a long family is usually an ordered series anyway.
if k <= 7
    cm = lines(k);
else
    cm = parula(k + 1);
    cm = cm(1:k, :);
end
end

function [head, unit, scale] = describe_prop_(meta, name)
% Column header, unit and display scale for a property, from propMeta.
% The unit lives either in the label ("Duration (ms)") or in the display
% format ("%.1f Hz"); a header always ends up carrying it.
head  = name;
unit  = "";
scale = 1;
if isempty(meta) || ~isstruct(meta) || ~isfield(meta, char(name))
    return
end
pm = meta.(char(name));
if isfield(pm, 'label'), head = string(pm.label); end
scale = stimgen.StimType.display_scale(pm);
tok = regexp(char(head), '\(([^)]*)\)\s*$', 'tokens', 'once');
if ~isempty(tok)
    unit = string(tok{1});
elseif isfield(pm, 'format')
    unit = string(strtrim(regexprep(char(pm.format), '%[-+ #0]*\d*(\.\d+)?[a-zA-Z]', '')));
    if strlength(unit) > 0
        head = head + " (" + unit + ")";
    end
end
end

function txt = value_text_(values, name, meta)
% One property's value for one combination, in display units, no unit.
txt = "";
if ~isfield(values, char(name)), return; end
v = values.(char(name));
[~, ~, scale] = describe_prop_(meta, name);
if isnumeric(v) || islogical(v)
    v = double(v);
    if isnumeric(v), v = v * scale; end
    if isscalar(v)
        txt = string(num2str(v, '%.6g'));
    else
        txt = string(mat2str(v, 6));
    end
elseif isstring(v) || ischar(v)
    txt = strjoin(string(v), ",");
else
    try, txt = string(v); catch, txt = "<" + string(class(v)) + ">"; end
end
end

function [short, full] = describe_values_(values, names, meta)
% "4000 Hz, 60 dB SPL" for a tile title; "Frequency=4000 Hz, ..." for the
% status line.
sParts = strings(1, 0);
fParts = strings(1, 0);
for k = 1:numel(names)
    txt = value_text_(values, names(k), meta);
    if strlength(txt) == 0, continue; end
    [head, unit, ~] = describe_prop_(meta, names(k));
    label = strtrim(regexprep(char(head), '\([^)]*\)\s*$', ''));
    if strlength(unit) > 0 && unit ~= "%"
        withUnit = txt + " " + unit;
    else
        withUnit = txt + unit;
    end
    sParts(end+1) = withUnit;                        %#ok<AGROW>
    fParts(end+1) = string(label) + "=" + withUnit;  %#ok<AGROW>
end
short = strjoin(sParts, ", ");
full  = strjoin(fParts, ", ");
end
