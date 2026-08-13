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
    % renders. Long records are drawn as a min/max envelope and spectra are
    % peak-held onto a log grid, which keeps redraw cost flat regardless of
    % record length.
    %
    % The transfer panel also carries the standard A/B/C/D weighting curves on
    % request (Weightings), anchored to the measured level at 1 kHz so the gap
    % between curve and measurement reads as what the ear discards.
    %
    % Attaches to axes supplied by a host GUI, or creates its own figure when
    % given none. Objects it created are the only ones reset() deletes, so it
    % can share axes with a host that draws its own static plots.
    %
    % Usage:
    %   % Own window, driven by an engine run:
    %   eng = stimgen.calibration.Engine(adapter);
    %   eng.set_configuration(ShowLivePlots=true);
    %   mon = stimgen.calibration.LiveMonitor(eng);
    %   eng.calibrate_tones();
    %
    %   % Into a host GUI's axes:
    %   mon = stimgen.calibration.LiveMonitor(eng, Axes=[axSig axSpec axXfer]);
    %
    % See also: stimgen.calibration.Engine, stimgen.calibration.LiveUpdate,
    %           stimgen.calibration.CalibrationGui

    properties
        MinInterval (1,1) double {mustBeNonnegative} = 0.05  % s between redraws
        MaxPoints   (1,1) double {mustBePositive}    = 4000  % samples drawn per waveform
        SpectrumBins (1,1) double {mustBePositive}   = 1200  % log-grid bins in the spectrum
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
        AxTransfer
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
            %   Axes - [signal spectrum transfer] axes handles. Omit to create a
            %          dedicated figure.
            arguments
                eng = []
                opts.Axes = []
            end

            obj.Timer_ = tic;

            if isempty(opts.Axes)
                obj.build_figure_();
            else
                ax = opts.Axes;
                if numel(ax) ~= 3
                    error('stimgen:calibration:LiveMonitor:badAxes', ...
                        'Axes must be three handles: [signal spectrum transfer].');
                end
                obj.AxSignal   = ax(1);
                obj.AxSpectrum = ax(2);
                obj.AxTransfer = ax(3);
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
        show_calibration(obj, eng)   % Draw an engine's committed LUTs on the transfer axes.
        show_background(obj, eng)    % Draw an engine's background analysis on the transfer axes.

        function set.Weightings(obj, value)
            obj.Weightings = unique(value, 'stable');

            % Both the curves and the legends that name them are cached, so a
            % selection changed mid-run would otherwise leave an orphan curve
            % on the panel and a legend that disagrees with it: the legends
            % are built with AutoUpdate off and never pick up a line added
            % after them. Dropping both makes the next render rebuild them.
            for t = stimgen.calibration.LiveMonitor.WeightingTypes
                obj.drop_(char("wt_" + t));
            end
            obj.drop_('xfer_legend');
            obj.drop_('static_legend');
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
            % legend that outlived its lines would keep naming them.
            keys = {'xfer_volt', 'xfer_vmax', 'xfer_vover', 'static_tone_v', ...
                'static_swept_sine_v', 'static_click_v', 'static_vmax'};
            for k = 1:numel(keys)
                obj.drop_(keys{k});
            end
            obj.drop_('xfer_legend');
            obj.drop_('static_legend');

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
        render_transfer_(obj, d)    % Transfer-curve panel.
        render_weighting_(obj, ax, f, lvl)  % Weighting curves over a level/frequency axis.

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
            % Retire the transfer panel's right-hand drive-voltage axis. The
            % axis itself outlives the lines drawn on it -- deleting those
            % leaves an empty scale and a label behind -- so it is hidden the
            % same way show_background hides it; whichever view draws voltage
            % next turns it back on.
            ax = obj.AxTransfer;
            if isempty(ax) || ~all(isgraphics(ax)) || numel(ax.YAxis) < 2
                return
            end
            yyaxis(ax, 'right');
            ylabel(ax, '');
            ax.YAxis(2).Visible = 'off';
            yyaxis(ax, 'left');
        end
    end

    methods (Static, Access = private)
        [t, y] = envelope_decimate_(y, fs, maxPoints)   % Min/max envelope for display.
        [f, vrms, noiseBw] = spectrum_vrms_(y, fs, nBins)  % V rms spectrum on a log grid.
        [v, info] = convert_spectrum_(vrms, unit, refLevel, micSens, noiseBw)  % V rms to a display unit.

        function s = clock_(seconds)
            % Format a duration as m:ss, or --:-- when unknown.
            if ~isfinite(seconds) || seconds < 0
                s = '--:--';
                return
            end
            seconds = round(seconds);
            s = sprintf('%d:%02d', floor(seconds / 60), mod(seconds, 60));
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
