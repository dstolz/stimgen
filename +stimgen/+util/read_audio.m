function [y, srcFs, nChannels] = read_audio(src, channel, targetFs, srcFs)
% [y, srcFs, nChannels] = read_audio(src, channel, targetFs)
% [y, srcFs, nChannels] = read_audio(data, channel, targetFs, srcFs)
% Read (or accept) an audio waveform, reduce it to one channel, and resample
% it to targetFs.
%
% Parameters:
%   src       - full path to an audio file readable by audioread, OR a
%               numeric samples-by-channels matrix (then srcFs is required)
%   channel   - 0 to average all channels to mono, or a 1-based channel index
%   targetFs  - desired output sample rate in Hz
%   srcFs     - native sample rate of src, required only when src is numeric
%
% Returns:
%   y         - 1-by-N double row vector at targetFs
%   srcFs     - native sample rate of the source
%   nChannels - number of channels in the source, before reduction
%
% Errors:
%   stimgen:util:read_audio:FileNotFound  - path does not exist
%   stimgen:util:read_audio:ReadFailed    - audioread could not decode
%   stimgen:util:read_audio:InvalidChannel- channel exceeds the source
%   stimgen:util:read_audio:EmptyAudio    - source contained no samples

arguments
    src
    channel  (1,1) double {mustBeNonnegative, mustBeInteger}
    targetFs (1,1) double {mustBePositive, mustBeFinite}
    srcFs    (1,1) double {mustBeNonnegative} = 0
end

% --- Obtain raw samples-by-channels data ---
if isnumeric(src)
    if srcFs <= 0
        error('stimgen:util:read_audio:ReadFailed', ...
            'srcFs must be supplied and positive when passing numeric audio data.');
    end
    x = double(src);
else
    ffn = char(string(src));
    if ~isfile(ffn)
        error('stimgen:util:read_audio:FileNotFound', ...
            'Audio file not found: %s', ffn);
    end
    try
        [x, srcFs] = audioread(ffn);
    catch ME
        error('stimgen:util:read_audio:ReadFailed', ...
            'Could not read audio file "%s": %s', ffn, ME.message);
    end
    x = double(x);
end

if isvector(x)
    x = x(:); % conform to samples-by-1
end

nChannels = size(x, 2);

if isempty(x)
    error('stimgen:util:read_audio:EmptyAudio', ...
        'Audio source contains no samples.');
end

% --- Reduce to a single channel ---
if channel == 0
    x = mean(x, 2);
elseif channel > nChannels
    error('stimgen:util:read_audio:InvalidChannel', ...
        'Requested channel %d but the source has only %d channel(s).', ...
        channel, nChannels);
else
    x = x(:, channel);
end

% --- Resample to targetFs ---
% The default stimgen Fs is 97656.25 Hz, so the rate ratio is generally not a
% small rational. resample's non-uniform form takes the source time vector and
% an output rate directly, which avoids rat() producing unwieldy p/q pairs.
if abs(srcFs - targetFs) > eps(targetFs)
    tx = (0:numel(x)-1)' ./ srcFs;
    x  = resample(x, tx, targetFs);
end

y = reshape(x, 1, []);
