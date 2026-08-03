function [modes, descriptions] = mode_names()
% [modes, descriptions] = stimgen.Patch.mode_names()
% The connection modes, with one-line descriptions for the editor.
%
% A connection carries a source node's output into a target node's parameter.
% Before the mode is applied, the source is normalized using its component's
% declared nominal_range into
%   u in [0 1]   (unipolar)
%   b in [-1 1]  (bipolar)
% so the meaning of Depth never depends on the source's actual amplitude.
%
%   Add    p = base + Depth*b            Depth is in the target's units.
%                                        Frequency + Add = FM, Depth in Hz.
%   AM     p = base*(1 - Depth + Depth*u) Classic amplitude modulation.
%                                        Depth 1 modulates fully to zero.
%   Ring   p = base*b                    Ring modulation / full bipolar gain.
%   Exp    p = base*2^(Depth*b)          Octave-scaled; Depth is in octaves.
%   Gate   p = base*(u >= Depth)         Hard gate at threshold Depth.
%   Direct p = m                          Replace the parameter with the raw
%                                        source. Used to patch audio into a
%                                        Mixer input.

modes = ["Add" "AM" "Ring" "Exp" "Gate" "Direct"];

descriptions = [ ...
    "p = base + Depth*b   (Depth in the target's units; use for FM)"
    "p = base*(1-Depth+Depth*u)   (classic AM; Depth 1 = full depth)"
    "p = base*b   (ring modulation)"
    "p = base*2^(Depth*b)   (Depth in octaves)"
    "p = base*(u >= Depth)   (hard gate at threshold Depth)"
    "p = m   (replace outright; use to patch audio into a Mixer input)"]';
end
