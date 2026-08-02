classdef StimInspector < handle

    % obj = stimgen.StimInspector
    % obj = stimgen.StimInspector(stimObj)
    % obj = stimgen.StimInspector(stimObj, label)
    % Detailed inspection window for a single stimgen stimulus.
    %
    % Developer guide: documentation/stimgen_StimInspector.md
    %
    % Shows the waveform, envelope, magnitude spectrum, spectrogram and
    % harmonic-distortion breakdown of one stimgen.StimType object, together
    % with a table of time/spectral/distortion metrics and the stimulus
    % parameter values that produced them.
    %
    % The window is read-only: it never writes to the stimulus, and never
    % advances the variant cycle (all values are read either from the already
    % generated Signal or from raw properties).
    %
    % Usage:
    %   t = stimgen.Tone; t.update_signal;
    %   stimgen.StimInspector(t);              % inspect one object
    %
    %   % Live-following: hand it a provider that returns the object to show.
    %   insp = stimgen.StimInspector;
    %   insp.set_source_provider(@() deal(stimObj, "my stim"));
    %   insp.refresh                            % re-reads through the provider
    %
    % stimgen.StimPlayer uses the provider form so the window tracks the bank
    % selection, the parameter edits and the variant combination step.
    %
    % Properties (read-only):
    %   StimObj - stimgen.StimType currently displayed ([] when none)
    %   Label   - display label for that stimulus
    %   Metrics - struct returned by the most recent signal_metrics call
    %
    % See also: stimgen.StimPlayer, stimgen.StimType

    % --- External method declarations ---
    % Trailing-underscore methods are helpers; they are public only so GUI
    % callbacks can reach them (same convention as stimgen.StimPlayer).
    methods
        refresh(obj)
        build_ui_(obj)
        update_info_(obj, stimObj, M)
        update_plots_(obj, M)
    end

    methods (Static)
        M = signal_metrics(y, fs, nHarmonics)
    end

    % --- Public read-only state ---
    properties (SetAccess = private)
        StimObj                         % stimgen.StimType being displayed, or []
        Label   (1,1) string = ""       % Display label for the stimulus
        Metrics (1,1) struct = struct() % Most recent signal_metrics result
    end

    % --- Private ---
    properties (Access = private)
        SourceFcn = []                  % function_handle -> [stimObj, label], or []
        Figure                          % uifigure handle
        handles struct = struct()       % UI component handles
        Signal_ (1,:) double = []       % Cached copy of the displayed waveform
        Fs_     (1,1) double = 1        % Sample rate of Signal_ (Hz)
    end

    properties (Constant)
        NHarmonics = 6      % Harmonics included in the THD estimate
        MaxPlotPoints = 2e4 % Waveform points drawn before min/max decimation
    end

    % =====================================================================
    methods

        function obj = StimInspector(stimObj, label)
            % obj = stimgen.StimInspector
            % obj = stimgen.StimInspector(stimObj)
            % obj = stimgen.StimInspector(stimObj, label)
            % Build the inspector window, optionally on a given stimulus.
            %
            % Parameters:
            %   stimObj - stimgen.StimType to inspect (optional)
            %   label   - display label for that stimulus (optional)
            arguments
                stimObj = []
                label (1,1) string = ""
            end

            if ~isempty(stimObj)
                mustBeA(stimObj, 'stimgen.StimType');
            end

            obj.build_ui_();

            if isempty(stimObj)
                obj.refresh();
            else
                obj.set_source(stimObj, label);
            end

            if nargout == 0, clear obj; end
        end

        % -----------------------------------------------------------------
        function delete(obj)
            % Destructor: close the window without re-entering delete().
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                obj.Figure.DeleteFcn = '';
                delete(obj.Figure);
            end
        end

        % -----------------------------------------------------------------
        function set_source(obj, stimObj, label)
            % set_source(obj, stimObj)
            % set_source(obj, stimObj, label)
            % Display a specific stimulus object and drop any source provider.
            %
            % Parameters:
            %   stimObj - stimgen.StimType to inspect, or [] to clear
            %   label   - display label (optional)
            arguments
                obj (1,1) stimgen.StimInspector
                stimObj
                label (1,1) string = ""
            end

            if ~isempty(stimObj)
                mustBeA(stimObj, 'stimgen.StimType');
            end

            obj.SourceFcn = [];
            obj.StimObj   = stimObj;
            obj.Label     = label;
            obj.refresh();
        end

        % -----------------------------------------------------------------
        function set_source_provider(obj, fcn)
            % set_source_provider(obj, fcn)
            % Track whatever stimulus a caller-supplied function returns.
            %
            % Parameters:
            %   fcn - function handle called as [stimObj, label] = fcn().
            %         Returning an empty stimObj clears the display.
            arguments
                obj (1,1) stimgen.StimInspector
                fcn (1,1) function_handle
            end

            obj.SourceFcn = fcn;
            obj.refresh();
        end

        % -----------------------------------------------------------------
        function show(obj)
            % show(obj) - Bring the inspector window to the foreground.
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                figure(obj.Figure);
            end
        end

        % -----------------------------------------------------------------
        function tf = is_open(obj)
            % tf = is_open(obj) - True while the inspector window exists.
            tf = isvalid(obj) && ~isempty(obj.Figure) && isvalid(obj.Figure);
        end

        % -----------------------------------------------------------------
        function [stimObj, label] = resolve_source_(obj)
            % [stimObj, label] = resolve_source_() - Resolve the stimulus to display.
            % Consults the source provider when one is attached, otherwise
            % returns the object handed to set_source.

            stimObj = [];
            label   = obj.Label;

            if ~isempty(obj.SourceFcn)
                try
                    [stimObj, label] = obj.SourceFcn();
                catch ME
                    stimgen.util.vprintf(1, 1, ...
                        'StimInspector: source provider failed: %s', ME.message);
                    stimObj = [];
                    label   = "";
                end
                if ~isa(stimObj, 'stimgen.StimType') || ~isscalar(stimObj) || ~isvalid(stimObj)
                    stimObj = [];
                end
                obj.StimObj = stimObj;
                obj.Label   = string(label);
                label       = obj.Label;
                return
            end

            if ~isempty(obj.StimObj) && isvalid(obj.StimObj)
                stimObj = obj.StimObj;
            end
        end

        % -----------------------------------------------------------------
        function set_status_(obj, messageText, options)
            % set_status_(messageText) - Update the status label.
            arguments
                obj (1,1) stimgen.StimInspector
                messageText (1,1) string
                options.isError (1,1) logical = false
            end

            h = obj.handles;
            if ~isfield(h, 'StatusLabel') || isempty(h.StatusLabel) || ~isvalid(h.StatusLabel)
                return
            end

            h.StatusLabel.Text = char(messageText);
            if options.isError
                h.StatusLabel.FontColor = [0.75 0.15 0.15];
            else
                h.StatusLabel.FontColor = [0.35 0.35 0.35];
            end
        end

        % -----------------------------------------------------------------
        function play_(obj)
            % play_() - Audition the displayed waveform through the sound card.
            if isempty(obj.StimObj) || ~isvalid(obj.StimObj) || isempty(obj.Signal_)
                obj.set_status_("Nothing to play.");
                return
            end
            try
                obj.set_status_("Playing...");
                drawnow limitrate
                obj.StimObj.play();
                obj.set_status_("Playback finished.");
            catch ME
                stimgen.util.vprintf(0, 1, 'StimInspector: playback failed.');
                stimgen.util.vprintf(0, 1, ME);
                obj.set_status_("Playback failed: " + string(ME.message), isError=true);
            end
        end

        % -----------------------------------------------------------------
        function export_(obj)
            % export_() - Copy the displayed signal and metrics to the base workspace.
            if isempty(obj.Signal_)
                obj.set_status_("Nothing to export.");
                return
            end
            try
                S = struct( ...
                    'label',   obj.Label, ...
                    'class',   string(class(obj.StimObj)), ...
                    'Fs',      obj.Fs_, ...
                    'signal',  obj.Signal_, ...
                    'metrics', obj.Metrics);
                assignin('base', 'stimInfo', S);
                stimgen.util.vprintf(1, ...
                    'StimInspector: exported signal and metrics to workspace variable ''stimInfo''.\n');
                obj.set_status_("Exported signal and metrics to workspace variable 'stimInfo'.");
            catch ME
                stimgen.util.vprintf(0, 1, ME);
                obj.set_status_("Export failed: " + string(ME.message), isError=true);
            end
        end

    end % methods (public)

end
