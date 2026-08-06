classdef LiveMonitor < handle
    % stimgen.calibration.LiveMonitor
    % Renderer for the stimgen.calibration.Engine LiveUpdate event stream.
    %
    % Draws three panels while a calibration runs: the acquired waveform with
    % the analysed span and clipping limits, its spectrum in dB SPL with
    % harmonic markers and the previous measurement as a ghost, and the partial
    % transfer curve with across-repeat spread, the required drive voltage, and
    % run progress.
    %
    % Graphics objects are created once and then updated in place, so a long
    % sweep does not rebuild the axes on every measurement. Updates are
    % rate-limited to MinInterval seconds; the final update of a run always
    % renders. Long records are drawn as a min/max envelope and spectra are
    % peak-held onto a log grid, which keeps redraw cost flat regardless of
    % record length.
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
        ShowGhost   (1,1) logical = true   % overlay the previous spectrum
        ShowVoltage (1,1) logical = true   % required-drive-voltage axis on the transfer plot
        LogX        (1,1) logical = true   % log x-axis on the transfer plot
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
        PrevSpectrum_ (1,2) cell = {[], []}  % {f, level} of the previous measurement
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
    end

    methods (Static, Access = private)
        [t, y] = envelope_decimate_(y, fs, maxPoints)   % Min/max envelope for display.
        [f, lvl] = spectrum_db_spl_(y, fs, refLevel, micSens, nBins)  % dB SPL spectrum on a log grid.

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
                case "click",      s = 'Click sweep';
                case "swept_sine", s = 'Swept sine';
                case "filter_test", s = 'Filter test';
                case "tone_test",  s = 'Tone LUT test';
                case "reference",  s = 'Reference';
                otherwise,         s = char(stage);
            end
        end
    end
end
