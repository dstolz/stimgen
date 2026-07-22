function play(obj)
% play(obj)
% Audition the current Signal through the default audio device.
% Signal is normalized to unit peak before playback. Blocks until
% playback finishes, unless stop_playback() is called from another
% callback in the interim (see stimgen.StimPlayer.play_all).

fsValue = double(obj.get_selected_property_value_("Fs"));
ap = audioplayer(obj.Signal./max(abs(obj.Signal)), fsValue);
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
