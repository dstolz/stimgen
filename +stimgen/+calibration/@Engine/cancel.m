function cancel(obj)
% cancel(obj)
% Request cancellation of an in-progress calibrate_tones/calibrate_clicks/
% calibrate_swept_sine run. Cancellation is checked between measurements
% (once per frequency/duration/repeat), never mid-measurement, so it takes
% effect at the next boundary rather than immediately. calibrate_tones plays
% a whole burst train per acquisition, so its coarsest boundary is one train
% rather than one frequency; shorten MaxSequenceDuration for a faster stop.
% No-op if no
% cancellable run is in progress; the flag is cleared at the start of each
% run by reset_cancel_.
obj.CancelRequested_ = true;
end
