function results = refine_lut_(obj, which, options)
% results = refine_lut_(obj, which, options)
% Shared measure-correct-remeasure loop behind refine_tones/refine_clicks.
%
% One pass tests the lookup table at its own points -- through test_tones or
% test_clicks, the same pathway that scales a real stimulus -- and, when the
% verdict fails, corrects each reliable point from the error that came back:
% a point that measured e dB high has its stored voltage scaled by
% 10^(-e/20), with spl_db and measurement moved the same way so the table
% stays consistent with compute_spl_voltage_'s model. Passes repeat until a
% test passes at ToleranceDb or MaxIterations tests have run. A correction is
% never applied after the final test, so the committed table is always the
% one the last test verified.
%
% Testing the table at its own knots is deliberate, and the opposite of what
% the standalone tests default to. The knots reproduce the calibration
% measurement by construction only at the excitation voltage; served at the
% level a stimulus asks for, each knot plays at a different drive, so any
% departure from the 20*log10(V) level model -- amplifier or speaker
% compression between those two operating points is the usual one -- lands
% here as a per-point error the sweep could never see. That error is exactly
% what the correction removes, and interpolation between the corrected knots
% inherits the fix.
%
% Aborts -- cancellation included -- restore the table (and its test record)
% to the state before refinement began, keeping refinement atomic the way
% every calibration run is.
%
% Parameters:
%   which - "tone" | "click": which lookup the refinement serves. "tone"
%           follows ToneLutSource, so it corrects the swept sine table when
%           that table is the one serving tone lookups.
%   options - forwarded from refine_tones/refine_clicks; see either for the
%           list and defaults.
%
% Returns:
%   results - the refinement record; see refine_tones. Also stored in the
%           refined table's own struct as CalibrationData.<table>.refinement,
%           so it is replaced along with the table by the next sweep.
arguments
    obj
    which (1,1) string {mustBeMember(which, ["tone", "click"])}
    options.MaxIterations   (1,1) double {mustBeInteger, mustBePositive, mustBeFinite} = 3
    options.ToleranceDb     (1,1) double {mustBePositive, mustBeFinite} = 1
    options.RepeatCount     (1,1) double {mustBeInteger, mustBePositive, mustBeFinite} = 2
    options.MinSnrDb        (1,1) double {mustBeFinite} = 10
    options.MaxCorrectionDb (1,1) double {mustBePositive, mustBeFinite} = 12
    options.LevelDb         (1,1) double = nan
end

obj.assert_adapter_();

% Resolve the table under refinement. "tone" follows ToneLutSource through
% resolve_tone_lut_, the same single definition of that choice the tests and
% compute_adjusted_voltage share.
if which == "tone"
    [lutField, lut] = obj.resolve_tone_lut_();
    verb = "tone (or swept sine)";
else
    lutField = "click";
    lut = [];
    if obj.IsCalibrated && isfield(obj.CalibrationData, 'click')
        lut = obj.CalibrationData.click;
    end
    verb = "click";
end
if isempty(lut)
    error('stimgen:calibration:Engine:missingTypeCalibration', ...
        ['Calibration data for type "%s" is not available. Run a %s ' ...
         'calibration before refining its lookup table.'], lutField, verb);
end

if which == "tone"
    knots = double(lut.frequency(:)).';
else
    knots = double(lut.duration(:)).';
end

level = options.LevelDb;
if ~isfinite(level)
    % The table's anchor level: the one every stored voltage promises to
    % produce, so it is where a correction is worth the most.
    level = obj.NormativeValue;
end

% Everything a pass touches -- the table itself and the test record the pass
% overwrites -- comes back on abort, keeping refinement as atomic as the
% sweeps. Snapshot of the whole struct rather than the one table: cheap, and
% immune to the tests growing new side fields.
backup = obj.CalibrationData;

iterations = struct('max_abs_error_db', {}, 'rms_error_db', {}, ...
    'bias_db', {}, 'n_reliable', {}, 'n_corrected', {}, ...
    'max_correction_db', {});
converged = false;
lastTest  = [];

try
    for it = 1:options.MaxIterations
        if which == "tone"
            r  = obj.test_tones(knots, level, ...
                RepeatCount=options.RepeatCount, ...
                ToleranceDb=options.ToleranceDb, ...
                MinSnrDb=options.MinSnrDb);
            tx = r.frequency(:);
        else
            r  = obj.test_clicks(knots, level, ...
                RepeatCount=options.RepeatCount, ...
                ToleranceDb=options.ToleranceDb, ...
                MinSnrDb=options.MinSnrDb);
            tx = r.duration(:);
        end
        lastTest = r;

        iterations(it).max_abs_error_db = r.max_abs_error_db;
        iterations(it).rms_error_db     = r.rms_error_db;
        iterations(it).bias_db          = r.bias_db;
        iterations(it).n_reliable       = nnz(r.reliable);
        iterations(it).n_corrected      = 0;
        iterations(it).max_correction_db = 0;

        stimgen.util.vprintf(1, ...
            'Refinement pass %d/%d ("%s" table): worst |error| %.2f dB, bias %+.2f dB (target %.2g dB)', ...
            it, options.MaxIterations, lutField, r.max_abs_error_db, ...
            r.bias_db, options.ToleranceDb);

        if r.passed
            converged = true;
            break
        end
        if it == options.MaxIterations
            % The last test stands as the record of the committed table;
            % correcting after it would leave an unverified table behind.
            break
        end

        % --- Correct the table from this pass's errors -------------------
        % Only reliable points move: a noise-dominated error would push its
        % point by the noise, not by the table's fault. e is measured minus
        % requested, so the drive that produces the requested level is the
        % stored voltage scaled by 10^(-e/20).
        e   = r.error_db(:, 1);
        rel = r.reliable(:, 1) & isfinite(e);

        corr = -e;
        clamped = rel & abs(corr) > options.MaxCorrectionDb;
        if any(clamped)
            % An error that size is a broken measurement or a rig fault, not
            % an interpolation residue; take the bounded step and let the
            % next pass judge the result rather than committing to it.
            stimgen.util.vprintf(0, 1, ...
                ['Refinement pass %d: %d correction(s) exceeded the %g dB bound ' ...
                 'and were clamped. Errors that large usually mean a rig fault ' ...
                 'rather than a lookup-table one.'], ...
                it, nnz(clamped), options.MaxCorrectionDb);
            corr(clamped) = sign(corr(clamped)) .* options.MaxCorrectionDb;
        end

        d = obj.CalibrationData.(lutField);
        nCorrected = 0;
        for k = 1:numel(tx)
            if ~rel(k) || corr(k) == 0
                continue
            end
            % Matched by value rather than by position: the test sorts and
            % uniques its point list, and may have dropped knots the current
            % adapter cannot render.
            if which == "tone"
                ii = find(d.frequency == tx(k));
            else
                ii = find(d.duration == tx(k));
            end
            if isempty(ii)
                continue
            end
            g = 10 .^ (corr(k) / 20);
            d.voltage(ii)     = d.voltage(ii) .* g;
            % spl_db and measurement follow so the table still satisfies
            % compute_spl_voltage_: after the correction they are the model's
            % inference of what the excitation voltage produces, not a new
            % direct measurement.
            d.spl_db(ii)      = d.spl_db(ii) - corr(k);
            d.measurement(ii) = d.measurement(ii) ./ g;
            if isfield(d, 'metrics')
                if isfield(d.metrics, 'frequency_response_db_spl')
                    d.metrics.frequency_response_db_spl(ii) = ...
                        d.metrics.frequency_response_db_spl(ii) - corr(k);
                end
                if isfield(d.metrics, 'calibrated_level_sensitivity_db_per_v')
                    d.metrics.calibrated_level_sensitivity_db_per_v(ii) = ...
                        d.metrics.calibrated_level_sensitivity_db_per_v(ii) - corr(k);
                end
            end
            nCorrected = nCorrected + numel(ii);
        end
        obj.CalibrationData.(lutField) = d;

        iterations(it).n_corrected       = nCorrected;
        iterations(it).max_correction_db = max([abs(corr(rel)); 0]);

        stimgen.util.vprintf(1, ...
            'Refinement pass %d: corrected %d point(s), largest correction %.2f dB', ...
            it, nCorrected, iterations(it).max_correction_db);
    end
catch ME
    obj.CalibrationData = backup;
    stimgen.util.vprintf(0, 2, ...
        'Lookup-table refinement aborted; the "%s" table was restored: %s', ...
        lutField, ME.message);
    rethrow(ME);
end

results = struct;
results.lut_source        = lutField;
results.level_db          = level;
results.tolerance_db      = options.ToleranceDb;
results.max_iterations    = options.MaxIterations;
results.repeat_count      = options.RepeatCount;
results.min_snr_db        = options.MinSnrDb;
results.max_correction_db = options.MaxCorrectionDb;
results.iterations        = iterations(:);
results.n_iterations      = numel(iterations);
results.initial_max_abs_error_db = iterations(1).max_abs_error_db;
results.final_max_abs_error_db   = iterations(end).max_abs_error_db;
results.n_unreliable      = nnz(~lastTest.reliable(:, 1));
results.converged         = converged;
results.refinedOn         = datetime('now');

obj.CalibrationData.(lutField).refinement = results;

if converged
    verdict = 'converged';
else
    verdict = 'did NOT converge';
end
stimgen.util.vprintf(1, ...
    ['Refinement of the "%s" table %s: worst |error| %.2f -> %.2f dB over ' ...
     '%d test pass(es) (target %.2g dB at %g dB SPL)'], ...
    lutField, verdict, results.initial_max_abs_error_db, ...
    results.final_max_abs_error_db, results.n_iterations, ...
    options.ToleranceDb, level);
if results.n_unreliable > 0
    stimgen.util.vprintf(0, 1, ...
        ['Refinement: %d point(s) were never reliable (unreachable at %g dB SPL ' ...
         'or below the %g dB SNR floor) and were left uncorrected.'], ...
        results.n_unreliable, level, options.MinSnrDb);
end
end
