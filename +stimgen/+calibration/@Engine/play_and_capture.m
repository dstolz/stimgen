function capture = play_and_capture(obj, signal, options)
% capture = play_and_capture(obj, signal)
% capture = play_and_capture(obj, signal, Name=Value)
% Play one arbitrary waveform and return the microphone record beside it.
%
% The general-purpose acquisition behind every measurement of a waveform this
% class did not synthesize itself: a stimulus built elsewhere, handed here to
% find out what the rig actually emits for it. Where calibrate_tones owns its
% excitation and reduces the record to one number per burst, this owns
% neither. It plays what it is given and returns the record aligned to it,
% leaving the analysis to the caller -- which is what lets
% stimgen.SpotCheck hand the result to stimgen.StimInspector rather than to a
% lookup table.
%
% signal is taken as VOLTS, already at the amplitude that should reach the
% converter. ExcitationVoltage is deliberately not applied: a calibrated
% stimulus already carries the drive voltage its own SoundLevel asks for, and
% scaling it again would measure a level nobody requested. A caller playing an
% unscaled unit-amplitude waveform therefore scales it itself.
%
% Silence is placed before and after the waveform, and both earn their keep.
% PreDelay is what the returned noise floor is measured over -- an in-situ
% floor for this record, under the conditions the signal was captured in, at
% no extra acquisition. PostDelay is the room the response has to arrive late
% in: it bounds the delay search, so it must be at least the rig's round-trip
% latency or the tail of the response falls outside the record and cannot be
% recovered.
%
% Parameters:
%   signal    - (1,:) double waveform to play, in volts
%   PreDelay  - (1,1) double leading silence in seconds (default 0.05)
%   PostDelay - (1,1) double trailing silence in seconds (default 0.05).
%               Also the largest conduction delay the alignment can find.
%   Repeats   - (1,1) double positive integer acquisitions to average
%               (default 1). Each is aligned on its own delay before
%               averaging, so a latency that moves between records does not
%               smear the average.
%   Stage     - (1,1) string LiveUpdate stage name (default "spot_check")
%
% Returns:
%   capture - struct describing the acquisition:
%     fs              sample rate (Hz)
%     excitation      the waveform as played (V)
%     response        stimulus-span response, averaged over repeats (V)
%     records         repeats-by-numel(signal) matrix of aligned responses
%     record          the whole last acquisition, silence included (V)
%     delay_s         median conduction delay over the repeats
%     delay_sd_s      its spread; 0 for a single acquisition
%     delay_at_bound  the delay search hit PostDelay, so the true delay is
%                     probably larger and the response mis-cut
%     align_quality   how unambiguous the alignment was (see align_by_peak_);
%                     around 2 for a sustained tone by nature, not by fault
%     noise           struct: rms_v over the pre-excitation silence, the
%                     record it came from, and how many samples that was
%     headroom        aggregate clipping/headroom metrics (estimate_headroom_)
%     dc_removed_v    DC that AC coupling took off, NaN when it did not act
%     ac_coupled_hz   corner it high-passed at, NaN when it did not filter
%     pre_delay_s / post_delay_s / repeats / measuredOn
%
% Repeats above 1 average the response coherently, which lowers the noise on
% it by roughly sqrt(Repeats) while the reported noise floor is pooled from
% the silence as measured. An SNR formed from the two is therefore pessimistic
% by that factor. At the default of one acquisition the two agree exactly.
%
% See also: stimgen.SpotCheck, stimgen.calibration.Engine.measure_conduction_delay

arguments
    obj
    signal (1,:) double {mustBeReal, mustBeFinite}
    options.PreDelay  (1,1) double {mustBeNonnegative, mustBeFinite} = 0.05
    options.PostDelay (1,1) double {mustBeNonnegative, mustBeFinite} = 0.05
    options.Repeats   (1,1) double {mustBeInteger, mustBePositive, mustBeFinite} = 1
    options.Stage     (1,1) string = "spot_check"
end

obj.assert_adapter_();
obj.reset_cancel_();

if isempty(signal)
    error('stimgen:calibration:Engine:emptyExcitation', ...
        'play_and_capture needs a waveform to play, but was given an empty one.');
end

fs = obj.Fs;
if ~isfinite(fs) || fs <= 0
    error('stimgen:calibration:Engine:noSampleRate', ...
        'The attached adapter reports no usable sample rate (%g Hz).', fs);
end

nPre  = round(options.PreDelay  * fs);
nPost = round(options.PostDelay * fs);
nSig  = numel(signal);
nRep  = options.Repeats;

% The delay search cannot run past the tail silence. A response arriving
% later than PostDelay has already had its own end cut off by the record, so
% there is nothing there to align to; align_response_ returns 0 for a search
% bound below one sample, which is the right answer when no silence was asked
% for at all.
maxLag = nPost;

x = [zeros(1, nPre), signal, zeros(1, nPost)];
obj.ExcitationSignal = x;

peakV = max(abs(signal));
if peakV > obj.MaxOutputVoltage
    stimgen.util.vprintf(0, 1, ...
        ['Excitation peaks at %.4g V, above the %.4g V output ceiling; the ' ...
         'converter will clip it and the captured level will be wrong.'], ...
        peakV, obj.MaxOutputVoltage);
end

stimgen.util.vprintf(1, ...
    'Spot capture: %.3f s waveform, %.3f s pre / %.3f s post, %d acquisition(s) at %.10g Hz', ...
    nSig / fs, nPre / fs, nPost / fs, nRep, fs);

obj.begin_run_();
obj.emit_live_(options.Stage, "start", ...
    'Index', 0, 'Total', nRep, 'Repeat', 0, 'RepeatTotal', nRep, 'Progress', 0);

segments  = nan(nRep, nSig);
noisePool = zeros(1, 0);
firstNoise = zeros(1, 0);
lagS      = nan(1, nRep);
atBound   = false(1, nRep);
qualities = nan(1, nRep);
headroom  = repmat(obj.estimate_headroom_([], []), nRep, 1);
lastFull  = zeros(1, 0);
dcRemoved = nan;
acHz      = nan;

try
    for rep = 1:nRep
        obj.throw_if_cancelled_();

        raw  = obj.Adapter.play_and_record(x);
        % Conformed to the excitation length before anything reads it: a
        % hardware adapter may hand back a fixed buffer allocation rather
        % than exactly what was asked for, and every index below -- and the
        % averaging across repeats -- assumes one known length.
        full = conform_length_(raw, numel(x));
        full = obj.ac_couple_response_(full);

        obj.ResponseSignal = full;
        lastFull  = full;
        dcRemoved = obj.LastDcRemoved_;
        acHz      = obj.LastAcCoupleHz_;

        [lag, bound, quality] = align_by_peak_(x, full, maxLag);
        lagS(rep)     = lag / fs;
        atBound(rep)  = bound && maxLag >= 1;
        qualities(rep) = quality;

        % The excitation begins at sample nPre+1, so its response begins lag
        % samples after that. Cutting exactly nSig samples from there is what
        % puts the recording on the same time base as the stimulus, which is
        % the whole basis of comparing the two.
        i0 = nPre + lag + 1;
        segments(rep, :) = full(i0 : i0 + nSig - 1);

        if nPre > 0
            thisNoise = full(1:nPre);
            noisePool = [noisePool, thisNoise]; %#ok<AGROW>
            if rep == 1
                firstNoise = thisNoise;
            end
        end

        headroom(rep) = obj.estimate_headroom_(signal, segments(rep, :));

        obj.emit_live_(options.Stage, "measure", ...
            'Span', [i0, i0 + nSig - 1], ...
            'Index', rep, 'Total', nRep, ...
            'Repeat', rep, 'RepeatTotal', nRep, ...
            'Progress', rep / nRep, ...
            'Metrics', struct('spl_db', obj.spl_from_volts(rms_(segments(rep, :)))));
    end
catch ME
    stimgen.util.vprintf(0, 2, 'Spot capture aborted: %s', ME.message);
    rethrow(ME);
end

response = mean(segments, 1, 'omitnan');

% Pooled across every silent sample acquired rather than averaged across
% repeats: averaging noise records suppresses the very thing being measured
% and would report a floor several dB below the one the signal actually sat on.
if isempty(noisePool)
    noiseRms = nan;
else
    noiseRms = rms_(noisePool);
end

delayS = median(lagS, 'omitnan');
if nRep > 1
    delaySd = std(lagS, 'omitnan');
else
    delaySd = 0;
end

if any(atBound)
    stimgen.util.vprintf(0, 1, ...
        ['The response delay reached the %.1f ms search bound, so the record ' ...
         'was probably cut in the wrong place. Increase PostDelay past the ' ...
         'rig round-trip latency.'], nPost / fs * 1e3);
end

capture = struct( ...
    'fs',             fs, ...
    'excitation',     signal, ...
    'response',       response, ...
    'records',        segments, ...
    'record',         lastFull, ...
    'pre_delay_s',    nPre / fs, ...
    'post_delay_s',   nPost / fs, ...
    'repeats',        nRep, ...
    'delay_s',        delayS, ...
    'delay_samples',  round(delayS * fs), ...
    'delay_sd_s',     delaySd, ...
    'delay_at_bound', any(atBound), ...
    'align_quality',  median(qualities, 'omitnan'), ...
    'noise',          struct('rms_v', noiseRms, 'record', firstNoise, ...
                             'n_samples', numel(noisePool)), ...
    'headroom',       obj.aggregate_headroom_(headroom), ...
    'dc_removed_v',   dcRemoved, ...
    'ac_coupled_hz',  acHz, ...
    'measuredOn',     datetime('now'));

obj.emit_live_(options.Stage, "done", ...
    'Index', nRep, 'Total', nRep, 'Repeat', nRep, 'RepeatTotal', nRep, ...
    'Progress', 1);

stimgen.util.vprintf(1, ...
    'Spot capture complete: delay %.2f ms, response %.4g V rms, noise %.4g V rms', ...
    delayS * 1e3, rms_(response), noiseRms);
end


% ------------------------------------------------------------------------ %
function y = conform_length_(y, n)
% y = conform_length_(y, n)
% One acquired record as a 1-by-n row: truncated past n, zero-filled short of
% it. An adapter that returns its whole output buffer rather than exactly the
% requested span is the case this exists for.
y = reshape(double(y), 1, []);
if numel(y) > n
    y = y(1:n);
elseif numel(y) < n
    y(end+1:n) = 0;
end
end


function [lag, atBound, quality] = align_by_peak_(x, y, maxLag)
% [lag, atBound, quality] = align_by_peak_(x, y, maxLag)
% Bulk delay of y relative to x, in samples, from the largest causal peak of
% their cross-correlation.
%
% NOT align_response_, and the difference matters. That method takes the FIRST
% causal sample to rise above the pre-excitation correlation floor, rather than
% the largest, because it serves measure_conduction_delay: a delay read there
% becomes a distance, and following the strongest return instead of the first
% arrival would measure a wall reflection and overstate the path. That rule is
% right for the click probe it was built around, whose arrival is a single
% sharp event standing clear of everything after it.
%
% It is not right for an arbitrary stimulus. A first-crossing test is only as
% good as the threshold under it, and for a continuous excitation the
% negative-lag floor and the early causal lags are the same order of magnitude
% -- so the crossing lands wherever the correlation noise happens to poke
% through first. Measured against a simulated rig with a known 137-sample
% delay, the first-crossing rule returned 0, 27, 41, 128 and 130 samples for
% noise, tones and a swept sine, while the peak returned 137-139 for every one.
%
% Nothing here becomes a distance, so there is no reflection to guard against.
% What this alignment is for is superimposing the two waveforms so they can be
% compared, and the correlation peak is the definition of the shift that does
% that best.
%
% Only causal lags are searched: a response cannot precede its own excitation.
%
% For a periodic stimulus the peak is ambiguous to within one period -- a
% steady 4 kHz tone correlates almost as well 12 samples out as on the nose.
% That is a real ambiguity rather than an error, and it is harmless: every
% level and spectrum here is computed over the whole span, where a shift of one
% period compares like with like. Only the waveform overlay can show it, as a
% phase offset between two otherwise identical traces.
%
% Parameters:
%   x      - (1,:) double excitation record
%   y      - (1,:) double response record
%   maxLag - (1,1) double largest delay to consider, in samples
%
% Returns:
%   lag     - (1,1) double delay in samples (>= 0)
%   atBound - (1,1) logical the peak sits at maxLag, so the true delay is
%             probably larger than the search allowed
%   quality - (1,1) double peak height over the rms of the searched
%             correlation. High for a broadband stimulus with one unambiguous
%             arrival, near 2 for a sustained tone that correlates at every
%             multiple of its period. Diagnostic only -- a low value means the
%             alignment is ambiguous, not that it is wrong.

lag     = 0;
atBound = false;
quality = nan;

n = min(numel(x), numel(y));
if n < 2 || maxLag < 1
    return
end

[c, lags] = xcorr(y(1:n), x(1:n), maxLag);

causal = lags >= 0;
cc     = abs(c(causal));
cl     = lags(causal);

[pk, k] = max(cc);
lag     = cl(k);
atBound = lag >= maxLag;
quality = pk / max(sqrt(mean(cc .^ 2)), eps);
end


function r = rms_(y)
% r = rms_(y) - Root mean square, ignoring NaN, 0 for an empty record.
y = y(isfinite(y));
if isempty(y)
    r = 0;
else
    r = sqrt(mean(y .^ 2));
end
end
