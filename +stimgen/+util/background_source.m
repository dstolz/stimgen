function B = background_source(spec, calibration, nEpoch)
% B = stimgen.util.background_source(spec, calibration)
% B = stimgen.util.background_source(spec, calibration, nEpoch)
% The ongoing background a stimulus is embedded in, generated and calibrated.
%
% Nothing about level is restated here. The background is made by the
% package's own stimulus classes -- a stimgen.Noise or a stimgen.Tone on the
% SAME calibration object, ungated -- so a background at 50 dB SPL has exactly
% the rms a Noise or Tone stimulus at SoundLevel 50 has, with the same
% equalizer and the same LUT anchoring.
%
% Noise is returned as a segment that LOOPS SEAMLESSLY. A presenter tiles it,
% so the join must be inaudible: the noise is generated LoopDuration plus a
% cross-fade longer, and that extra tail is cross-faded (equal power) into
% the head. The last sample of the loop is then followed, on the next lap, by
% the sample the noise itself continued with. The two ends of the generated
% record are discarded first when an equalizer is applied, because
% filter_aligned starts and ends on zeros and its edges are not noise.
% Cross-fading independent noise keeps the expected power but not exactly the
% record's own rms, so the loop is scaled back to it: the loop AS PLAYED sits
% at the requested level.
%
% The noise is drawn from a private stream seeded with spec.Seed, so one seed
% is one waveform and the global stream is neither read nor changed.
%
% A tone needs no waveform: its frequency and peak amplitude are returned and
% a presenter computes it in closed form (which is also what lets it be
% frequency-modulated without a splice).
%
% Loops are memoized by Key (a few, most recent first): building one filters
% tens of seconds of noise, and a presenter asks once per variant.
%
% Parameters:
%   spec        - struct, as stimgen.StimType.background_spec_ returns:
%                 Type ("Noise"|"Tone"), Level, HighPass, LowPass, Frequency,
%                 LoopDuration, Seed, Fs, ApplyCalibration
%   calibration - stimgen.StimCalibration of the stimulus being embedded
%   nEpoch      - (optional) number of samples. Noise only: return that many
%                 samples of FRESH noise (global stream, not looped, not
%                 memoized) instead of the loop. This is the carrier a
%                 stimgen.BackgroundModulation draws its standalone Signal
%                 on; Key is "" because it identifies no shared waveform.
%
% Returns:
%   B - struct:
%       Type           "Noise" | "Tone"
%       Key            text equal for two calls that return the same
%                      background; "" for an epoch
%       Fs             sample rate (Hz)
%       Level          requested level (dB SPL when Calibrated)
%       Calibrated     the level is a real dB SPL: calibration was applied
%       Normalization  "rms" (Noise) | "absmax" (Tone): what an UNcalibrated
%                      waveform was normalized to, for a presenter that has
%                      to place it on a relative scale
%       Waveform       (1,:) double, volts: the loop or the epoch; [] for Tone
%       Frequency      Hz (Tone); NaN for Noise
%       Amplitude      peak volts (Tone); NaN for Noise
%       HighPass, LowPass      Hz (Noise); NaN for Tone
%       LoopDuration   seconds, as realized (Noise loop); NaN otherwise
%       Seed           (Noise loop); NaN otherwise
%       Crossfade      seconds of cross-fade at the seam (Noise loop)
%       Rms, Peak      volts, of the waveform (of the sine, for a Tone)
%
% Example:
%   t = stimgen.Tone('Background', "Noise", 'BackgroundLevel', 50);
%   B = t.get_background();          % calls this
%   y = B.Waveform(mod(0:1e6-1, numel(B.Waveform)) + 1);   % 1e6 samples of it
%
% See also: stimgen.StimType.get_background, stimgen.StimType.embedded_signal

Crossfade = 0.05;   % seconds of equal-power cross-fade at the loop seam
MemoSize  = 3;      % loops kept; each is LoopDuration*Fs doubles

if nargin < 3
    nEpoch = [];
end

type = string(spec.Type);
fs   = double(spec.Fs);
calibrated = logical(spec.ApplyCalibration) && has_data_(calibration);

switch type
    case "Tone"
        B = tone_(spec, calibration, calibrated, fs);
        return
    case "Noise"
        % below
    otherwise
        error('stimgen:util:background_source:UnknownType', ...
            'A background is "Noise" or "Tone", not "%s".', type);
end

if ~isempty(nEpoch)
    B = empty_(type, fs, spec, calibrated);
    nz = noise_(spec, calibration, calibrated, fs, max(1, round(nEpoch)), []);
    B.Waveform = nz.Signal;
    B.Rms      = sqrt(mean(B.Waveform .^ 2));
    B.Peak     = max(abs(B.Waveform));
    return
end

key = sprintf('Noise|L=%.10g|HP=%.10g|LP=%.10g|D=%.10g|S=%d|X=%.10g|Fs=%.10g|%s', ...
    spec.Level, spec.HighPass, spec.LowPass, spec.LoopDuration, ...
    round(spec.Seed), Crossfade, fs, fingerprint_(calibration, calibrated, "filter", NaN, spec.Level));

persistent memo
if isempty(memo)
    memo = struct('Key', {}, 'B', {});
end
hit = find(strcmp({memo.Key}, key), 1);
if ~isempty(hit)
    B    = memo(hit).B;
    memo = memo([hit, 1:hit-1, hit+1:end]);   % most recent first
    return
end

n  = round(double(spec.LoopDuration) * fs);
nx = min(round(Crossfade * fs), floor(n / 2));
if n < 2
    error('stimgen:util:background_source:LoopTooShort', ...
        'A background loop of %g s at %g Hz holds fewer than two samples.', ...
        spec.LoopDuration, fs);
end

% Guard samples at both ends, discarded: the equalizer's zero-padded edges.
guard = 0;
if calibrated
    calData = calibration.CalibrationData;
    if isfield(calData, 'filter') && ~isempty(calData.filter) && isfield(calData, 'filterGrpDelay')
        guard = 2 * round(double(calData.filterGrpDelay));
    end
end

stream = RandStream('mt19937ar', 'Seed', round(double(spec.Seed)));
nz  = noise_(spec, calibration, calibrated, fs, n + nx + 2 * guard, stream);
sig = nz.Signal;
if numel(sig) ~= n + nx + 2 * guard
    error('stimgen:util:background_source:LengthMismatch', ...
        'The background noise came back %d samples long where %d were asked for.', ...
        numel(sig), n + nx + 2 * guard);
end
target = sqrt(mean(sig .^ 2));       % the level stimgen.Noise set, over its record

y    = sig(guard + (1:n + nx));
loop = y(1:n);
if nx > 0
    k    = (0:nx-1) ./ nx;
    up   = sin(pi/2 .* k);
    down = cos(pi/2 .* k);
    % Lap boundary: loop(n) = y(n) is followed by loop(1) = y(n+1), the
    % sample the noise continued with; by loop(nx+1) it is all head again.
    loop(1:nx) = y(1:nx) .* up + y(n + (1:nx)) .* down;
end
loop = loop .* (target ./ sqrt(mean(loop .^ 2)));

B = empty_(type, fs, spec, calibrated);
B.Key          = string(key);
B.Waveform     = loop;
B.LoopDuration = n / fs;
B.Seed         = round(double(spec.Seed));
B.Crossfade    = nx / fs;
B.Rms          = sqrt(mean(loop .^ 2));
B.Peak         = max(abs(loop));

memo = [struct('Key', key, 'B', B), memo];
if numel(memo) > MemoSize
    memo = memo(1:MemoSize);
end
end


% ------------------------------------------------------------------------ %
function B = tone_(spec, calibration, calibrated, fs)
% A tone background: frequency and the peak a stimgen.Tone at that level has.
f = double(spec.Frequency);
if ~(f > 0 && f < fs / 2)
    error('stimgen:util:background_source:InvalidFrequency', ...
        'A background tone of %g Hz must lie between 0 and Fs/2 (%g Hz).', f, fs / 2);
end

% Long enough to hold a whole cycle, so the sampled peak the absmax
% normalization divides by is the sine's own to within the sampling.
dur = max(0.02, 4 / f);
tn  = stimgen.Tone('Fs', fs, 'Duration', dur, 'Frequency', f, ...
    'SoundLevel', double(spec.Level), 'ApplyWindow', false, ...
    'ApplyCalibration', calibrated);
if calibrated
    tn.Calibration = calibration;
end
tn.update_signal();

B = empty_("Tone", fs, spec, calibrated);
B.Key = string(sprintf('Tone|L=%.10g|F=%.10g|Fs=%.10g|%s', ...
    spec.Level, f, fs, fingerprint_(calibration, calibrated, "tone", f, spec.Level)));
B.Frequency = f;
B.Amplitude = max(abs(tn.Signal));
B.Rms       = B.Amplitude / sqrt(2);
B.Peak      = B.Amplitude;
end


function nz = noise_(spec, calibration, calibrated, fs, nSamples, stream)
% A stimgen.Noise of nSamples at the background's band and level, ungated,
% generated once. ApplyCalibration is switched off when there is no table to
% apply, so apply_calibration returns before logging a missing calibration.
nz = stimgen.Noise('Fs', fs, 'Duration', nSamples / fs, ...
    'HighPass', double(spec.HighPass), 'LowPass', double(spec.LowPass), ...
    'SoundLevel', double(spec.Level), 'ApplyWindow', false, ...
    'ApplyCalibration', calibrated);
if calibrated
    nz.Calibration = calibration;
end
nz.RandomStream = stream;
nz.update_signal();
end


function B = empty_(type, fs, spec, calibrated)
B = struct( ...
    'Type',          string(type), ...
    'Key',           "", ...
    'Fs',            fs, ...
    'Level',         double(spec.Level), ...
    'Calibrated',    calibrated, ...
    'Normalization', "rms", ...
    'Waveform',      [], ...
    'Frequency',     NaN, ...
    'Amplitude',     NaN, ...
    'HighPass',      NaN, ...
    'LowPass',       NaN, ...
    'LoopDuration',  NaN, ...
    'Seed',          NaN, ...
    'Crossfade',     NaN, ...
    'Rms',           NaN, ...
    'Peak',          NaN);
if type == "Tone"
    B.Normalization = "absmax";
else
    B.HighPass = double(spec.HighPass);
    B.LowPass  = double(spec.LowPass);
end
end


function tf = has_data_(calibration)
tf = false;
try
    tf = isa(calibration, 'stimgen.StimCalibration') ...
        && isstruct(calibration.CalibrationData) && ~isempty(calibration.CalibrationData);
catch
end
end


function text = fingerprint_(calibration, calibrated, type, value, level)
% What of the calibration decides this background's waveform, as text for the
% key: the drive voltage the tables give for it and, for noise, the equalizer
% that shapes it. Two calibrations that would scale and shape the background
% alike give the same text; a re-measured table or a redesigned filter does
% not, so a memoized loop is never served for a calibration it was not made
% with.
if ~calibrated
    text = 'uncal';
    return
end
v = calibration.compute_adjusted_voltage(type, value, level);
text = sprintf('cal:v=%.10g', v);
if type == "filter"
    calData = calibration.CalibrationData;
    if isfield(calData, 'filter') && ~isempty(calData.filter)
        h = filter_taps_(calData.filter);
        text = sprintf('%s|eq=%d:%.10g:%.10g', text, numel(h), sum(abs(h)), sum(h .* (1:numel(h))));
    end
end
end


function h = filter_taps_(f)
% The equalizer's coefficients as a row, whatever form it is stored in.
if isnumeric(f)
    h = double(f(:)).';
elseif isa(f, 'digitalFilter')
    h = double(f.Coefficients(:)).';
else
    try
        h = double(f.Numerator(:)).';
    catch
        h = [];
    end
end
end
