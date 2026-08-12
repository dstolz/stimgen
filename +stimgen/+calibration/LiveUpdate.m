classdef LiveUpdate < event.EventData
    % stimgen.calibration.LiveUpdate
    % Payload broadcast by the stimgen.calibration.Engine LiveUpdate event.
    %
    % One immutable snapshot of an in-progress calibration: the waveform just
    % acquired, the span of it that was actually measured, the run's partial
    % lookup table, and the scalar metrics computed from that measurement.
    % Consumers render it; nothing here touches graphics, so a host application
    % can log or forward the stream instead of plotting it.
    %
    % Properties:
    %   Stage        - "reference" | "background" | "latency" | "tone" |
    %                  "click" | "swept_sine" | "tone_test" | "filter_test" |
    %                  "manual"
    %   Phase        - "start" | "measure" | "done"
    %   Fs           - sample rate of Excitation/Response (Hz)
    %   Excitation   - excitation waveform sent to the hardware (V)
    %   Response     - microphone response recorded for it (V)
    %   Span         - [first last] sample index into Response that the
    %                  measurement was computed over; [] means the whole record
    %   Markers      - frequencies of interest (Hz), e.g. [f0 2*f0 3*f0]
    %   MarkerLabels - one label per marker
    %   Table        - partial LUT: x, measurement, spl_db, voltage, sd_db.
    %                  NaN at points not yet measured
    %   XLabel       - axis label for Table.x, already in display units
    %   XScale       - "log" | "linear" for the Table.x axis
    %   XFactor      - multiply Table.x by this to reach display units
    %   Index/Total  - point being measured, and how many there are
    %   Repeat/RepeatTotal - pass being measured, and how many there are
    %   Progress     - fraction of the whole run complete, 0..1
    %   Elapsed      - seconds since the run started
    %   Metrics      - scalars for the current measurement (see default_metrics).
    %                  dc_v is the offset still in Response; dc_removed_v is the
    %                  offset AC coupling took off it and ac_coupled_hz the corner
    %                  it high-passed at, both NaN when the record was not coupled
    %   Context      - engine parameters needed to interpret the data
    %                  (see default_context)
    %
    % See also: stimgen.calibration.Engine, stimgen.calibration.LiveMonitor

    properties (SetAccess = immutable)
        Stage        (1,1) string
        Phase        (1,1) string
        Fs           (1,1) double
        Excitation   (1,:) double
        Response     (1,:) double
        Span         (1,:) double
        Markers      (1,:) double
        MarkerLabels (1,:) string
        Table        (1,1) struct
        XLabel       (1,1) string
        XScale       (1,1) string
        XFactor      (1,1) double
        Index        (1,1) double
        Total        (1,1) double
        Repeat       (1,1) double
        RepeatTotal  (1,1) double
        Progress     (1,1) double
        Elapsed      (1,1) double
        Metrics      (1,1) struct
        Context      (1,1) struct
    end

    methods
        function obj = LiveUpdate(stage, phase, opts)
            % obj = stimgen.calibration.LiveUpdate(stage, phase, Name=Value)
            % Build one live-update payload. Every field beyond stage and
            % phase is optional and defaults to empty/NaN, so a caller only
            % supplies what it actually knows.
            arguments
                stage (1,1) string
                phase (1,1) string {mustBeMember(phase, ["start" "measure" "done"])}
                opts.Fs           (1,1) double = 0
                opts.Excitation   (1,:) double = []
                opts.Response     (1,:) double = []
                opts.Span         (1,:) double = []
                opts.Markers      (1,:) double = []
                opts.MarkerLabels (1,:) string = string.empty
                opts.Table        (1,1) struct = stimgen.calibration.LiveUpdate.default_table()
                opts.XLabel       (1,1) string = ""
                opts.XScale       (1,1) string = "log"
                opts.XFactor      (1,1) double = 1
                opts.Index        (1,1) double = 0
                opts.Total        (1,1) double = 0
                opts.Repeat       (1,1) double = 0
                opts.RepeatTotal  (1,1) double = 0
                opts.Progress     (1,1) double = nan
                opts.Elapsed      (1,1) double = 0
                opts.Metrics      (1,1) struct = stimgen.calibration.LiveUpdate.default_metrics()
                opts.Context      (1,1) struct = stimgen.calibration.LiveUpdate.default_context()
            end
            obj.Stage        = stage;
            obj.Phase        = phase;
            obj.Fs           = opts.Fs;
            obj.Excitation   = opts.Excitation;
            obj.Response     = opts.Response;
            obj.Span         = opts.Span;
            obj.Markers      = opts.Markers;
            obj.MarkerLabels = opts.MarkerLabels;
            obj.Table        = opts.Table;
            obj.XLabel       = opts.XLabel;
            obj.XScale       = opts.XScale;
            obj.XFactor      = opts.XFactor;
            obj.Index        = opts.Index;
            obj.Total        = opts.Total;
            obj.Repeat       = opts.Repeat;
            obj.RepeatTotal  = opts.RepeatTotal;
            obj.Elapsed      = opts.Elapsed;
            obj.Metrics      = stimgen.calibration.LiveUpdate.fill_defaults_( ...
                opts.Metrics, stimgen.calibration.LiveUpdate.default_metrics());
            obj.Context      = stimgen.calibration.LiveUpdate.fill_defaults_( ...
                opts.Context, stimgen.calibration.LiveUpdate.default_context());

            if isnan(opts.Progress)
                obj.Progress = stimgen.calibration.LiveUpdate.infer_progress_(opts);
            else
                obj.Progress = opts.Progress;
            end
        end
    end

    methods (Static)
        function t = default_table()
            % Empty partial-LUT struct. sd_db is the across-repeat standard
            % deviation of the level, NaN before a second pass exists.
            t = struct('x', [], 'measurement', [], 'spl_db', [], ...
                       'voltage', [], 'sd_db', []);
        end

        function m = default_metrics()
            % Scalar metrics for the current measurement.
            m = struct( ...
                'spl_db',         nan, ...
                'voltage',        nan, ...
                'snr_db',         nan, ...
                'thd_db',         nan, ...
                'h2_db',          nan, ...
                'h3_db',          nan, ...
                'peak_v',         nan, ...
                'rms_v',          nan, ...
                'dc_v',           nan, ...
                'dc_removed_v',   nan, ...
                'ac_coupled_hz',  nan, ...
                'full_scale_v',   nan, ...
                'clipping',       false);
        end

        function c = default_context()
            % Engine parameters a renderer needs to convert volts to dB SPL
            % and to judge whether a required drive voltage is reachable.
            c = struct( ...
                'ReferenceLevel',    94, ...
                'MicSensitivity',    1, ...
                'NormativeValue',    80, ...
                'ExcitationVoltage', 1, ...
                'MaxOutputV',        10);
        end
    end

    methods (Static, Access = private)
        function s = fill_defaults_(s, d)
            % Add any field of d that s is missing, so a caller may pass a
            % partial struct and a renderer can still index every field.
            f = fieldnames(d);
            for k = 1:numel(f)
                if ~isfield(s, f{k})
                    s.(f{k}) = d.(f{k});
                end
            end
        end

        function p = infer_progress_(opts)
            % Fall back to point/repeat counting when the caller did not say.
            % Runs whose measurement order is not point-major must pass
            % Progress explicitly.
            if opts.Total <= 0
                p = nan;
                return
            end
            reps = max(opts.RepeatTotal, 1);
            done = max(opts.Index - 1, 0) * reps + max(opts.Repeat, 0);
            p = min(done / (opts.Total * reps), 1);
        end
    end
end
