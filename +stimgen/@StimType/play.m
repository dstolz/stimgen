function play(obj)
% play(obj)
% Audition the current Signal through the default audio device.
% Signal is normalized to unit peak before playback. Blocks until
% playback finishes, unless stop_playback() is called from another
% callback in the interim (see stimgen.StimPlayer.play_all).
%
% With a Background set, what plays is audition_signal: the stimulus in a
% short stretch of its background, normalized the same way, so the relative
% level of the two is kept and their absolute level is not.

fsValue = double(obj.get_selected_property_value_("Fs"));
y  = obj.audition_signal();
ap = audioplayer(y./max(abs(y)), fsValue);
obj.activePlayer_ = ap;

ap.play();
while isvalid(ap) && ap.isplaying()
    pause(0.01);
end

if isvalid(ap)
    delete(ap);
end
if isequal(obj.activePlayer_, ap)
    obj.activePlayer_ = [];
end
