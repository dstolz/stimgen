function throw_if_cancelled_(obj)
% Pump the event queue so a Stop button click gets processed, then abort
% the calling run via error() if cancel() was invoked. Callers rely on the
% existing catch/rethrow blocks in calibrate_tones/calibrate_clicks/
% calibrate_swept_sine to discard partial data on this error, same as any
% other mid-run failure.
drawnow limitrate;
if obj.CancelRequested_
    error('stimgen:calibration:Engine:cancelled', 'Calibration cancelled by user.');
end
end
