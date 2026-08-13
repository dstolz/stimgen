classdef StimCalibration < handle & matlab.mixin.SetGet
    % obj = stimgen.StimCalibration(adapter)
    % obj = stimgen.StimCalibration()
    %
    % Calibration object that stimulus classes talk to.
    %
    % Thin wrapper around stimgen.calibration.Engine, exposing proxy properties
    % and methods so that stimgen.StimType continues to work without
    % modification. It is the serialized form of a calibration: a StimType
    % holds one, and toStruct/saveobj carry it into .spl banks and host
    % protocol files.
    %
    % This class is headless. The interactive front end is
    % stimgen.calibration.CalibrationGui, which drives the same Engine.
    %
    % Properties (delegated from Engine):
    %   CalibrationData, MicSensitivity, ReferenceLevel, ReferenceFrequency,
    %   NormativeValue, ExcitationSignalVoltage, ToneLutSource,
    %   CalibrationTimestamp, Fs
    %
    % Methods:
    %   compute_adjusted_voltage - Proxy to Engine; used by StimType.
    %   load_calibration         - Load .esgc file into Engine.
    %   save_calibration         - Save Engine data to .esgc file.
    %   design_filter            - Proxy to Engine; design equalization filter.
    %   filter_level_reference   - Proxy to Engine; level reference for
    %                              running the filter in hardware.
    %   test_filter              - Proxy to Engine; verify the filter flattens
    %                              the measured response.
    %   test_tones               - Proxy to Engine; verify the tone LUT
    %                              reproduces requested levels.
    %
    % See also: stimgen.calibration.Engine, stimgen.calibration.HwAdapter,
    %           stimgen.calibration.CalibrationGui,
    %           documentation/stimgen_StimCalibration.md

    properties (SetAccess = protected)
        Engine  stimgen.calibration.Engine  % core calibration engine
    end

    % --- Dependent pass-throughs so StimType sees familiar property names --
    properties (Dependent)
        CalibrationData
        MicSensitivity
        ReferenceLevel
        ReferenceFrequency
        NormativeValue
        ExcitationSignalVoltage
        ToneLutSource
        CalibrationTimestamp
        Fs
    end

    methods

        v = compute_adjusted_voltage(obj, type, value, level)  % Proxy to Engine.

        % ---------------------------------------------------------- %
        function obj = StimCalibration(adapter)
            % obj = StimCalibration()
            % obj = StimCalibration(adapter)
            %
            % Parameters:
            %   adapter - stimgen.calibration.HwAdapter connected to calibration
            %             hardware (optional; omit for offline use). The host
            %             application builds this, e.g. stimbridge.InterfaceAdapter.
            if nargin > 0 && ~isempty(adapter)
                mustBeA(adapter, 'stimgen.calibration.HwAdapter');
                obj.Engine = stimgen.calibration.Engine(adapter);
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
            S.ToneLutSource           = obj.ToneLutSource;
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
        end

        function v = get.ReferenceLevel(obj)
            v = obj.Engine.ReferenceLevel;
        end
        function set.ReferenceLevel(obj, r)
            obj.Engine.set_configuration(ReferenceLevel=r);
        end

        function v = get.ReferenceFrequency(obj)
            v = obj.Engine.ReferenceFrequency;
        end
        function set.ReferenceFrequency(obj, r)
            obj.Engine.set_configuration(ReferenceFrequency=r);
        end

        function v = get.NormativeValue(obj)
            v = obj.Engine.NormativeValue;
        end
        function set.NormativeValue(obj, r)
            obj.Engine.set_configuration(NormativeValue=r);
        end

        function v = get.ExcitationSignalVoltage(obj)
            v = obj.Engine.ExcitationVoltage;
        end
        function set.ExcitationSignalVoltage(obj, r)
            obj.Engine.set_configuration(ExcitationVoltage=r);
        end

        function v = get.ToneLutSource(obj)
            v = obj.Engine.ToneLutSource;
        end
        function set.ToneLutSource(obj, r)
            obj.Engine.set_configuration(ToneLutSource=r);
        end

        function v = get.CalibrationTimestamp(obj)
            v = obj.Engine.CalibrationTimestamp;
        end

        function v = get.Fs(obj)
            v = obj.Engine.Fs;
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
        function results = test_filter(obj, varargin)
            % results = test_filter(obj)
            % results = test_filter(obj, Name=Value)
            % Empirically verify the designed filter: play the sweep raw and
            % through the filter, and compare the flatness of the two measured
            % responses. Delegates to Engine, arguments and all; results are
            % stored in CalibrationData.filterTest.
            results = obj.Engine.test_filter(varargin{:});
        end

        % ---------------------------------------------------------- %
        function r = filter_level_reference(obj, varargin)
            % r = filter_level_reference(obj)
            % r = filter_level_reference(obj, x)
            % Level reference for running the equalization filter in
            % hardware, where nothing renormalizes after the FIR: the factor
            % that brings the filtered source to the NormativeValue level,
            % and the dB SPL the unscaled source produces at unity hardware
            % gain. x is a white-noise RMS in volts (default 1) or the
            % actual source waveform. Delegates to Engine, arguments and
            % all; see Engine.filter_level_reference.
            r = obj.Engine.filter_level_reference(varargin{:});
        end

        % ---------------------------------------------------------- %
        function results = test_tones(obj, varargin)
            % results = test_tones(obj)
            % results = test_tones(obj, freqs, levels, Name=Value)
            % Verify the tone lookup table: play discrete tones at the drive
            % voltages the LUT asks for and compare the levels that come back
            % to the ones requested. Delegates to Engine, arguments and all;
            % results are stored in CalibrationData.toneTest.
            results = obj.Engine.test_tones(varargin{:});
        end

        % ---------------------------------------------------------- %
        function results = test_clicks(obj, varargin)
            % results = test_clicks(obj)
            % results = test_clicks(obj, durs, levels, Name=Value)
            % Verify the click lookup table: play clicks at the drive voltages
            % the LUT asks for and compare the levels that come back to the
            % ones requested. Delegates to Engine, arguments and all; results
            % are stored in CalibrationData.clickTest.
            results = obj.Engine.test_clicks(varargin{:});
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
        end

        function save_calibration(obj, ffn)
            % save_calibration(obj)
            % save_calibration(obj, ffn)
            % Save Engine calibration data to a .esgc file.
            if nargin < 2, ffn = ''; end
            obj.Engine.save(ffn);
        end

    end  % public methods

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
