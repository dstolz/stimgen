function results = refine_tones(obj, options)
% results = refine_tones(obj)
% results = refine_tones(obj, Name=Value)
% Iteratively refine the tone lookup table against measured levels.
%
% Runs test_tones at the table's own frequencies -- each point played at the
% drive voltage the table asks for, the same call apply_calibration makes --
% and corrects every reliably measured point from the level error that comes
% back, repeating until a pass lands every point within ToleranceDb or
% MaxIterations tests have run. The correction is exact under the level
% model: a point measured e dB high has its stored voltage scaled by
% 10^(-e/20), and spl_db/measurement follow so the table stays consistent.
%
% What this buys over the one-shot sweep: the sweep measures every frequency
% at the excitation voltage, and the table then serves levels by assuming
% output scales as 20*log10 of drive voltage. Where the rig bends that
% assumption between the two operating points -- amplifier or speaker
% compression is the usual cause -- the refinement measures the residual at
% the drive the table actually commands and removes it, point by point.
%
% Which table is refined follows ToneLutSource, exactly as lookups and
% test_tones do: with "Tone Lookup From Swept Sine" set, the swept sine
% table is the one corrected.
%
% A correction is never applied after the final test, so the committed table
% is always one a test just verified -- results.converged says whether that
% test passed. Aborts (cancellation included) restore the table to its
% pre-refinement state. The final test remains in CalibrationData.toneTest,
% and the refinement record is stored in the refined table's own struct
% (CalibrationData.tone.refinement or .swept_sine.refinement), where the
% next sweep of that table replaces it.
%
% Name-Value Parameters:
%   MaxIterations   - most test passes to run; corrections happen between
%                     them, so at most MaxIterations-1 corrections (default 3)
%   ToleranceDb     - absolute level error at or below which a pass -- and
%                     the refinement -- is complete (default 1)
%   RepeatCount     - measurements averaged per point per pass (default 2)
%   MinSnrDb        - SNR below which a point is left uncorrected (default 10)
%   MaxCorrectionDb - largest single-pass correction; larger errors are
%                     clamped and logged, since they usually mean a rig
%                     fault rather than a table one (default 12)
%   LevelDb         - level the table is refined at (default: NormativeValue,
%                     the level every stored voltage promises to produce)
%
% Returns:
%   results - struct:
%     lut_source               - "tone" | "swept_sine", the table refined
%     level_db                 - level the passes tested at
%     iterations               - per-pass record: max_abs_error_db,
%                                rms_error_db, bias_db, n_reliable,
%                                n_corrected, max_correction_db
%     n_iterations             - test passes actually run
%     initial_max_abs_error_db - worst error before any correction
%     final_max_abs_error_db   - worst error of the last (verifying) test
%     n_unreliable             - points never reliable, left uncorrected
%     converged                - true when the last test passed ToleranceDb
%     tolerance_db, max_iterations, repeat_count, min_snr_db,
%     max_correction_db        - the criteria applied
%     refinedOn                - datetime of the run
%
% Example:
%   eng.calibrate_tones([], 2);
%   r = eng.refine_tones(ToleranceDb=0.5);
%   fprintf('worst error %.2f -> %.2f dB in %d pass(es)\n', ...
%       r.initial_max_abs_error_db, r.final_max_abs_error_db, r.n_iterations);
%
% See also: stimgen.calibration.Engine/calibrate_tones,
%           stimgen.calibration.Engine/test_tones,
%           stimgen.calibration.Engine/refine_clicks
arguments
    obj
    options.MaxIterations   (1,1) double {mustBeInteger, mustBePositive, mustBeFinite} = 3
    options.ToleranceDb     (1,1) double {mustBePositive, mustBeFinite} = 1
    options.RepeatCount     (1,1) double {mustBeInteger, mustBePositive, mustBeFinite} = 2
    options.MinSnrDb        (1,1) double {mustBeFinite} = 10
    options.MaxCorrectionDb (1,1) double {mustBePositive, mustBeFinite} = 12
    options.LevelDb         (1,1) double = nan
end
nv = namedargs2cell(options);
results = obj.refine_lut_("tone", nv{:});
end
