function tf = alternates_polarity(obj) %#ok<MANU>
% tf = alternates_polarity(obj)
% True when the presenter should invert every other presentation of the
% active variant.
%
% Alternating polarity cancels the stimulus artifact in an averaged response.
% A stimulus that alternates WITHIN its own waveform (ClickTrain's Polarity = 0
% flips each click of the train) has nothing left for the presenter to do, so
% the base class answers false. One that alternates ACROSS presentations (a
% Tone with Polarity = 0, a ClickTrain with Polarity = 2) generates the positive
% waveform and overrides this to hand the flipping to whoever presents it --
% StimPlayer's hardware playback, or a host such as MABR.
%
% Returns:
%   tf - logical scalar.
%
% See also: stimgen.Tone
tf = false;
end
