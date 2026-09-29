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
    % A MICROPHONE RECORD IS SHOWN AS SOUND. When the object is a
    % stimgen.CapturedSignal carrying a microphone sensitivity, every plot and
    % readout switches to sound pressure: the waveform in pascals, the
    % envelope, spectrum, spectrogram, harmonics and band levels in dB SPL,
    % and a Sound Level tab with what a sound level meter would read (Z/A/C
    % weighted Leq, peak, Fast/Slow maximum and exposure level, plus the
    % peak-equivalent levels clicks are specified in). A capture also brings
    % its noise floor -- the silence recorded before the stimulus -- which is
    % drawn under the spectrum and the bands and turned into an SNR, and the
    % level its stimulus asked for, which is compared with the level that came
    % back, measured the way the stimulus's calibration table was measured
    % (stimgen.util.level_as_calibrated). The Units control switches the same
    % record back to volts, which is the view for input-stage headroom. Every
    % dB SPL on screen goes through stimgen.calibration.Engine.volts_to_spl.
    % A generated stimulus has no sensitivity and is shown exactly as before.
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
    %   StimObj     - stimgen.StimType currently displayed ([] when none)
    %   Label       - display label for that stimulus
    %   Metrics     - struct returned by the most recent signal_metrics call
    %   Scale       - how the record is being read: Available (a sensitivity
    %                 came with it), Acoustic (shown in Pa/dB SPL now), and
    %                 MicSensitivity (V/Pa, NaN when none)
    %   SoundLevels - stimgen.util.sound_levels readouts of the displayed
    %                 record, in the current units ([] until needed)
    %
    % See also: stimgen.StimPlayer, stimgen.StimType, stimgen.CapturedSignal,
    %           stimgen.util.sound_levels

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

        % How the displayed record is read. Acoustic is the view actually on
        % screen; Available says whether it could be (a sensitivity came
        % with the record), so the two differ only when the Units control
        % has asked for volts.
        Scale (1,1) struct = struct('Available', false, 'Acoustic', false, ...
            'MicSensitivity', NaN)

        SoundLevels = []                % stimgen.util.sound_levels result, or []
    end

    % --- Private ---
    properties (Access = private)
        SourceFcn = []                  % function_handle -> [stimObj, label], or []
        Figure                          % uifigure handle
        handles struct = struct()       % UI component handles
        Signal_ (1,:) double = []       % Cached copy of the displayed waveform
        Fs_     (1,1) double = 1        % Sample rate of Signal_ (Hz)

        % The Units choice. Kept apart from Scale.Acoustic so that stepping
        % through records that have no sensitivity does not forget it.
        PreferAcoustic_ (1,1) logical = true

        % What a stimgen.CapturedSignal brings besides its samples; empty
        % for anything else. See read_capture_.
        Noise_    (1,:) double = []     % silence before the stimulus (V)
        NoiseRms_ (1,1) double = NaN    % rms of all the silence acquired (V)
        Request_  (1,1) struct = struct() % stimgen.util.level_request + spectral settings
        Warnings_ (1,:) string = string.empty(1, 0)
        Provenance_ (1,1) struct = struct()

        NoiseLevels_  = []              % sound_levels of Noise_, or []
        AsCalibrated_ = []              % level_as_calibrated result, or []
    end

    properties (Constant)
        NHarmonics = 6      % Harmonics included in the THD estimate
        MaxPlotPoints = 2e4 % Waveform points drawn before min/max decimation
        WarningsHeight = 120 % Pixels given to a recording's warning list
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
        function set_units(obj, units)
            % set_units(obj, "acoustic" | "electrical")
            % Show a microphone record as sound pressure (Pa, dB SPL) or as
            % the voltage it arrived as (V, dB re 1 V).
            %
            % "acoustic" is a preference, not a promise: a record with no
            % sensitivity has no pressure scale and stays in volts, and the
            % preference applies again to the next record that does.
            arguments
                obj (1,1) stimgen.StimInspector
                units (1,1) string {mustBeMember(units, ["acoustic", "electrical"])}
            end
            obj.PreferAcoustic_ = units == "acoustic";
            obj.refresh();
        end

        % -----------------------------------------------------------------
        function read_capture_(obj, stimObj)
            % read_capture_(stimObj) - Take the scale and the capture context.
            % Everything a stimgen.CapturedSignal carries besides its
            % samples, and the Scale that follows from it; empty for any
            % other stimulus. Clears every cache computed on the last record.
            sens  = NaN;
            noise = [];
            nrms  = NaN;
            req   = struct();
            warns = string.empty(1, 0);
            prov  = struct();
            if isa(stimObj, 'stimgen.CapturedSignal') && isvalid(stimObj)
                if stimObj.has_spl_scale()
                    sens = stimObj.MicSensitivity;
                end
                noise = stimObj.NoiseRecord;
                nrms  = stimObj.NoiseRms;
                req   = stimObj.Request;
                warns = stimObj.Warnings;
                prov  = stimObj.Provenance;
            end

            available = isfinite(sens) && sens > 0;
            obj.Scale = struct('Available', available, ...
                'Acoustic', available && obj.PreferAcoustic_, ...
                'MicSensitivity', sens);
            obj.Noise_       = noise;
            obj.NoiseRms_    = nrms;
            obj.Request_     = req;
            obj.Warnings_    = warns;
            obj.Provenance_  = prov;
            obj.SoundLevels  = [];
            obj.NoiseLevels_ = [];
            obj.AsCalibrated_ = [];

            h = obj.handles;
            if isfield(h, 'UnitsDD') && isvalid(h.UnitsDD)
                h.UnitsDD.Enable = matlab.lang.OnOffSwitchState(available);
                if obj.Scale.Acoustic
                    h.UnitsDD.Value = "acoustic";
                else
                    h.UnitsDD.Value = "electrical";
                end
            end
        end

        % -----------------------------------------------------------------
        function tf = is_capture_(obj)
            % tf = is_capture_() - True when the displayed object is a recording.
            tf = ~isempty(obj.StimObj) && isa(obj.StimObj, 'stimgen.CapturedSignal') ...
                && isvalid(obj.StimObj);
        end

        % -----------------------------------------------------------------
        function sens = display_sensitivity_(obj)
            % sens = display_sensitivity_() - V/Pa in force on screen, NaN in volts.
            if obj.Scale.Acoustic
                sens = obj.Scale.MicSensitivity;
            else
                sens = NaN;
            end
        end

        % -----------------------------------------------------------------
        function L = to_db_(obj, v)
            % L = to_db_(v) - Linear amplitude(s) as the level on screen.
            % dB SPL through stimgen.calibration.Engine.volts_to_spl -- the
            % package's one conversion -- when the record is shown as sound,
            % dB re 1 otherwise. v is an rms amplitude (or a peak, for a
            % peak level); any shape, returned in the same shape.
            sz = size(v);
            v  = reshape(double(v), 1, []);
            if obj.Scale.Acoustic
                L = stimgen.calibration.Engine.volts_to_spl(v, obj.Scale.MicSensitivity);
            else
                L = 20 * log10(max(v, 0));
            end
            L = reshape(L, sz);
        end

        % -----------------------------------------------------------------
        function S = sound_levels_(obj)
            % S = sound_levels_() - Meter readouts of the displayed record.
            % Computed on first use and kept until the record or the units
            % change, since the metrics table and the Sound Level tab both
            % read them.
            if isempty(obj.SoundLevels)
                obj.SoundLevels = stimgen.util.sound_levels(obj.Signal_, obj.Fs_, ...
                    obj.display_sensitivity_());
            end
            S = obj.SoundLevels;
        end

        % -----------------------------------------------------------------
        function S = noise_levels_(obj)
            % S = noise_levels_() - Meter readouts of the capture's noise floor.
            % [] when the record brought no silence with it.
            if isempty(obj.NoiseLevels_) && numel(obj.Noise_) >= 8
                obj.NoiseLevels_ = stimgen.util.sound_levels(obj.Noise_, obj.Fs_, ...
                    obj.display_sensitivity_());
            end
            S = obj.NoiseLevels_;
        end

        % -----------------------------------------------------------------
        function m = as_calibrated_(obj)
            % m = as_calibrated_() - The record measured as its stimulus was calibrated.
            % [] when nothing is known about the stimulus. The spectral
            % options are the calibration's own, carried in the request, so a
            % tone is measured exactly as its table was.
            if ~isempty(obj.AsCalibrated_)
                m = obj.AsCalibrated_;
                return
            end
            m = [];
            req = obj.Request_;
            if ~isfield(req, 'mode') || isempty(obj.Signal_)
                return
            end
            spec = stimgen.calibration.SpectralOptions();
            try
                if isfield(req, 'spectral_window')
                    spec = stimgen.calibration.SpectralOptions( ...
                        req.spectral_window, req.spectral_fft_length);
                end
            catch
                % A request from another version; the default is what an
                % unconfigured engine measures with.
            end
            m = stimgen.util.level_as_calibrated(obj.Signal_, obj.Fs_, req, ...
                obj.display_sensitivity_(), spec);
            obj.AsCalibrated_ = m;
        end

        % -----------------------------------------------------------------
        function export_(obj)
            % export_() - Copy the displayed signal and metrics to the base workspace.
            % A recording shown as sound also brings its scale and every
            % calibrated readout, so the numbers on screen travel with it.
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
                if obj.is_capture_()
                    S.units           = string(obj.sound_levels_().Unit);
                    S.mic_sensitivity = obj.Scale.MicSensitivity;
                    S.sound_levels    = obj.sound_levels_();
                    S.noise_levels    = obj.noise_levels_();
                    S.as_calibrated   = obj.as_calibrated_();
                    S.request         = obj.Request_;
                    S.warnings        = obj.Warnings_;
                end
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
