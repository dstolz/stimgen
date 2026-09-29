function refresh_ui_(obj)
% refresh_ui_(obj)
% Bring the header, the stimulus summary, the control enable states and the
% result table up to date with the object.
%
% One writer for all of it. Every callback changes state and then calls here,
% rather than each one updating the parts it happens to know about, so a
% control cannot be left enabled for an action that is no longer possible.

if ~obj.is_open()
    return
end

h = obj.handles;

update_header_(obj, h);
update_stimulus_label_(obj, h);
update_variant_(obj, h);
update_enable_(obj, h);
update_results_table_(obj, h);
end % refresh_ui_


% =========================================================================

function update_header_(obj, h)
% One line naming what is loaded and what it will be played through.

if isempty(obj.Stimulus) || ~isvalid(obj.Stimulus)
    h.HeaderLabel.Text = 'No stimulus loaded.';
    return
end

fsHw = obj.Engine.Fs;
if isempty(obj.Engine.Adapter) || ~isfinite(fsHw) || fsHw <= 0
    hwText = 'offline — no acquisition hardware';
else
    hwText = sprintf('hardware %.7g Hz', fsHw);
end

parts = split(string(class(obj.Stimulus)), ".");

h.HeaderLabel.Text = sprintf('%s  [%s]   |   %.7g Hz   |   %s', ...
    char(obj.StimulusLabel), char(parts(end)), obj.Stimulus.Fs, hwText);
end


function update_stimulus_label_(obj, h)
% The stimulus panel's summary block: what it is, and anything that would stop
% it being played.

if isempty(obj.Stimulus) || ~isvalid(obj.Stimulus)
    h.StimLabel.Text = 'No stimulus loaded.';
    return
end

stimObj = obj.Stimulus;
lines = string.empty(0, 1);

try
    lines(end+1) = string(stimObj.current_parameter_summary());
catch
    lines(end+1) = obj.StimulusLabel;
end

fsHw = obj.Engine.Fs;
if ~isempty(obj.Engine.Adapter) && isfinite(fsHw) && fsHw > 0 ...
        && abs(double(stimObj.Fs) - fsHw) > 1e-6
    lines(end+1) = sprintf('Rate mismatch: stimulus %.7g Hz, hardware %.7g Hz.', ...
        stimObj.Fs, fsHw);
end

if ~logical(stimObj.ApplyCalibration)
    lines(end+1) = "Calibration is off — Sound Level is nominal.";
end

h.StimLabel.Text = char(strjoin(lines, newline));
end


function update_variant_(obj, h)
% The variant row: which combination runs play, out of how many, and whether
% each run steps. The spinner shows VariantIndex -- the combination the next
% run plays -- rather than the stimulus's own active index, which moves by
% itself and is put back at the start of a run.

n   = variant_count_(obj);
idx = min(max(round(obj.VariantIndex), 1), n);

sp = h.VariantSpinner;
% A spinner's limits must be increasing, so a single combination still gets
% [1 2]; the control is disabled then. Value goes to 1 first so the new limits
% never have to be set around a value outside them.
sp.Value  = 1;
sp.Limits = [1 max(n, 2)];
sp.Value  = idx;

h.VariantCountLabel.Text = sprintf('of %d', n);
h.StepVariantCheck.Value = obj.StepVariant;
end


function n = variant_count_(obj)
% Combinations the loaded stimulus has; 1 when none is loaded.
n = 1;
if isempty(obj.Stimulus) || ~isvalid(obj.Stimulus)
    return
end
try
    info = obj.Stimulus.get_variant_info();
    n = max(1, info.NumCombinations);
catch
end
end


function update_enable_(obj, h)
% Which actions are possible right now.

running  = obj.Running_;
hasStim  = ~isempty(obj.Stimulus) && isvalid(obj.Stimulus);
hasHw    = ~isempty(obj.Engine.Adapter);
hasResult = ~isempty(fieldnames(obj.Results));
hasRec   = ~isempty(obj.Recording) && isvalid(obj.Recording);
multi    = variant_count_(obj) > 1;

set_enable_(h.VariantSpinner,   ~running && multi);
set_enable_(h.StepVariantCheck, ~running && multi);

set_enable_(h.LoadBtn,      ~running);
set_enable_(h.OpenTool,     ~running);
set_enable_(h.MatchRateBtn, ~running && hasStim && hasHw);
set_enable_(h.PreField,     ~running);
set_enable_(h.PostField,    ~running);
set_enable_(h.RepeatsField, ~running);
set_enable_(h.SaveTool,     ~running && hasResult);
set_enable_(h.ShotTool,     ~running);
set_enable_(h.SummaryTool,  hasResult);
set_enable_(h.InspectStimTool,    hasStim);
set_enable_(h.InspectCaptureTool, hasRec);

% Run doubles as Cancel while a capture is in flight, so it stays enabled --
% a capture that cannot be stopped is worse than one that cannot be started.
if running
    h.RunBtn.Text = 'Cancel';
    set_enable_(h.RunBtn,  true);
    set_enable_(h.RunTool, true);
else
    h.RunBtn.Text = 'Run Spot Check';
    set_enable_(h.RunBtn,  obj.can_run());
    set_enable_(h.RunTool, obj.can_run());
end
end


function update_results_table_(obj, h)
% The reduction, as Measure/Value rows.

if isempty(fieldnames(obj.Results))
    h.ResultsTable.Data = cell(0, 2);
    return
end

r = obj.Results;
rows = cell(0, 2);

% A click (or a peak-referenced sound file) is measured at its peak, so its
% requested and measured levels are dB peSPL; the noise floor stays an rms.
lu = stimgen.SpotCheck.level_unit_(r);
rows(end+1, :) = {'— Level —', ''};
if isfinite(r.measured.level_error_db)
    rows(end+1, :) = {['Requested (' lu ')'], num_(r.stimulus.requested_level_db, '%.1f')};
    rows(end+1, :) = {['Measured (' lu ')'],  num_(r.measured.level_db_spl, '%.1f')};
    rows(end+1, :) = {'Error (dB)',         num_(r.measured.level_error_db, '%+.2f')};
else
    rows(end+1, :) = {['Measured (' lu ')'],  num_(r.measured.level_db_spl, '%.1f')};
    rows(end+1, :) = {['Requested (' lu ')'], 'not comparable'};
end
rows(end+1, :) = {'Measured as',        char(r.stimulus.level_reference)};
rows(end+1, :) = {'Noise floor (dB SPL)', num_(r.measured.noise_db_spl, '%.1f')};
rows(end+1, :) = {'SNR (dB)',           num_(r.measured.snr_db, '%.1f')};

rows(end+1, :) = {'— Recording —', ''};
rows(end+1, :) = {'RMS (V)',            num_(r.measured.rms_v, '%.5g')};
rows(end+1, :) = {'Peak (V)',           num_(r.measured.peak_v, '%.5g')};
rows(end+1, :) = {'Crest factor (dB)',  num_(r.measured.crest_factor_db, '%.1f')};
rows(end+1, :) = {'Fundamental (Hz)',   num_(r.measured.fundamental_hz, '%.4g')};
rows(end+1, :) = {'THD (%)',            num_(r.measured.thd_percent, '%.3f')};
rows(end+1, :) = {'Clipping',           yesno_(r.measured.clipping)};
rows(end+1, :) = {'Conduction delay (ms)', num_(r.measured.delay_s * 1e3, '%.2f')};

% Side by side with the stimulus: a difference in these is the whole point of
% a spot check, and it is far easier to see on adjacent rows than by opening
% two inspector windows.
rows(end+1, :) = {'— Stimulus —', ''};
rows(end+1, :) = {'Crest factor (dB)',  num_(r.stimulus_metrics.CrestFactorDb, '%.1f')};
rows(end+1, :) = {'Fundamental (Hz)',   num_(r.stimulus_metrics.FundamentalHz, '%.4g')};
rows(end+1, :) = {'THD (%)',            num_(r.stimulus_metrics.ThdPercent, '%.3f')};

if ~isempty(r.warnings)
    rows(end+1, :) = {'— Warnings —', ''};
    for k = 1:numel(r.warnings)
        rows(end+1, :) = {sprintf('%d', k), char(r.warnings(k))}; %#ok<AGROW>
    end
end

h.ResultsTable.Data = rows;
end


% =========================================================================

function set_enable_(handle, tf)
% Enable/disable one component, tolerating one that was never built.
if isempty(handle) || ~isvalid(handle)
    return
end
if tf
    handle.Enable = 'on';
else
    handle.Enable = 'off';
end
end


function text = num_(value, spec)
% Format a scalar, rendering a missing value as "n/a".
if isempty(value) || ~isscalar(value) || ~isfinite(value)
    text = 'n/a';
    return
end
text = sprintf(spec, value);
end


function text = yesno_(tf)
if tf
    text = 'yes';
else
    text = 'no';
end
end
