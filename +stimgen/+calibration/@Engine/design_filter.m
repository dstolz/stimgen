function design_filter(obj, source, options)
% design_filter(obj)
% design_filter(obj, source)
% design_filter(obj, source, Name=Value)
% Design an arbitrary-magnitude FIR equalizer from a frequency LUT.
% Stores the result in CalibrationData.filter, CalibrationData.filterGrpDelay,
% CalibrationData.filterSource and CalibrationData.filterDesign.
% Requires a completed tone or swept sine calibration.
%
% The LUT is resampled onto a dense design grid before the filter is fitted,
% so the design is no longer tied to how many frequencies were measured:
% NumCoefficients sets the filter length, Interpolation/FrequencyScale set how
% the measured points are joined, and SmoothingOctaves/MaxCorrectionDb keep a
% noisy or deeply notched measurement from consuming the whole filter.
%
% Parameters:
%   source - "auto" (default), "tone", or "swept_sine". "auto" prefers the
%            tone LUT and falls back to swept sine.
%
% Name-Value Parameters:
%   NumCoefficients  - filter length in taps. 0 (default) derives it from the
%                      number of LUT points. Forced odd (Type I linear phase).
%   DesignMethod     - "freqsamp" (default, frequency sampling) or "ls"
%                      (least squares). "ls" tracks the target more tightly at
%                      a given length but rings more at sharp transitions.
%   Interpolation    - "pchip" (default), "linear", "spline", or "makima".
%                      How LUT points are joined across the design grid.
%                      "pchip" will not overshoot between measured points;
%                      "spline" is smoother but can.
%   FrequencyScale   - "log" (default) or "linear". Axis on which the grid is
%                      laid out and the interpolation is performed. Log
%                      spends resolution where transducers actually vary.
%   AmplitudeScale   - "db" (default) or "linear". Axis the interpolation and
%                      smoothing operate on.
%   GridPoints       - design grid resolution. 0 (default) scales it with the
%                      filter length.
%   SmoothingOctaves - fractional-octave smoothing width applied to the target
%                      magnitude, e.g. 1/3. 0 (default) disables it.
%   MaxCorrectionDb  - maximum correction depth in dB below the peak of the
%                      target response. Inf (default) leaves it unlimited.
%                      Caps how much of the filter a deep notch can claim.
%   FrequencyRange   - [lo hi] Hz to equalize. Defaults to the LUT span. The
%                      target is held flat at the edge value outside it.
%   ShowResponse     - true (default) opens the design in fvtool.
%
% Example:
%   eng.design_filter("swept_sine", NumCoefficients=257, ...
%       SmoothingOctaves=1/6, MaxCorrectionDb=20, FrequencyRange=[500 32000]);
arguments
    obj
    source (1,1) string {mustBeMember(source, ["auto", "tone", "swept_sine"])} = "auto"
    options.NumCoefficients  (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    options.DesignMethod     (1,1) string {mustBeMember(options.DesignMethod, ["freqsamp", "ls"])} = "freqsamp"
    options.Interpolation    (1,1) string {mustBeMember(options.Interpolation, ["pchip", "linear", "spline", "makima"])} = "pchip"
    options.FrequencyScale   (1,1) string {mustBeMember(options.FrequencyScale, ["log", "linear"])} = "log"
    options.AmplitudeScale   (1,1) string {mustBeMember(options.AmplitudeScale, ["db", "linear"])} = "db"
    options.GridPoints       (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    options.SmoothingOctaves (1,1) double {mustBeNonnegative, mustBeFinite} = 0
    options.MaxCorrectionDb  (1,1) double {mustBePositive} = inf
    options.FrequencyRange   (1,:) double = []
    options.ShowResponse     (1,1) logical = true
end

% Both LUTs carry frequency/voltage on the same scale, so either can drive
% the equalizer; tone wins under "auto" only to preserve prior behaviour.
if source == "auto"
    candidates = ["tone", "swept_sine"];
else
    candidates = source;
end

lutName = '';
if obj.IsCalibrated
    for c = candidates
        if isfield(obj.CalibrationData, c) && ~isempty(obj.CalibrationData.(c))
            lutName = char(c);
            break
        end
    end
end

if isempty(lutName)
    % Name what is on hand: the GUI remembers the source across sessions, so
    % an explicit "swept_sine" against a tone-only calibration would
    % otherwise fail the same inscrutable way every time.
    known = ["tone", "swept_sine"];
    has = false(size(known));
    for k = 1:numel(known)
        has(k) = isfield(obj.CalibrationData, known(k)) && ...
                 ~isempty(obj.CalibrationData.(known(k)));
    end
    available = known(has);

    if isempty(available)
        error('stimgen:calibration:Engine:noToneData', ...
            'Tone or swept sine calibration must be completed before designing the filter.');
    end
    error('stimgen:calibration:Engine:noToneData', ...
        ['This calibration has no %s LUT to design from. Available: %s. ' ...
         'Choose that source, or use "auto".'], source, strjoin(available, ', '));
end
stimgen.util.vprintf(1, 'Designing equalization filter from %s calibration...', lutName);

fs = obj.Fs;
if ~isfinite(fs) || fs <= 0
    % Fs comes from the adapter, so this is the offline case.
    error('stimgen:calibration:Engine:noSampleRate', ...
        ['Filter design needs a sample rate, which comes from the hardware ' ...
         'adapter. Attach an adapter before designing the filter.']);
end
nyq  = fs / 2;
d    = obj.CalibrationData.(lutName);
freq = d.frequency(:);
volt = d.voltage(:);

% The design grid needs a strictly increasing frequency vector, and the DC and
% Nyquist endpoints are appended below, so drop anything that would collide
% with them or break monotonicity.
keep = isfinite(freq) & isfinite(volt) & freq > 0 & freq < nyq & volt > 0;
[freq, iKeep] = unique(freq(keep));
voltKept = volt(keep);
volt     = voltKept(iKeep);

if numel(freq) < 2
    error('stimgen:calibration:Engine:insufficientToneData', ...
        'At least two in-band %s calibration points are required to design a filter.', lutName);
end

% --- Filter length --------------------------------------------------------
% Odd tap count (even order): an odd-order linear-phase FIR is silently forced
% to zero gain at Nyquist, losing the top of the band with no error.
if options.NumCoefficients > 0
    nCoef = options.NumCoefficients;
    if mod(nCoef, 2) == 0
        nCoef = nCoef + 1;
        stimgen.util.vprintf(1, ...
            'NumCoefficients rounded up to %d: a linear-phase FIR needs an odd tap count to hold gain at Nyquist.', ...
            nCoef);
    end
    if nCoef < 3
        error('stimgen:calibration:Engine:badFilterLength', ...
            'NumCoefficients must be at least 3.');
    end
else
    nCoef = 2 * ceil(numel(freq) / 2) + 1;
end
nOrd = nCoef - 1;

% --- Equalized band -------------------------------------------------------
if isempty(options.FrequencyRange)
    band = [freq(1) freq(end)];
else
    if numel(options.FrequencyRange) ~= 2
        error('stimgen:calibration:Engine:badFrequencyRange', ...
            'FrequencyRange must be a two-element [lo hi] vector in Hz.');
    end
    band = double(options.FrequencyRange);
    band(1) = max(band(1), fs / 1e6);   % keep it off DC so the log grid is valid
    band(2) = min(band(2), nyq);
    if ~all(isfinite(band)) || band(2) <= band(1)
        error('stimgen:calibration:Engine:badFrequencyRange', ...
            'FrequencyRange must be increasing and fall between 0 and Nyquist (%g Hz).', nyq);
    end
end

% --- Design grid ----------------------------------------------------------
if options.GridPoints > 0
    nGrid = max(options.GridPoints, 2);
else
    nGrid = min(1024, max(256, 8 * nCoef));
end

if options.FrequencyScale == "log"
    fGrid = logspace(log10(band(1)), log10(band(2)), nGrid)';
    xLut  = log2(freq);
    xGrid = log2(fGrid);
else
    fGrid = linspace(band(1), band(2), nGrid)';
    xLut  = freq;
    xGrid = fGrid;
end

% --- Target magnitude -----------------------------------------------------
% Interpolate in dB by default: transducer responses are smooth in dB and a
% linear-amplitude fit lets the loud end of the LUT dominate the shape.
useDb = options.AmplitudeScale == "db";
if useDb
    yLut = 20 * log10(volt);
else
    yLut = volt;
end

% No extrapolation - the target is held flat at the edge value wherever the
% requested band runs past the measured one.
mag = interp1(xLut, yLut, xGrid, char(options.Interpolation), nan);
mag(xGrid < xLut(1))   = yLut(1);
mag(xGrid > xLut(end)) = yLut(end);

if options.SmoothingOctaves > 0
    % SamplePoints in log2(Hz) makes the window a constant fraction of an
    % octave regardless of how the grid itself is spaced.
    mag = movmean(mag, options.SmoothingOctaves, 'SamplePoints', log2(fGrid));
end

if ~useDb
    mag = 20 * log10(max(mag, eps));
end

% Only the shape matters - apply_calibration renormalizes after filtering - so
% referencing the peak to 0 dB keeps the design well conditioned and makes
% MaxCorrectionDb mean "depth below the peak".
mag = mag - max(mag);
if isfinite(options.MaxCorrectionDb)
    mag = max(mag, -options.MaxCorrectionDb);
end
correctionDb = max(mag) - min(mag);
amp = 10 .^ (mag / 20);

% --- [DC, grid, Nyquist] specification ------------------------------------
% Frequencies stay in Hz because SampleRate is supplied; normalizing them here
% is what made designfilt reject the vector.
fAll = fGrid;
aAll = amp;
if fAll(1) > 0
    fAll = [0; fAll];
    aAll = [aAll(1); aAll];
end
if fAll(end) < nyq
    fAll = [fAll; nyq];
    aAll = [aAll; aAll(end)];
end

% Frequencies must be strictly increasing for both methods: designfilt
% rejects the duplicated band edges a direct firls call would accept, and
% builds the piecewise-linear target from consecutive points itself. Its "ls"
% solve is rank deficient by one for every Type I arbmagfir - on a four-point
% specification as readily as on a thousand-point one - and designfilt keeps
% that warning to itself, leaving the minimum-norm result this design wants.
filt = designfilt('arbmagfir', ...
    'FilterOrder',  nOrd, ...
    'Frequencies',  fAll, ...
    'Amplitudes',   aAll, ...
    'SampleRate',   fs, ...
    'DesignMethod', char(options.DesignMethod));

gd = round(mean(grpdelay(filt)));

obj.CalibrationData.filter         = filt;
obj.CalibrationData.filterGrpDelay = gd;
obj.CalibrationData.filterSource   = string(lutName);
obj.CalibrationData.filterDesign   = struct( ...
    'source',           string(lutName), ...
    'numCoefficients',  nCoef, ...
    'designMethod',     options.DesignMethod, ...
    'interpolation',    options.Interpolation, ...
    'frequencyScale',   options.FrequencyScale, ...
    'amplitudeScale',   options.AmplitudeScale, ...
    'gridPoints',       numel(fAll), ...
    'smoothingOctaves', options.SmoothingOctaves, ...
    'maxCorrectionDb',  options.MaxCorrectionDb, ...
    'frequencyRange',   band, ...
    'correctionDb',     correctionDb, ...
    'sampleRate',       fs, ...
    'designedOn',       datetime('now'));

stimgen.util.vprintf(1, ...
    ['Filter designed from %s LUT: %d taps (%s), %g-%g Hz at Fs = %.4f Hz, ' ...
     'correction span %.1f dB, group delay %d samples'], ...
    lutName, nCoef, options.DesignMethod, band(1), band(2), fs, correctionDb, gd);

if options.ShowResponse
    show_response_(filt, lutName, nCoef, options.FrequencyScale, fs, band);
end
end

% ------------------------------------------------------------------------ %
function show_response_(filt, lutName, nCoef, freqScale, fs, band)
% Raise the new design in fvtool, replacing the window left by the previous
% design so repeated tuning passes do not litter the desktop.
%
% fvtool returns a sigtools.fvtool, not an HG figure, so the window cannot be
% recovered with findall - the handle has to be held here, and its validity
% tested with isvalid rather than ishandle, which is false even when live.
persistent hFv
try
    if ~isempty(hFv) && isvalid(hFv)
        delete(hFv);
    end
    hFv = fvtool(filt);

    % filt already carries SampleRate, so fvtool inherits the hardware rate.
    % Set it anyway: the frequency axis is where the operator confirms the
    % filter was designed for the rate the equipment actually runs at.
    set(hFv, 'Fs', fs);

    if freqScale == "log"
        % A log axis over fvtool's default [0, Fs/2) grid starts at
        % Fs/2/NumberofPoints - a few Hz, decades below the lowest measured
        % point - so most of the axis shows the flat target held outside the
        % band rather than the design. Plot the equalized band itself, log
        % spaced, ending on Nyquist so the axis states the hardware rate.
        set(hFv, 'FrequencyRange', 'Specify freq. vector');
        set(hFv, 'FrequencyVector', logspace(log10(band(1)), log10(fs/2), 2048));
        set(hFv, 'FrequencyScale', 'Log');
    end

    % Name last: Fs and FrequencyScale each force a redraw that resets it to
    % fvtool's own "Figure N: <analysis>" title.
    set(hFv, 'Name', sprintf('stimgen Equalizer - %s LUT, %d taps, Fs = %.4f Hz', ...
             lutName, nCoef, fs), 'NumberTitle', 'off');
    figure(hFv);
catch ME
    % A missing display or a docked-tool failure must not lose the filter.
    stimgen.util.vprintf(1, 1, 'Could not open fvtool: %s', ME.message);
end
end
