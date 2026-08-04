classdef StimCalibration < handle & matlab.mixin.SetGet
    % obj = stimgen.StimCalibration(adapter, parent)
    % obj = stimgen.StimCalibration()
    %
    % GUI controller for SPL-to-voltage calibration.
    %
    % Thin wrapper around stimgen.calibration.Engine. Owns the GUI state
    % machine and exposes proxy properties and methods so that
    % stimgen.StimType continues to work without modification.
    %
    % When constructed without arguments the object is in offline mode and
    % can load a .esgc file for use by StimType. When an adapter is supplied
    % the calibration GUI is launched against that hardware.
    %
    % Plotting is delegated to a stimgen.calibration.LiveMonitor attached to
    % axes inside the GUI window, so a sweep's waveform, spectrum and transfer
    % curve fill in beside the controls driving it. Nothing in this class
    % draws.
    %
    % Properties (delegated from Engine):
    %   CalibrationData, MicSensitivity, ReferenceLevel, ReferenceFrequency,
    %   NormativeValue, ExcitationSignalVoltage, CalibrationTimestamp
    %
    % Methods:
    %   gui                      - Launch calibration GUI.
    %   refresh_plots            - Redraw the panels from the Engine's state.
    %   compute_adjusted_voltage - Proxy to Engine; used by StimType.
    %   load_calibration         - Load .esgc file into Engine.
    %   save_calibration         - Save Engine data to .esgc file.
    %
    % See also: stimgen.calibration.Engine, stimgen.calibration.HwAdapter,
    %           stimgen.calibration.LiveMonitor,
    %           documentation/stimgen_StimCalibration.md

    properties (SetAccess = protected)
        Engine  stimgen.calibration.Engine  % core calibration engine
        Monitor stimgen.calibration.LiveMonitor  % live plot renderer; empty until gui()
    end

    properties (SetAccess = private, SetObservable, AbortSet)
        STATE (1,1) string {mustBeMember(STATE,["IDLE","REFERENCE","CALIBRATE"])} = "IDLE"
    end

    properties (SetAccess = protected, Hidden)
        handles
    end

    % --- Dependent pass-throughs so StimType sees familiar property names --
    properties (Dependent)
        CalibrationData
        MicSensitivity
        ReferenceLevel
        ReferenceFrequency
        NormativeValue
        ExcitationSignalVoltage
        CalibrationTimestamp
        Fs
    end

    methods

        gui(obj)  % Launch calibration GUI.
        refresh_plots(obj)  % Redraw the monitor panels from the Engine's state.
        v = compute_adjusted_voltage(obj, type, value, level)  % Proxy to Engine.

        % ---------------------------------------------------------- %
        function obj = StimCalibration(adapter, parent)
            % obj = StimCalibration()
            % obj = StimCalibration(adapter)
            % obj = StimCalibration(adapter, parent)
            %
            % Parameters:
            %   adapter - stimgen.calibration.HwAdapter connected to calibration
            %             hardware (optional; omit for offline use). The host
            %             application builds this, e.g. stimbridge.InterfaceAdapter.
            %   parent  - UI parent container (optional)
            obj.handles.parent = [];
            if nargin > 1
                obj.handles.parent = parent;
            end

            if nargin > 0 && ~isempty(adapter)
                mustBeA(adapter, 'stimgen.calibration.HwAdapter');
                obj.Engine = stimgen.calibration.Engine(adapter);
                obj.gui();
            else
                obj.Engine = stimgen.calibration.Engine();
            end
        end

        % ---------------------------------------------------------- %
        function S = toStruct(obj)
            % S = toStruct(obj)
            % Serialize to a plain struct for protocol persistence.
            S                         = struct;
            S.Class                   = "stimgen.StimCalibration";
            S.CalibrationData         = obj.CalibrationData;
            S.MicSensitivity          = obj.MicSensitivity;
            S.NormativeValue          = obj.NormativeValue;
            S.ReferenceLevel          = obj.ReferenceLevel;
            S.ReferenceFrequency      = obj.ReferenceFrequency;
            S.ExcitationSignalVoltage = obj.ExcitationSignalVoltage;
            S.CalibrationTimestamp    = obj.CalibrationTimestamp;
            S.Fs                      = obj.Fs;
        end

        % ---------------------------------------------------------- %
        % Dependent property accessors — all delegate to Engine

        function v = get.CalibrationData(obj)
            v = obj.Engine.CalibrationData;
        end

        function v = get.MicSensitivity(obj)
            v = obj.Engine.MicSensitivity;
        end
        function set.MicSensitivity(obj, r)
            obj.Engine.set_configuration(MicSensitivity=r);
            obj.sync_gui_field_('MicSensitivity', r);
        end

        function v = get.ReferenceLevel(obj)
            v = obj.Engine.ReferenceLevel;
        end
        function set.ReferenceLevel(obj, r)
            obj.Engine.set_configuration(ReferenceLevel=r);
            obj.sync_gui_field_('ReferenceLevel', r);
        end

        function v = get.ReferenceFrequency(obj)
            v = obj.Engine.ReferenceFrequency;
        end
        function set.ReferenceFrequency(obj, r)
            obj.Engine.set_configuration(ReferenceFrequency=r);
            obj.sync_gui_field_('ReferenceFrequency', r);
        end

        function v = get.NormativeValue(obj)
            v = obj.Engine.NormativeValue;
        end
        function set.NormativeValue(obj, r)
            obj.Engine.set_configuration(NormativeValue=r);
            obj.sync_gui_field_('NormativeValue', r);
        end

        function v = get.ExcitationSignalVoltage(obj)
            v = obj.Engine.ExcitationVoltage;
        end
        function set.ExcitationSignalVoltage(obj, r)
            obj.Engine.set_configuration(ExcitationVoltage=r);
            obj.sync_gui_field_('ExcitationSignalVoltage', r);
        end

        function v = get.CalibrationTimestamp(obj)
            v = obj.Engine.CalibrationTimestamp;
        end

        function v = get.Fs(obj)
            v = obj.Engine.Fs;
        end

        % ---------------------------------------------------------- %
        function set_prop(obj, src, ~)
            % Callback from GUI numeric fields: src.Tag names the Engine property.
            % ExcitationSignalVoltage is a special case (maps to Engine.ExcitationVoltage).
            %
            % Engine parameters are SetAccess = protected, so the write has to
            % go through set_configuration -- that is also what runs the
            % property validators. A rejected value is rolled back in the
            % widget so the GUI cannot drift out of sync with the Engine.
            tag = src.Tag;
            if strcmp(tag, 'ExcitationSignalVoltage')
                name = 'ExcitationVoltage';
            else
                name = tag;
            end

            try
                obj.Engine.set_configuration(name, src.Value);
            catch ME
                src.Value = obj.Engine.(name);
                stimgen.util.vprintf(0, 2, ME);
            end
        end

        % ---------------------------------------------------------- %
        function calibration_state(obj, ~, ~)
            % STATE PostSet listener — orchestrates Engine calls and GUI state.
            h   = obj.handles;
            hen = findobj(h.parent, '-property', 'Enable');

            % Axes carry an Enable property of their own; greying them out
            % along with the controls would blank the live plots for exactly
            % the duration of the run they exist to show.
            hen = hen(~isa(hen, 'matlab.graphics.axis.AbstractAxes'));

            switch obj.STATE
                case "IDLE"
                    set(hen, 'Enable', 'on');
                    h.RefMeasure.Text    = 'Measure Reference';
                    h.RunCalibration.Text = 'Calibrate';

                case "REFERENCE"
                    set(hen, 'Enable', 'off');
                    h.RefMeasure.Enable = 'on';
                    h.RefMeasure.Text   = 'Stop';
                    if isfield(h, 'RefMeasureTool'), h.RefMeasureTool.Enable = 'on'; end
                    drawnow;

                    try
                        obj.Engine.calibrate_reference();
                        obj.sync_gui_field_('MicSensitivity', obj.Engine.MicSensitivity);
                    catch ME
                        set(hen, 'Enable', 'on');
                        h.RefMeasure.Text = 'REFERENCING ERROR';
                        stimgen.util.vprintf(0, 2, ME);
                        obj.STATE = "IDLE";
                        return;
                    end

                    set(hen, 'Enable', 'on');
                    h.RefMeasure.Text = 'Measure Reference';
                    obj.refresh_plots();
                    obj.STATE = "IDLE";

                case "CALIBRATE"
                    set(hen, 'Enable', 'off');
                    h.RunCalibration.Enable = 'on';
                    h.RunCalibration.Text   = 'Stop';
                    if isfield(h, 'RunCalibrationTool'), h.RunCalibrationTool.Enable = 'on'; end
                    drawnow;

                    try
                        % No timestamp write here: CalibrationTimestamp is
                        % SetAccess = protected, and calibrate_clicks/
                        % calibrate_tones each stamp it on success anyway.
                        obj.Engine.calibrate_clicks();
                        obj.Engine.calibrate_tones();
                        h.MenuSaveCalibration.Enable = 'on';
                    catch ME
                        set(hen, 'Enable', 'on');
                        h.RunCalibration.Text            = {'CALIBRATION','ERROR'};
                        h.RunCalibration.BackgroundColor = 'r';
                        stimgen.util.vprintf(0, 2, ME);
                        obj.STATE = "IDLE";
                        return;
                    end
                    set(hen, 'Enable', 'on');
                    h.RunCalibration.Text = 'Calibrate';
                    obj.refresh_plots();
                    obj.STATE = "IDLE";
            end
            drawnow;
        end

        % ---------------------------------------------------------- %
        function design_filter(obj, varargin)
            % design_filter(obj)
            % design_filter(obj, source, Name=Value)
            % Design equalization FIR filter from a completed tone or swept
            % sine calibration. Delegates to Engine, arguments and all, so the
            % design options documented there apply here unchanged. Results are
            % stored in CalibrationData.filter.
            obj.Engine.design_filter(varargin{:});
        end

        % ---------------------------------------------------------- %
        function measure_ref(obj, ~, ~)
            if obj.STATE == "REFERENCE"
                obj.STATE = "IDLE";
            else
                obj.STATE = "REFERENCE";
            end
        end

        function run_calibration(obj, ~, ~)
            if obj.STATE == "CALIBRATE"
                obj.STATE = "IDLE";
            else
                obj.STATE = "CALIBRATE";
            end
        end

        % ---------------------------------------------------------- %
        function load_calibration(obj, ffn)
            % load_calibration(obj)
            % load_calibration(obj, ffn)
            % Load a .esgc calibration file into the Engine.
            %
            % Old .sgc files are not supported; please recalibrate.
            if nargin < 2, ffn = ''; end
            eng = stimgen.calibration.Engine.load(ffn);
            if isempty(eng), return; end
            obj.Engine = eng;

            % The monitor follows an engine, not this object, so a load that
            % swaps the engine has to move it across or it would keep
            % rendering the discarded one.
            if ~isempty(obj.Monitor) && isvalid(obj.Monitor)
                obj.Monitor.attach(obj.Engine);
            end

            % Sync GUI fields to loaded values, and move the mirroring
            % listeners onto the engine that just replaced the old one.
            if isfield(obj.handles, 'EngineListeners')
                obj.attach_engine_listeners_();
                obj.sync_gui_field_('MicSensitivity',      obj.Engine.MicSensitivity);
                obj.sync_gui_field_('ReferenceLevel',      obj.Engine.ReferenceLevel);
                obj.sync_gui_field_('ReferenceFrequency',  obj.Engine.ReferenceFrequency);
                obj.sync_gui_field_('NormativeValue',      obj.Engine.NormativeValue);
                obj.sync_gui_field_('ExcitationSignalVoltage', obj.Engine.ExcitationVoltage);
                obj.sync_gui_field_('MaxOutputVoltage',    obj.Engine.MaxOutputVoltage);
                obj.sync_gui_field_('ShowLivePlots',       obj.Engine.ShowLivePlots);
            end

            obj.refresh_plots();

            f = ancestor(obj.handles.parent, 'figure');
            if ~isempty(f), figure(f); end
        end

        function save_calibration(obj, ffn)
            % save_calibration(obj)
            % save_calibration(obj, ffn)
            % Save Engine calibration data to a .esgc file.
            if nargin < 2, ffn = ''; end
            obj.Engine.save(ffn);
            f = ancestor(obj.handles.parent, 'figure');
            if ~isempty(f), figure(f); end
        end

        % ---------------------------------------------------------- %
        function delete(obj)
            % Release everything holding a listener on the engine: a StimType
            % may keep using that engine long after this object is gone.
            if ~isempty(obj.Monitor) && isvalid(obj.Monitor)
                obj.Monitor.detach();
                delete(obj.Monitor);
            end
            if isfield(obj.handles, 'EngineListeners')
                delete(obj.handles.EngineListeners);
            end
        end

    end  % public methods

    % ------------------------------------------------------------------ %
    methods (Access = private)
        build_plots_(obj, parent)  % Create the plot panel and its LiveMonitor.

        function set_log_x_(obj, tf)
            % Switch the transfer panel between log and linear frequency, then
            % redraw so the change is visible without waiting for a run.
            if isempty(obj.Monitor) || ~isvalid(obj.Monitor)
                return
            end
            obj.Monitor.LogX = tf;
            obj.refresh_plots();
        end

        function attach_engine_listeners_(obj)
            % attach_engine_listeners_(obj)
            % Mirror the Engine's parameters into the widgets.
            %
            % The engine writes some of these itself -- calibrate_reference
            % replaces MicSensitivity -- and a host application can call
            % set_configuration directly. Relying on every writer to also
            % update the GUI is what let the fields drift out of step with the
            % engine they claim to show; the properties are SetObservable, so
            % listening is both cheaper and complete.
            %
            % Re-registered by load_calibration, which swaps the engine out
            % from under the listeners.
            map = { ...
                'MicSensitivity',     'MicSensitivity'; ...
                'ReferenceLevel',     'ReferenceLevel'; ...
                'ReferenceFrequency', 'ReferenceFrequency'; ...
                'NormativeValue',     'NormativeValue'; ...
                'ExcitationVoltage',  'ExcitationSignalVoltage'; ...
                'MaxOutputVoltage',   'MaxOutputVoltage'; ...
                'ShowLivePlots',      'ShowLivePlots'};

            if isfield(obj.handles, 'EngineListeners')
                delete(obj.handles.EngineListeners);
            end

            L = cell(1, size(map, 1));
            for k = 1:size(map, 1)
                prop = map{k, 1};
                tag  = map{k, 2};
                L{k} = addlistener(obj.Engine, prop, 'PostSet', ...
                    @(~,~) obj.sync_gui_field_(tag, obj.Engine.(prop)));
            end
            obj.handles.EngineListeners = [L{:}];
        end

        function sync_gui_field_(obj, tag, value)
            % sync_gui_field_(obj, tag, value)
            % Update a GUI control identified by handles.(tag) if it exists.
            if isempty(obj.handles) || ~isfield(obj.handles, tag)
                return;
            end
            h = obj.handles.(tag);
            if ~isvalid(h) || ~isprop(h, 'Value')
                return;
            end

            % A numeric field's Limits are a tighter guard on typed input than
            % the engine's own validators, so an engine-legal value can still
            % be one this widget refuses. Assigning it would throw from inside
            % a PostSet listener and take the caller down with it, which for a
            % listener attached to a running sweep means losing the run.
            if isprop(h, 'Limits') && isnumeric(value) && isscalar(value) ...
                    && (value < h.Limits(1) || value > h.Limits(2))
                stimgen.util.vprintf(2, ...
                    'StimCalibration: %s = %g is outside the field limits [%g %g]; not displayed.', ...
                    tag, value, h.Limits(1), h.Limits(2));
                return;
            end

            h.Value = value;
        end
    end

    % ------------------------------------------------------------------ %
    methods
        function s = saveobj(obj)
            % Serialize for MATLAB session saves.
            s.CalibrationData        = obj.Engine.CalibrationData;
            s.MicSensitivity         = obj.Engine.MicSensitivity;
            s.NormativeValue         = obj.Engine.NormativeValue;
            s.ReferenceLevel         = obj.Engine.ReferenceLevel;
            s.ReferenceFrequency     = obj.Engine.ReferenceFrequency;
            s.ExcitationSignalVoltage = obj.Engine.ExcitationVoltage;
            s.CalibrationTimestamp   = obj.Engine.CalibrationTimestamp;
        end
    end

    methods (Static)
        function obj = loadobj(s)
            % Restore from a MATLAB session save struct.
            obj = stimgen.StimCalibration();  % offline, no adapter
            if isstruct(s)
                % Engine measurement properties are SetAccess = protected, so
                % they cannot be assigned from here; restore() is the
                % supported entry point and tolerates a partial struct.
                obj.Engine.restore(s);
            end
        end
    end

end
