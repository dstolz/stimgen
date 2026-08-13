function results = refine_clicks(obj, options)
% results = refine_clicks(obj)
% results = refine_clicks(obj, Name=Value)
% Iteratively refine the click lookup table against measured levels.
%
% Runs test_clicks at the table's own durations -- each click played at the
% drive voltage the table asks for, the same call apply_calibration makes --
% and corrects every reliably measured point from the level error that comes
% back, repeating until a pass lands every point within ToleranceDb or
% MaxIterations tests have run. The correction is exact under the level
% model: a point measured e dB high has its stored voltage scaled by
% 10^(-e/20), and spl_db/measurement follow so the table stays consistent.
%
% What this buys over the one-shot sweep: the sweep measures every duration
% at the excitation voltage, and the table then serves levels by assuming
% output scales as 20*log10 of drive voltage. Where the rig bends that
% assumption between the two operating points -- amplifier or speaker
% compression is the usual cause, and brief clicks are driven hard -- the
% refinement measures the residual at the drive the table actually commands
% and removes it, point by point.
%
% A correction is never applied after the final test, so the committed table
% is always one a test just verified -- results.converged says whether that
% test passed. Aborts (cancellation included) restore the table to its
% pre-refinement state. The final test remains in CalibrationData.clickTest,
% and the refinement record is stored in CalibrationData.click.refinement,
% where the next click sweep replaces it.
%
% Name-Value Parameters and Returns: as refine_tones, with durations in
% place of frequencies and lut_source always "click".
%
% Example:
%   eng.calibrate_clicks([], 2);
%   r = eng.refine_clicks(ToleranceDb=0.5);
%
% See also: stimgen.calibration.Engine/calibrate_clicks,
%           stimgen.calibration.Engine/test_clicks,
%           stimgen.calibration.Engine/refine_tones
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
results = obj.refine_lut_("click", nv{:});
end
