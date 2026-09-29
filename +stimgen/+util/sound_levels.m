function S = sound_levels(y, fs, micSens, options)
% S = stimgen.util.sound_levels(y, fs)
% S = stimgen.util.sound_levels(y, fs, micSens)
% S = stimgen.util.sound_levels(y, fs, micSens, Name=Value)
% What a sound level meter would read for one record.
%
% The readouts of an IEC 61672-1 meter, for each requested frequency
% weighting:
%
%   Leq    equivalent continuous level: the rms of the weighted record
%   Lpeak  peak level: the largest instantaneous weighted value. LCpeak is
%          the one a meter reports by default; LZpeak is the unweighted peak
%   LFmax  maximum Fast (125 ms) exponentially time-weighted level
%   LSmax  maximum Slow (1 s) exponentially time-weighted level
%   LE     sound exposure level: the record's energy re 1 s, which is Leq
%          plus 10*log10(duration). For a stimulus shorter than a second it
%          is the number that does not depend on how much silence surrounds it
%
% and, unweighted, the two peak-equivalent levels audiology specifies
% transients in:
%
%   peSPL  the rms level of a sinusoid with the same PEAK as the record --
%          the peak divided by sqrt(2). This is the scale stimgen's click
%          table is built on (Engine/compute_spl_voltage_).
%   ppeSPL the rms level of a sinusoid with the same PEAK-TO-PEAK
%
% The frequency weightings are the IEC 61672-1 analog networks themselves,
% evaluated on the record's FFT grid and applied to the waveform: the exact
% magnitude -- the curve stimgen.util.weighting_db draws, from the same pole
% frequencies -- and the network's own minimum phase, at every frequency up to
% Nyquist and at any sample rate. The weighting is applied to the waveform
% rather than to a spectrum because a peak and a time-weighted maximum are
% properties of the weighted waveform, and every readout here should come from
% the same weighted signal a meter would have. The usual digital realization,
% a bilinear-transformed IIR, was not used because it compresses the top
% octave: on a 48 kHz converter its A curve is 7 dB low at 16 kHz, and even at
% 96 kHz a decibel. The record is zero-padded by a quarter of a second first,
% so the network's slowest tail -- the doubled 20.6 Hz pole -- has died away
% rather than wrapping round onto the start of the record.
%
% Z is no weighting at all, over the full band up to Nyquist -- not the
% 10 Hz - 20 kHz a Z-weighted meter guarantees -- because on a rig presenting
% ultrasonic stimuli the band above 20 kHz is the point.
%
% Fast and Slow are exponential averages started from zero at the first
% sample, as a meter reset at the start of the record would be. A record much
% shorter than the time constant never charges the average: LFmax for a 5 ms
% tone pip reads far below its Leq, which is exactly what a meter shows for
% one, and the reason Leq, LE and the peak levels are the ones to trust for
% short stimuli.
%
% DC is removed before anything is measured. An offset in the input stage is
% not sound, and left in it would inflate every unweighted level and put a
% step into the weighting filters.
%
% Every level goes through stimgen.calibration.Engine.volts_to_spl when a
% microphone sensitivity is given -- the package's one volts-to-dB-SPL
% conversion -- and is 20*log10 of the value (dB re 1, i.e. dBV for a record in
% volts) when it is not.
%
% Parameters:
%   y              - (1,:) double record, in volts (or any linear unit when
%                    micSens is NaN)
%   fs             - (1,1) double sample rate (Hz)
%   micSens        - (1,1) double microphone sensitivity (V/Pa); NaN (default)
%                    for levels in dB re 1
%   Weightings     - (1,:) string subset of ["Z","A","C"] (default all three)
%   History        - (1,1) string "" (default) or one of Weightings: also
%                    return the time-weighted level against time for that
%                    weighting
%   TimeWeighting  - (1,1) string "F" (default) | "S", for History
%
% Returns:
%   S - struct:
%     Unit            "dB SPL" | "dB re 1"
%     MicSensitivity  as given
%     Fs, N, Duration_s
%     Weightings      (1,W) string
%     Leq, Lpeak, LFmax, LSmax, LE
%                     (1,W) levels, one per weighting (NaN for an empty,
%                     constant or non-finite record)
%     peSPL, ppeSPL   unweighted peak-equivalent levels
%     History         [] or struct: weighting, time_weighting, t_s, level_db
%                     (full resolution; decimate before drawing)
%
% Example:
%   S = stimgen.util.sound_levels(micRecord, 48000, 0.05);
%   fprintf('LAeq %.1f dB, LCpeak %.1f dB\n', ...
%       S.Leq(S.Weightings == "A"), S.Lpeak(S.Weightings == "C"));
%
% See also: stimgen.util.weighting_db, stimgen.calibration.Engine.volts_to_spl,
%           stimgen.StimInspector
arguments
    y       (1,:) double
    fs      (1,1) double {mustBePositive, mustBeFinite}
    micSens (1,1) double = nan
    options.Weightings (1,:) string {mustBeMember(options.Weightings, ["Z","A","C"])} = ["Z","A","C"]
    options.History (1,1) string {mustBeMember(options.History, ["","Z","A","C"])} = ""
    options.TimeWeighting (1,1) string {mustBeMember(options.TimeWeighting, ["F","S"])} = "F"
end

W  = options.Weightings;
nW = numel(W);
n  = numel(y);
acoustic = isfinite(micSens) && micSens > 0;

S = struct();
if acoustic
    S.Unit = "dB SPL";
else
    S.Unit = "dB re 1";
end
S.MicSensitivity = micSens;
S.Fs         = fs;
S.N          = n;
S.Duration_s = n / fs;
S.Weightings = W;
S.Leq        = nan(1, nW);
S.Lpeak      = nan(1, nW);
S.LFmax      = nan(1, nW);
S.LSmax      = nan(1, nW);
S.LE         = nan(1, nW);
S.peSPL      = nan;
S.ppeSPL     = nan;
S.History    = [];

if n < 2 || ~all(isfinite(y)) || ~any(y ~= y(1))
    return
end

toDb = @(v) level_(v, micSens, acoustic);

y = y - mean(y);

S.peSPL  = toDb(max(abs(y)) / sqrt(2));
S.ppeSPL = toDb((max(y) - min(y)) / 2 / sqrt(2));

aF = exp(-1 / (0.125 * fs));
aS = exp(-1 / (1.000 * fs));

for k = 1:nW
    yw = weight_(y, fs, W(k));
    p2 = yw .^ 2;
    eF = filter(1 - aF, [1, -aF], p2);
    eS = filter(1 - aS, [1, -aS], p2);

    S.Leq(k)   = toDb(sqrt(mean(p2)));
    S.Lpeak(k) = toDb(max(abs(yw)));
    S.LFmax(k) = toDb(sqrt(max(eF)));
    S.LSmax(k) = toDb(sqrt(max(eS)));
    % Energy re 1 s: sqrt of the time integral of the squared record, over
    % one second, is the rms that one second would need to hold as much.
    S.LE(k)    = toDb(sqrt(sum(p2) / fs));

    if options.History == W(k)
        if options.TimeWeighting == "S"
            e = eS;
        else
            e = eF;
        end
        S.History = struct( ...
            'weighting',      W(k), ...
            'time_weighting', options.TimeWeighting, ...
            't_s',            (0:n-1) / fs, ...
            'level_db',       toDb(sqrt(e)));
    end
end
end


% ------------------------------------------------------------------------ %
function L = level_(v, micSens, acoustic)
% Linear amplitude(s) as a level: dB SPL through the package's one conversion
% when there is a sensitivity, dB re 1 otherwise.
v = reshape(double(v), 1, []);
if acoustic
    L = stimgen.calibration.Engine.volts_to_spl(v, micSens);
else
    L = 20 * log10(max(v, 0));
end
end


function yw = weight_(y, fs, type)
% The record through one frequency weighting, applied on its FFT grid.
if type == "Z"
    yw = y;
    return
end
n    = numel(y);
nfft = 2 ^ nextpow2(n + ceil(0.25 * fs));
f    = (0:nfft/2) * (fs / nfft);
H    = network_(f, type);
X    = fft(y, nfft);
% The grid covers 0..Nyquist; 'symmetric' supplies the mirrored half, so
% the weighted record comes back real without a stray imaginary residue.
X    = X(1:nfft/2 + 1) .* H;
yw   = ifft([X, conj(X(end-1:-1:2))], 'symmetric');
yw   = yw(1:n);
end


function H = network_(f, type)
% Complex response of the IEC 61672-1 A or C network at f (Hz), 0 dB at 1 kHz.
%
% A has four zeros at the origin and poles at f1 (twice), f2, f3 and f4
% (twice); C has two zeros at the origin and poles at f1 and f4, each twice.
% The pole frequencies are the ones stimgen.util.weighting_db evaluates its
% curves from, so the magnitude here is that curve exactly; the phase is the
% network's own.
p = 2 * pi * [20.6, 107.7, 737.9, 12194];
switch type
    case "A"
        h = @(s) s.^4 ./ ((s + p(1)).^2 .* (s + p(2)) .* (s + p(3)) .* (s + p(4)).^2);
    case "C"
        h = @(s) s.^2 ./ ((s + p(1)).^2 .* (s + p(4)).^2);
end
H = h(2i * pi * f) ./ abs(h(2i * pi * 1000));
end
