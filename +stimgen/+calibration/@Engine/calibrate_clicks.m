function calibrate_clicks(obj, durs, repeatCount)
% calibrate_clicks(obj)
% calibrate_clicks(obj, durs)
% calibrate_clicks(obj, durs, repeatCount)
%
% Sweep across click durations and build the click calibration LUT.
% Aborts and clears any prior click data on error.
%
% Durations shorter than one sample at the current Fs cannot be rendered, so
% they are dropped with a message rather than aborting the sweep partway
% through on ClickTrain's assertion.
%
% Parameters:
%   durs - (1,:) double click durations in seconds
%          (default: 10-point octave series, 10 us .. 5.12 ms)
%   repeatCount - (1,1) double positive integer number of
%                 measurements to average per duration
arguments
    obj
    durs (1,:) double = []
    repeatCount (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 1
end
obj.assert_adapter_();
obj.reset_cancel_();
fs = obj.Fs;

if isempty(durs)
    % Fixed durations rather than sample counts, so the same sweep is
    % requested regardless of the rig's sample rate.
    durs = 2.^(0:9) .* 10e-6;
end

% ClickTrain renders round(fs*dur) samples and requires at least one.
minDur     = 0.5 / fs;
resolvable = round(fs .* durs) >= 1;
if ~any(resolvable)
    error('stimgen:calibration:Engine:unresolvableClickDurations', ...
        'No requested click duration reaches one sample at Fs = %.0f Hz (minimum %.2f us).', ...
        fs, minDur*1e6);
end
if ~all(resolvable)
    stimgen.util.vprintf(0, 1, ...
        'Skipping %d click duration(s) below one sample at Fs = %.0f Hz (minimum %.2f us): %s', ...
        sum(~resolvable), fs, minDur*1e6, ...
        char(strjoin(compose('%.2f us', durs(~resolvable)*1e6).', ', ')));
    durs = durs(resolvable);
end

so            = stimgen.ClickTrain;
so.Fs         = fs;
so.Duration   = 0.05;
so.Rate       = 1;
so.WindowFcn  = "";
so.OnsetDelay = 0.01;

n          = numel(durs);
click_data = obj.empty_table_(n);
% Every abscissa up front, levels still NaN: that is what lets the monitor
% draw the points still to come alongside the ones already measured.
click_data.x = durs(:).';
clickMeasAll = nan(repeatCount, n);
clickSnrAll = nan(repeatCount, n);
clickNoiseFloorAll = nan(repeatCount, n);
clickThdAll = nan(repeatCount, n);
clickHeadroomAll = repmat(struct( ...
    'assumedFullScaleV', nan, ...
    'excitationPeakV', nan, ...
    'excitationHeadroomDb', nan, ...
    'excitationClippingLikely', false, ...
    'responsePeakV', nan, ...
    'responseHeadroomDb', nan, ...
    'responseFlatTopFraction', nan, ...
    'responseClippingLikely', false), repeatCount, n);

% Axis metadata for the live table; identical on every update of this run.
axisMeta = {'XLabel', "click duration (\mus)", 'XScale', "log", 'XFactor', 1e6};

obj.begin_run_();
obj.emit_live_("click", "start", 'Table', click_data, 'Total', n, ...
    'RepeatTotal', repeatCount, axisMeta{:});

try
    for i = 1:n
        obj.throw_if_cancelled_();
        stimgen.util.vprintf(1, '[%d/%d] Calibrating click %.2f μs', i, n, durs(i)*1e6);
        so.ClickDuration = durs(i);
        so.update_signal();

        y = obj.ExcitationVoltage .* so.Signal;
        obj.ExcitationSignal = y;

        m = 0;
        for rep = 1:repeatCount
            obj.throw_if_cancelled_();
            mRep = obj.measure_(y, "peak");
            m = m + mRep;
            clickMeasAll(rep, i) = mRep;
            response = obj.ResponseSignal;
            [clickNoiseFloorAll(rep, i), clickSnrAll(rep, i)] = obj.estimate_noise_snr_(response, fs, nan);
            clickThdAll(rep, i) = thd(response, fs);
            clickHeadroomAll(rep, i) = obj.estimate_headroom_(y, response);

            % Publish the running average rather than waiting for the point to
            % finish: on a many-pass run that is the difference between a curve
            % that grows steadily and one that stalls for seconds at a time.
            if obj.ShowLivePlots
                mAvg = mean(clickMeasAll(1:rep, i), 'omitnan');
                [splRep, voltRep] = obj.compute_spl_voltage_(mAvg, "peak");
                click_data.measurement(i) = mAvg;
                click_data.spl_db(i)      = splRep;
                click_data.voltage(i)     = voltRep;
                click_data.sd_db          = obj.level_sd_db_(clickMeasAll);
                obj.emit_live_("click", "measure", 'Table', click_data, ...
                    'Index', i, 'Total', n, ...
                    'Repeat', rep, 'RepeatTotal', repeatCount, axisMeta{:}, ...
                    'Metrics', struct('spl_db', splRep, 'voltage', voltRep, ...
                                      'snr_db', clickSnrAll(rep, i), ...
                                      'thd_db', clickThdAll(rep, i)));
            end
        end
        m = m ./ repeatCount;
        [spl, volt] = obj.compute_spl_voltage_(m, "peak");

        click_data.measurement(i) = m;
        click_data.spl_db(i)      = spl;
        click_data.voltage(i)     = volt;
    end
catch ME
    if isstruct(obj.CalibrationData)
        obj.CalibrationData = stimgen.calibration.Engine.rmfield_safe_(obj.CalibrationData, 'click');
    end
    stimgen.util.vprintf(0, 2, 'Click calibration aborted: %s', ME.message);
    rethrow(ME);
end

cd_out = obj.commit_cal_data_();
clickSensitivity = click_data.spl_db(:) - 20*log10(max(obj.ExcitationVoltage, eps));
clickRepeatability = obj.repeatability_stats_(clickMeasAll);
clickHeadroom = obj.aggregate_headroom_(clickHeadroomAll(:));
clickNoiseFloor = mean(clickNoiseFloorAll, 1, 'omitnan');
clickSnr = mean(clickSnrAll, 1, 'omitnan');
clickThd = mean(clickThdAll, 1, 'omitnan');
cd_out.click = struct( ...
    'duration',    durs(:), ...
    'measurement', click_data.measurement(:), ...
    'spl_db',      click_data.spl_db(:), ...
    'voltage',     click_data.voltage(:), ...
    'metrics', struct( ...
        'calibrated_level_sensitivity_db_per_v', clickSensitivity, ...
        'noise_floor_db', clickNoiseFloor(:), ...
        'snr_db', clickSnr(:), ...
        'thd_db', clickThd(:), ...
        'h2_db', nan(size(clickThd(:))), ...
        'h3_db', nan(size(clickThd(:))), ...
        'repeatability', clickRepeatability, ...
        'clipping_headroom', clickHeadroom));
obj.CalibrationData = cd_out;
obj.CalibrationTimestamp = datetime('now');

click_data.sd_db = obj.level_sd_db_(clickMeasAll);
obj.emit_live_("click", "done", 'Table', click_data, ...
    'Index', n, 'Total', n, 'Repeat', repeatCount, 'RepeatTotal', repeatCount, ...
    'Progress', 1, axisMeta{:});
end
