function stop_playback(obj)
% stop_playback(obj)
% Immediately halt any in-progress playback started by play(). No-op if
% nothing is currently playing.

if ~isempty(obj.activePlayer_) && isvalid(obj.activePlayer_) && obj.activePlayer_.isplaying()
    obj.activePlayer_.stop();
end
