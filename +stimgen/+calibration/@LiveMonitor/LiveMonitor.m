classdef LiveMonitor < handle
    % stimgen.calibration.LiveMonitor
    % Renderer for the stimgen.calibration.Engine LiveUpdate event stream.
    %
    % Draws three panels while a calibration runs: the acquired waveform with
    % the analysed span and clipping limits, its spectrum with harmonic markers
    % and the previous measurement as a ghost, and the partial transfer curve
    % with across-repeat spread, the required drive voltage, and run progress.
    %
    % The spectrum is drawn in dB SPL by default and in any of SpectrumUnitList
    % on request -- electrical units for judging the input stage, per-Hz
    % densities for comparing noise floors, dB re peak for shape alone. The
    % measurement itself is kept in volts, so changing units redraws the same
    % record rather than needing a new one.
    %
    % Graphics objects are created once and then updated in place, so a long
    % sweep does not rebuild the axes on every measurement. Updates are
    % rate-limited to MinInterval seconds; the final update of a run always
    % renders. Waveforms are drawn as a min/max envelope and spectra are
    % peak-held onto a log grid, which keeps redraw cost flat regardless of
    % record length; DecimateWaveforms=false trades that back for every
    % sample of the time-domain panels.
    %
    % Every panel is captioned the same way: a short title naming what is
    % on screen, with the measurement's numbers in a smaller subtitle
    % underneath (caption_), so a caption never runs past its panel.
    %
    % The transfer panel also carries the standard A/B/C/D weighting curves on
    % request (Weightings), anchored to the measured level at 1 kHz so the gap
    % between curve and measurement reads as what the ear discards.
    %
    % Attaches to axes supplied by a host GUI, or creates its own figure when
    % given none. Objects it created are the only ones reset() deletes, so it
    % can share axes with a host that draws its own static plots.
    %
    % The lookup tables, the background analysis and the delay probe are one
    % family of views. Given three axes they share the third and each clears
    % the last one on its way in -- one panel, one view at a time. Given five,
    % the background and the delay probe get panels of their own while the
    % three sweeps still share one, so a redraw of the sweep leaves the other
    % two measurements standing.
    %
    % Given a STRUCT of axes, each stimulus gets a panel of its own as well --
    % tone, click, swept sine -- and with it a plot shaped for that stimulus
    % rather than the one shape all three can share. Each may carry detail
    % axes underneath (see the constructor), drawn from the committed table
    % when a sweep finishes: per-frequency distortion and SNR for tones, the
    % same against duration for clicks, and for a swept sine the deconvolved
    % flatness, the group delay and the impulse response -- none of which a
    % level-versus-x panel can show. That is the form CalibrationGui uses,
    % one tab per stimulus.
    %
    % The filter test is a panel of that family too, named "filter_test":
    % what it measures is a level against frequency, so it could be read on
    % the tone panel, but it is the one measurement that draws the SAME
    % quantity twice -- once through the speaker and once through the filter
    % and the speaker -- and put on the tone panel it either overwrote the
    % tone table or was overwritten by the next redraw of it. Given no panel
    % of its own it still falls back there.
    %
    % Usage:
    %   % Own window, driven by an engine run:
    %   eng = stimgen.calibration.Engine(adapter);
    %   eng.set_configuration(ShowLivePlots=true);
    %   mon = stimgen.calibration.LiveMonitor(eng);
    %   eng.calibrate_tones();
    %
    %   % Into a host GUI's axes, sharing one transfer panel:
    %   mon = stimgen.calibration.LiveMonitor(eng, Axes=[axSig axSpec axXfer]);
    %
    %   % ... or with a panel per view:
    %   mon = stimgen.calibration.LiveMonitor(eng, ...
    %       Axes=[axSig axSpec axXfer axBackground axLatency]);
    %
    % See also: stimgen.calibration.Engine, stimgen.calibration.LiveUpdate,
    %           stimgen.calibration.CalibrationGui

    properties
        MinInterval (1,1) double {mustBeNonnegative} = 0.05  % s between redraws
        SpectrumBins (1,1) double {mustBePositive}   = 1200  % log-grid bins in the spectrum

        % How a time-domain waveform is drawn. On (the default), a record
        % longer than 2*MaxPoints is reduced to the min/max envelope of each
        % block, which keeps a redraw the same cost whatever the record
        % length -- a calibration record can be hundreds of thousands of
        % samples, and handing all of them to a line object costs more than
        % the measurement did. Off draws every sample, which is what an
        % operator zooming into the panel to see the record itself wants.
        %
        % The envelope preserves the peak of every block, so a clipped or
        % transient record still reads as one; what it costs is the shape
        % *within* a block, which at full-record zoom is below a pixel
        % anyway. It only starts to matter once zoomed in far enough that a
        % block spans several pixels -- which is exactly when to turn this
        % off.
        DecimateWaveforms (1,1) logical = true
        MaxPoints (1,1) double {mustBePositive} = 4000  % blocks per decimated waveform

        SpectrumUnits (1,1) string = "dB SPL"  % y-axis of the spectrum panel; see SpectrumUnitList
        ShowGhost   (1,1) logical = true   % overlay the previous spectrum
        ShowVoltage (1,1) logical = true   % required-drive-voltage axis on the transfer plot
        LogX        (1,1) logical = true   % log x-axis on the transfer plot

        % Weighting curves overlaid on the transfer plot, e.g. ["A" "C"];
        % empty for none. Ignored on a panel whose x-axis is not frequency.
        Weightings (1,:) string {mustBeMember(Weightings, ["A", "B", "C", "D"])} = string.empty(1, 0)
    end

    properties (Constant)
        WeightingTypes = ["A", "B", "C", "D"]   % offered as overlays, in legend order

        % The views that draw on the transfer panel -- one axes between them,
        % or one each. Named here because the clearing rules, the cache keys
        % and the weighting overlays are all per-view.
        %
        % "transfer" is the combined view: every lookup table overlaid on one
        % axes, which is what a host that supplied a single sweep panel gets.
        % Where each stimulus was given a panel of its own the three named
        % ones are drawn instead and "transfer" never is. Both forms are in
        % the family because they resolve to the same axes when the panels
        % are shared, and clear_for_ decides what a redraw takes down with it
        % by comparing axes handles rather than names.
        TransferPanels = ["transfer", "tone", "click", "swept_sine", ...
            "filter_test", "background", "latency"]

        % The three stimulus panels, in the order a rig is normally
        % calibrated in. Their names are also the Engine's CalibrationData
        % field names, which is what lets one loop draw all three.
        SweepPanels = ["tone", "click", "swept_sine"]

        % Units the spectrum panel can be drawn in, in menu order. dB SPL is the
        % calibration's own scale; the electrical units say whether the input
        % stage has room left; the per-Hz forms are the comparable way to read a
        % noise floor, since a per-bin level depends on the analysis window and a
        % density does not; dB re peak shows shape alone, which is what a rig
        % without a measured reference can still be judged on.
        SpectrumUnitList = ["dB SPL", "dB SPL/Hz", "Pa", "V", "dBV", ...
            "V/sqrt(Hz)", "dB re peak"]
    end

    properties (SetAccess = private)
        AxSignal        % matlab.graphics.axis.Axes | matlab.ui.control.UIAxes | []
        AxSpectrum
        AxTransfer      % the combined lookup-table panel; = AxTone when unshared
        AxTone          % tone sweep, tone LUT and the tone LUT test
        AxClick         % click sweep, click LUT and the click LUT test
        AxSweptSine     % swept sine sweep and its LUT
        AxFilterTest    % equalization filter test; own axes when the host named one, else AxTone
        AxBackground    % own axes when the host supplied five; else AxTransfer
        AxLatency       % likewise

        % Detail axes under a stimulus panel; empty when the host gave none,
        % and every renderer that touches one guards on that. Nothing drawn
        % here is live: the figures they show are computed when a sweep is
        % committed, not per measurement, so they fill in when the run ends.
        AxToneDetail    % harmonic distortion and SNR against frequency
        AxClickDetail   % harmonic distortion and SNR against duration
        AxSweptDetail   % deconvolved magnitude flatness and group delay
        AxSweptImpulse  % impulse response, its arrival and first reflection
        AxFilterDetail  % filter test: deviation from flat, before and after

        Engine          % stimgen.calibration.Engine | []
        OwnsFigure (1,1) logical = false
    end

    properties (Access = private)
        Figure_                    % figure created by this object, if any
        Listener_                  % listener on the engine's LiveUpdate event
        H_ (1,1) struct = struct() % cache of graphics objects this object created
        LastDraw_ (1,1) double = -inf   % toc() of the last render
        Timer_                     % tic id backing LastDraw_
        PrevSpectrum_ (1,2) cell = {[], []}  % {f, V rms} behind the one on screen -- the ghost
        CurrSpectrum_ (1,2) cell = {[], []}  % {f, V rms} of the record on screen
        LastRecord_ (1,:) double = []        % fingerprint of the record last drawn, to tell a redraw from a new measurement
        LastStage_ (1,1) string = ""
        RenderFailed_ (1,1) logical = false  % latched by update() on a render error; re-armed at "start"
    end

    methods
        function obj = LiveMonitor(eng, opts)
            % obj = stimgen.calibration.LiveMonitor()
            % obj = stimgen.calibration.LiveMonitor(eng)
            % obj = stimgen.calibration.LiveMonitor(eng, Axes=[a1 a2 a3])
            %
            % Parameters:
            %   eng  - stimgen.calibration.Engine to follow; omit to attach later
            %   Axes - [signal spectrum transfer] axes handles, or five --
            %          [signal spectrum transfer background latency] -- to give
            %          the background analysis and the delay probe panels of
            %          their own, or a struct to give each STIMULUS one too:
            %
            %            signal, spectrum      the record being acquired
            %            tone, click, swept_sine   one panel per sweep
            %            filter_test, background, latency
            %
            %          and, optionally, the detail axes drawn beneath four
            %          of those when a run is committed:
            %
            %            tone_detail, click_detail    distortion and SNR
            %            swept_detail                 flatness and group delay
            %            swept_impulse                impulse response
            %            filter_detail                equalized flatness
            %
            %          A struct field left out is treated as absent, not as
            %          an error: a host may want the tone panel's detail and
            %          not the click panel's. Omit Axes entirely to create a
            %          dedicated figure.
            arguments
                eng = []
                opts.Axes = []
            end

            obj.Timer_ = tic;

            if isempty(opts.Axes)
                obj.build_figure_();
            elseif isstruct(opts.Axes)
                obj.assign_axes_struct_(opts.Axes);
            else
                ax = opts.Axes;
                if numel(ax) ~= 3 && numel(ax) ~= 5
                    error('stimgen:calibration:LiveMonitor:badAxes', ...
                        ['Axes must be three handles -- [signal spectrum transfer] ' ...
                        '-- five: [signal spectrum transfer background latency] ' ...
                        '-- or a struct naming one panel per stimulus.']);
                end
                obj.AxSignal   = ax(1);
                obj.AxSpectrum = ax(2);
                obj.AxTransfer = ax(3);
                % Three is the shared form: the background analysis and the
                % delay probe draw on the transfer axes and clear whatever
                % was there. Five gives each its own, so all three survive
                % together.
                if numel(ax) == 5
                    obj.AxBackground = ax(4);
                    obj.AxLatency    = ax(5);
                else
                    obj.AxBackground = ax(3);
                    obj.AxLatency    = ax(3);
                end
                % Every stimulus draws on the one sweep panel in both of
                % these forms, which is what makes show_calibration overlay
                % the tables rather than draw one per stimulus.
                obj.AxTone      = ax(3);
                obj.AxClick     = ax(3);
                obj.AxSweptSine = ax(3);
                obj.AxFilterTest = ax(3);
            end

            if ~isempty(eng)
                obj.attach(eng);
            end
        end

        function delete(obj)
            % Release the engine registration and any figure this object owns.
            obj.detach();
            if obj.OwnsFigure && ~isempty(obj.Figure_) && isvalid(obj.Figure_)
                delete(obj.Figure_);
            end
        end

        attach(obj, eng)   % Follow an engine's LiveUpdate event.
        detach(obj)        % Stop following the current engine.
        update(obj, d)     % Render one stimgen.calibration.LiveUpdate payload.
        reset(obj)         % Delete every graphics object this monitor created.
        show_engine_state(obj, eng)  % Draw an engine's current response, off-run.
        show_calibration(obj, eng)   % Draw an engine's committed LUTs: one panel per stimulus, or all on the shared one.
        show_filter_test(obj, eng)   % Draw an engine's recorded filter test on its own panel.
        show_background(obj, eng)    % Draw an engine's background analysis on its panel.
        show_latency(obj, lat)       % Draw a conduction-delay probe's diagnostics on its panel.

        function set.Weightings(obj, value)
            obj.Weightings = unique(value, 'stable');

            % Both the curves and the legends that name them are cached, so a
            % selection changed mid-run would otherwise leave an orphan curve
            % on the panel and a legend that disagrees with it: the legends
            % are built with AutoUpdate off and never pick up a line added
            % after them. Dropping both makes the next render rebuild them.
            % Every panel's copy goes, not just the one on screen: with a
            % panel per view the same overlay is drawn on more than one.
            for p = stimgen.calibration.LiveMonitor.TransferPanels
                for t = stimgen.calibration.LiveMonitor.WeightingTypes
                    obj.drop_(char("wt_" + p + "_" + t));
                end
                obj.drop_(char(p + "_legend"));
                obj.drop_(char(p + "_lut_legend"));
            end
            obj.drop_('bg_legend');
        end

        function set.ShowGhost(obj, value)
            obj.ShowGhost = value;

            % The ghost is drawn only while it is on, and updated in place
            % rather than recreated, so switching it off would otherwise leave
            % the last one on the panel until something reset the cache.
            if ~value
                obj.drop_('spec_ghost');
            end
        end

        function set.ShowVoltage(obj, value)
            obj.ShowVoltage = value;

            % Same reason as the ghost, for both the live and the static
            % transfer view, plus the right-hand axis they share: neither view
            % clears the voltage traces on its way out. The legends naming
            % those traces go too -- they are built with AutoUpdate off, so a
            % legend that outlived its lines would keep naming them. Every
            % sweep panel is swept, not just the one on screen: with a panel
            % per stimulus there are three of each of these.
            bases = {'volt', 'vmax', 'vover', 'lut_vmax', 'lut_tone_v', ...
                'lut_click_v', 'lut_swept_sine_v', 'legend', 'lut_legend'};
            for p = stimgen.calibration.LiveMonitor.TransferPanels
                for k = 1:numel(bases)
                    obj.drop_(char(p + "_" + bases{k}));
                end
            end

            if ~value
                obj.hide_voltage_axis_();
            end
        end

        function set.SpectrumUnits(obj, v)
            % Rejected here rather than at draw time: an unknown unit would
            % otherwise surface as a latched render failure partway through a
            % sweep, which reads as a plotting bug rather than a bad assignment.
            v = string(v);
            mustBeMember(v, stimgen.calibration.LiveMonitor.SpectrumUnitList);
            obj.SpectrumUnits = v;
        end

        function show(obj)
            % Bring an owned figure to the foreground. Never called during a
            % run: stealing focus on every measurement is what the old
            % subplot-based live plots did wrong.
            if obj.OwnsFigure && ~isempty(obj.Figure_) && isvalid(obj.Figure_)
                figure(obj.Figure_);
            end
        end
    end

    methods (Access = private)
        build_figure_(obj)          % Create the standalone monitor window.
        render_(obj, d)             % Draw all three panels from one payload.
        render_signal_(obj, d)      % Waveform panel.
        render_spectrum_(obj, d)    % Spectrum panel.
        render_transfer_(obj, d, panel)  % Live sweep on one stimulus panel.
        render_latency_(obj, lat)   % Conduction-delay panel.
        show_lut_(obj, eng, panel)  % One committed lookup table on its own panel.
        draw_quality_panel_(obj, ax, panel, x, m, xLabelText, titleText)  % Distortion/SNR detail axes.
        show_tone_detail_(obj, eng)      % Distortion and SNR against frequency.
        show_click_detail_(obj, eng)     % Distortion and SNR against duration.
        show_swept_detail_(obj, eng)     % Flatness, group delay and impulse response.
        render_weighting_(obj, panel, f, lvl)  % Weighting curves over a level/frequency axis.

        function ax = panel_axes_(obj, panel)
            % The axes one view draws on. Views the host gave no panel of
            % their own return the same handle, which is what clear_for_
            % compares to decide whether a redraw of one takes another down
            % with it.
            switch panel
                case "background",  ax = obj.AxBackground;
                case "latency",     ax = obj.AxLatency;
                case "tone",        ax = obj.AxTone;
                case "click",       ax = obj.AxClick;
                case "swept_sine",  ax = obj.AxSweptSine;
                case "filter_test", ax = obj.AxFilterTest;
                otherwise,          ax = obj.AxTransfer;
            end
        end

        function ax = detail_axes_(obj, panel, which)
            % ax = detail_axes_(obj, panel, which)
            % One stimulus panel's detail axes, or [] where the host gave
            % none. "which" is 1 for the panel's first detail axes and 2 for
            % the second, which only the swept sine has.
            ax = [];
            switch panel
                case "tone"
                    if which == 1, ax = obj.AxToneDetail; end
                case "click"
                    if which == 1, ax = obj.AxClickDetail; end
                case "swept_sine"
                    if which == 1
                        ax = obj.AxSweptDetail;
                    else
                        ax = obj.AxSweptImpulse;
                    end
                case "filter_test"
                    if which == 1, ax = obj.AxFilterDetail; end
            end
            if ~isempty(ax) && ~all(isgraphics(ax))
                ax = [];
            end
        end

        function tf = sweeps_share_panel_(obj)
            % True when the host gave one axes for all three stimuli, which
            % is what makes show_calibration overlay the tables instead of
            % drawing a plot per stimulus. Asked of the handles rather than
            % remembered from the constructor, so an axes deleted underneath
            % this object cannot leave the two disagreeing.
            tf = isequal(obj.AxTone, obj.AxClick) && ...
                 isequal(obj.AxTone, obj.AxSweptSine);
        end

        function assign_axes_struct_(obj, s)
            % assign_axes_struct_(obj, s)
            % Take the panel axes from a struct, one field per panel. Absent
            % fields stay empty and every renderer guards on that, so a host
            % may supply a stimulus panel without its detail axes -- or, for
            % the two views this object has always been able to share, no
            % panel at all.
            obj.AxSignal    = field_(s, 'signal');
            obj.AxSpectrum  = field_(s, 'spectrum');
            obj.AxTone      = field_(s, 'tone');
            obj.AxClick     = field_(s, 'click');
            obj.AxSweptSine = field_(s, 'swept_sine');

            % The combined view's axes. It is never drawn where the three
            % stimuli have panels of their own, but clear_for_ still asks
            % for it by name, and an empty handle there would make the
            % family comparison meaningless.
            obj.AxTransfer = obj.AxTone;

            % A host that named no background or delay panel falls back to
            % the tone panel, the same sharing the three-axes form has
            % always had rather than silently dropping the measurement.
            obj.AxBackground = field_(s, 'background', obj.AxTone);
            obj.AxLatency    = field_(s, 'latency',    obj.AxTone);

            % The filter test falls back the same way. Sharing the tone panel
            % is what it did before it had one of its own, and a host that
            % names no panel for it gets that rather than a run with nowhere
            % to draw.
            obj.AxFilterTest = field_(s, 'filter_test', obj.AxTone);

            obj.AxToneDetail   = field_(s, 'tone_detail');
            obj.AxClickDetail  = field_(s, 'click_detail');
            obj.AxSweptDetail  = field_(s, 'swept_detail');
            obj.AxSweptImpulse = field_(s, 'swept_impulse');
            obj.AxFilterDetail = field_(s, 'filter_detail');

            if isempty(obj.AxTone) || isempty(obj.AxClick) || isempty(obj.AxSweptSine)
                error('stimgen:calibration:LiveMonitor:badAxes', ...
                    ['An Axes struct must name a panel for every stimulus: ' ...
                    'tone, click and swept_sine.']);
            end
        end

        function clear_for_(obj, panel)
            % clear_for_(obj, panel)
            % Release every graphics object one view owns, and those of any
            % other view sharing its axes.
            %
            % With a panel per view only this view's objects go, which is
            % what lets a background analysis and a delay probe outlive a
            % sweep being redrawn over them. Where the views share one axes
            % every view on it has to go instead: a curve left from another
            % would be read against limits, a scale and an x-axis that are
            % no longer its own.
            obj.drop_keys_(stimgen.calibration.LiveMonitor.panel_keys_(panel));

            family = stimgen.calibration.LiveMonitor.TransferPanels;
            if ~any(panel == family)
                return
            end
            ax = obj.panel_axes_(panel);
            if isempty(ax)
                return
            end
            for p = family(family ~= panel)
                if isequal(obj.panel_axes_(p), ax)
                    obj.drop_keys_(stimgen.calibration.LiveMonitor.panel_keys_(p));
                end
            end
        end

        function drop_keys_(obj, keys)
            % Delete a list of cached objects and forget them.
            for k = 1:numel(keys)
                obj.drop_(keys{k});
            end
        end

        function [t, v] = waveform_xy_(obj, y, fs, t0Ms)
            % [t, v] = waveform_xy_(obj, y, fs)
            % [t, v] = waveform_xy_(obj, y, fs, t0Ms)
            % One waveform's display points, in milliseconds from t0Ms,
            % following DecimateWaveforms. The single place that policy is
            % applied, so the response, the excitation behind it and the
            % delay probe's record are always drawn the same way -- three
            % traces read against each other, which they could not be if
            % one were an envelope and another every sample.
            arguments
                obj
                y
                fs (1,1) double
                t0Ms (1,1) double = 0
            end
            if obj.DecimateWaveforms
                [t, v] = stimgen.calibration.LiveMonitor.envelope_decimate_( ...
                    y, fs, obj.MaxPoints);
            else
                v = reshape(y, 1, []);
                t = (0:numel(v)-1) ./ fs .* 1e3;
            end
            t = t + t0Ms;
        end

        function h = gobj_(obj, key, ctor)
            % h = gobj_(obj, key, ctor)
            % Return the cached graphics object for key, creating it with ctor
            % when absent or deleted. Recreating on demand is what lets a host
            % GUI cla() these axes to draw something else without leaving this
            % object holding stale handles.
            if isfield(obj.H_, key)
                h = obj.H_.(key);
                if ~isempty(h) && all(isgraphics(h))
                    return
                end
            end
            h = ctor();
            obj.H_.(key) = h;
        end

        function tf = has_(obj, key)
            % True when key names a live cached object.
            tf = isfield(obj.H_, key) && ~isempty(obj.H_.(key)) && all(isgraphics(obj.H_.(key)));
        end

        function drop_(obj, key)
            % Delete one cached object and forget it.
            if obj.has_(key)
                delete(obj.H_.(key));
            end
            if isfield(obj.H_, key)
                obj.H_ = rmfield(obj.H_, key);
            end
        end

        function hide_voltage_axis_(obj)
            % Retire the right-hand drive-voltage axis on every sweep panel.
            % The axis itself outlives the lines drawn on it -- deleting
            % those leaves an empty scale and a label behind -- so it is
            % hidden the same way show_background hides it; whichever view
            % draws voltage next turns it back on. Shared panels resolve to
            % one handle and are hidden once.
            done = {};
            for p = stimgen.calibration.LiveMonitor.TransferPanels
                ax = obj.panel_axes_(p);
                if isempty(ax) || ~all(isgraphics(ax)) || numel(ax.YAxis) < 2
                    continue
                end
                if any(cellfun(@(h) isequal(h, ax), done))
                    continue
                end
                done{end+1} = ax;
                yyaxis(ax, 'right');
                ylabel(ax, '');
                ax.YAxis(2).Visible = 'off';
                yyaxis(ax, 'left');
            end
        end
    end

    methods (Static)
        function panel = stage_panel(stage)
            % panel = stimgen.calibration.LiveMonitor.stage_panel(stage)
            % The stimulus panel a run stage draws its lookup table on.
            %
            % Public and static because a host has to agree with it: a GUI
            % that brings up a tab before starting a run picks the tab from
            % here rather than from a list of its own, or the two drift and
            % an operator watches an empty panel while the curve fills in
            % behind another tab (CalibrationGui.focus_sweep_panel_).
            %
            % A table's verification belongs on the panel of the table it
            % verifies -- a tone LUT test read anywhere but under the tone
            % curve is a set of numbers with nothing to disagree with. The
            % filter test is the exception, and has a panel of its own: it
            % verifies no table, it draws two curves of the same quantity
            % rather than one, and sharing the tone panel meant one of the
            % two measurements always lost.
            %
            % Parameters:
            %   stage - a stimgen.calibration.LiveUpdate Stage
            %
            % Returns:
            %   panel - "tone" | "click" | "swept_sine" | "filter_test"
            arguments
                stage (1,1) string
            end
            switch stage
                case {"click", "click_test"}
                    panel = "click";
                case "swept_sine"
                    panel = "swept_sine";
                case "filter_test"
                    panel = "filter_test";
                otherwise   % tone, tone_test
                    panel = "tone";
            end
        end
    end

    methods (Static, Access = private)
        [t, y] = envelope_decimate_(y, fs, maxPoints)   % Min/max envelope for display.
        [f, vrms, noiseBw] = spectrum_vrms_(y, fs, nBins, spec)  % V rms spectrum on a log grid.
        [v, info] = convert_spectrum_(vrms, unit, refLevel, micSens, noiseBw)  % V rms to a display unit.

        function keys = panel_keys_(panel)
            % keys = panel_keys_(panel)
            % Every cache key one view owns, weighting overlays included.
            % Enumerating them is what makes a redraw of one view able to
            % leave the others standing; a new graphics object in any render
            % function belongs on this list or it will outlive its panel.
            %
            % "response" covers the waveform and spectrum panels together:
            % they are always cleared as a pair, being two views of one
            % record.
            wt = arrayfun(@(t) char("wt_" + panel + "_" + t), ...
                stimgen.calibration.LiveMonitor.WeightingTypes, ...
                UniformOutput=false);

            switch panel
                case "response"
                    keys = [{'sig_span', 'sig_exc', 'sig_exc_fill', 'sig_resp', ...
                        'sig_clip', 'spec_ghost', 'spec_current', 'spec_floor', ...
                        'spec_marks'}, ...
                        arrayfun(@(k) sprintf('spec_txt%d', k), 1:8, ...
                        UniformOutput=false)];
                case "background"
                    keys = [{'bg_spectrum', 'bg_bands', 'bg_bands_a', ...
                        'bg_broadband', 'bg_peaks', 'bg_legend'}, ...
                        arrayfun(@(k) sprintf('bg_pk%d', k), 1:8, ...
                        UniformOutput=false), wt];
                case "latency"
                    keys = [{'lat_corr', 'lat_pick', 'lat_pick_txt', ...
                        'lat_bound', 'lat_probe', 'lat_floor', 'lat_legend'}, wt];
                otherwise
                    % A stimulus panel, or the combined one. All four own the
                    % same shapes -- a live sweep, a committed table, and the
                    % detail axes underneath -- so one list of base names is
                    % scoped by the panel's own name rather than repeated
                    % four times. Listing a name no panel happens to draw
                    % costs nothing: drop_ ignores a key it has never seen.
                    bases = {'meas', 'sd', 'pending', 'cur', 'norm', ...
                        'volt', 'vmax', 'vover', 'legend', ...
                        'lut_tone', 'lut_click', 'lut_swept_sine', ...
                        'lut_tone_v', 'lut_click_v', 'lut_swept_sine_v', ...
                        'lut_vmax', 'lut_legend', ...
                        'det1', 'det2', 'det3', 'det4', 'det_ref', 'det_legend', ...
                        'dev', 'dev_band', 'gd', 'gd_bulk', 'gd_legend', ...
                        'ir', 'ir_arr', 'ir_refl', 'ir_legend', ...
                        'ft_unfiltered', 'ft_filtered', 'ft_dev_unfiltered', ...
                        'ft_dev_filtered', 'ft_tol', 'ft_ref', 'ft_legend', ...
                        'ft_det_legend'};
                    keys = [cellfun(@(b) char(panel + "_" + b), bases, ...
                        UniformOutput=false), wt];
            end
        end

        function caption_(ax, titleText, subtitleText, titleColor)
            % caption_(ax, titleText, subtitleText, titleColor)
            % Set a panel's title and subtitle together. The title names what
            % is on screen and stays short enough to fit the panel; the
            % measurements that used to run past the panel's edge live in the
            % smaller subtitle, which may be a cell array for two lines. Both
            % are always written: the panels swap views over shared axes, and
            % a view that set only its title would inherit the last view's
            % subtitle.
            arguments
                ax
                titleText
                subtitleText = ''
                titleColor (1,3) double = [0 0 0]
            end
            title(ax, titleText, Color=titleColor);
            subtitle(ax, subtitleText, FontSize=9);
        end

        function label = frequency_ticks_(ax, labelText)
            % label = frequency_ticks_(ax, labelText)
            % Label a frequency axis in kHz and return the axis caption to use
            % with it.
            %
            % A log frequency axis is labelled 10^3, 10^4 by default, which
            % states the decade and leaves the reader to work out that the tick
            % between them is 2 kHz. Ticks are placed at the 1-2-5 points of
            % each decade instead and written as the kHz value they are, so
            % every tick on screen is a number a rig is set to.
            %
            % Only the tick text is in kHz; the data stays in Hz. The caption
            % returned is labelText with its unit rewritten by a factor of a
            % thousand, which is why a mixed axis works too -- a click LUT's
            % microseconds and a tone LUT's hertz divide by the same 1000, so
            % "frequency (Hz) / duration (us)" reads correctly as
            % "frequency (kHz) / duration (ms)".
            %
            % Parameters:
            %   ax        - axes whose XLim and XScale are already set
            %   labelText - the axis caption in Hz/us units
            %
            % Returns:
            %   label - the caption to apply, in kHz/ms units
            arguments
                ax
                labelText (1,:) char = ''
            end
            label = strrep(strrep(labelText, '(Hz)', '(kHz)'), '(\mus)', '(ms)');

            if ~isgraphics(ax)
                return
            end

            lims = xlim(ax);
            if ~all(isfinite(lims)) || lims(2) <= lims(1)
                return
            end

            if strcmp(ax.XScale, 'log')
                decades = floor(log10(max(lims(1), realmin))) : ceil(log10(lims(2)));
                ticks = reshape([1; 2; 5] * 10 .^ decades, 1, []);
                ticks = ticks(ticks >= lims(1) & ticks <= lims(2));
                % A span too narrow to hold three of those decade points --
                % a zoomed axis, a two-point LUT -- keeps whatever MATLAB
                % chose for it, relabelled. Forcing the 1-2-5 grid there
                % would leave an axis with one tick on it.
                if numel(ticks) < 3
                    ticks = [];
                end
            else
                ticks = [];
            end

            if isempty(ticks)
                ax.XTickMode = 'auto';   % re-derive: the last call set it manual
                ticks = ax.XTick;
                ticks = ticks(ticks >= lims(1) & ticks <= lims(2));
            end
            if isempty(ticks)
                return
            end

            ax.XTick = ticks;
            ax.XTickLabel = arrayfun(@(v) sprintf('%g', round(v / 1e3, 6)), ...
                ticks, UniformOutput=false);
        end

        function s = clock_(seconds)
            % Format a duration as m:ss, or --:-- when unknown.
            if ~isfinite(seconds) || seconds < 0
                s = '--:--';
                return
            end
            seconds = round(seconds);
            s = sprintf('%d:%02d', floor(seconds / 60), mod(seconds, 60));
        end

        function m = lut_metrics_(eng, field)
            % m = lut_metrics_(eng, field)
            % The metrics struct one committed table carries, or an empty
            % struct where the table is absent or predates them. Every
            % reader asks isfield of what comes back, so an .esgc saved
            % before a figure existed degrades to a panel without that trace
            % rather than to a render failure that suspends live plotting
            % for the rest of the run.
            m = struct();
            C = eng.CalibrationData;
            if ~isstruct(C) || ~isfield(C, field) || isempty(C.(field))
                return
            end
            S = C.(field);
            if isfield(S, 'metrics') && isstruct(S.metrics)
                m = S.metrics;
            end
        end

        function s = calibration_stamp_(eng)
            % Age of the calibration, so a stale file is obvious on screen.
            % Every panel drawn from committed data carries it, which is why
            % it is here rather than local to one of them.
            t = eng.CalibrationTimestamp;
            if isnat(t)
                s = 'measurement date unknown';
                return
            end
            s = sprintf('measured %s', ...
                char(datetime(t, Format='dd-MMM-yyyy HH:mm')));
        end

        function s = stage_name_(stage)
            % Human-readable name for a run stage.
            switch stage
                case "tone",       s = 'Tone sweep';
                case "latency",    s = 'Conduction delay';
                case "click",      s = 'Click sweep';
                case "swept_sine", s = 'Swept sine';
                case "filter_test", s = 'Filter test';
                case "tone_test",  s = 'Tone LUT test';
                case "click_test", s = 'Click LUT test';
                case "reference",  s = 'Reference';
                case "background", s = 'Background';
                otherwise,         s = char(stage);
            end
        end
    end
end

% ------------------------------------------------------------------------ %
function ax = field_(s, name, dflt)
% One axes handle out of the constructor's Axes struct, or the default when
% the field is absent or empty. Absent rather than an error, so a host can
% name only the panels it built.
arguments
    s (1,1) struct
    name (1,:) char
    dflt = []
end
ax = dflt;
if isfield(s, name) && ~isempty(s.(name)) && all(isgraphics(s.(name)))
    ax = s.(name);
end
end
