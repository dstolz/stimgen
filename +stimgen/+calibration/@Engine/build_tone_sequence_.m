function [y, schedule] = build_tone_sequence_(obj, freqs, burstDur, gapDur)
% [y, schedule] = build_tone_sequence_(obj, freqs, burstDur, gapDur)
% Assemble one train of gated tone bursts covering every frequency in freqs.
%
% Bursts are laid end to end separated by silence, with a gap also leading
% and trailing the train: the leading gap absorbs the acquisition delay that
% would otherwise push the first burst off the front of the record, and the
% trailing gap keeps the last burst's ringdown inside it. Both adapters
% record exactly as many samples as they play, so that padding has to be part
% of the excitation.
%
% Silence between bursts is what makes the per-burst analysis independent of
% frequency spacing: bursts are separated in time, so neighbouring points may
% sit closer together than their spectral lobes are wide.
%
% Parameters:
%   freqs    - (1,:) double burst frequencies in Hz
%   burstDur - (1,1) double burst length in seconds
%   gapDur   - (1,1) double silence before, between, and after bursts, seconds
%
% Returns:
%   y        - (1,:) double unit-amplitude excitation train
%   schedule - (1,:) struct, one element per burst:
%              frequency   - Hz
%              onset       - 1-based sample index of the burst's first sample
%              nsamples    - burst length in samples
%              rampSamples - length of one onset/offset ramp in samples
%              gapOnset    - 1-based sample index of the following gap
%              gapSamples  - length of that gap

fs   = obj.Fs;
gapN = round(gapDur * fs);

so                  = stimgen.Tone;
so.Fs               = fs;
so.Duration         = burstDur;
so.WindowMethod     = "Duration";
so.ApplyCalibration = false;   % the excitation must stay raw; scaling it by an
                               % existing LUT would fold that LUT into the result

n      = numel(freqs);
bursts = cell(1, n);
rampN  = zeros(1, n);
for i = 1:n
    so.Frequency = freqs(i);
    % Four carrier periods of total gate, as the per-burst version used: long
    % enough to keep splatter off the neighbouring analysis bands, short
    % enough to leave a steady-state middle even at the bottom of the sweep.
    % The clamp matters only for burst lengths under eight periods.
    so.WindowDuration = min(4 / freqs(i), burstDur / 2);
    so.update_signal();
    bursts{i} = so.Signal(:).';
    rampN(i)  = round(so.WindowDuration / 2 * fs);
end

burstN = cellfun(@numel, bursts);
y      = zeros(1, gapN + sum(burstN + gapN));

schedule = repmat(struct('frequency', nan, 'onset', 0, 'nsamples', 0, ...
    'rampSamples', 0, 'gapOnset', 0, 'gapSamples', 0), 1, n);

pos = gapN + 1;
for i = 1:n
    y(pos : pos + burstN(i) - 1) = bursts{i};

    schedule(i).frequency   = freqs(i);
    schedule(i).onset       = pos;
    schedule(i).nsamples    = burstN(i);
    schedule(i).rampSamples = rampN(i);
    schedule(i).gapOnset    = pos + burstN(i);
    schedule(i).gapSamples  = gapN;

    pos = pos + burstN(i) + gapN;
end
end
