function tf = supports_background_(~)
% tf = supports_background_(obj)
% Whether this class can be embedded in an ongoing background.
%
% True for every synthesized stimulus. A subclass with nothing a background
% could correctly be added to -- stimgen.CapturedSignal, a recording --
% returns false, and then carries none of the Background* properties in its
% UserProperties, GUI or serialized form.
tf = true;
end
