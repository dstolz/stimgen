function update_runtime_state_(obj)
obj.refresh_sample_rate_label_();
obj.refresh_conduction_delay_label_();
obj.refresh_level_reference_label_();

hasAdapter = ~isempty(obj.Engine.Adapter);
if hasAdapter
    obj.BtnReference.Enable = 'on';
    obj.BtnBackground.Enable = 'on';
    obj.BtnTones.Enable = 'on';
    obj.BtnClicks.Enable = 'on';
    obj.BtnSweptSine.Enable = 'on';
    % The delay probe plays and records and needs nothing else:
    % no reference, no table. It is measurable the moment there is
    % hardware, which is what makes it usable to check a rig
    % before calibrating it.
    obj.BtnDelay.Enable = 'on';
else
    obj.BtnReference.Enable = 'off';
    obj.BtnBackground.Enable = 'off';
    obj.BtnTones.Enable = 'off';
    obj.BtnClicks.Enable = 'off';
    obj.BtnSweptSine.Enable = 'off';
    obj.BtnDelay.Enable = 'off';
end

% Either LUT can drive the equalizer; Engine.design_filter picks.
C = obj.Engine.CalibrationData;
hasLut = obj.Engine.IsCalibrated && ...
    ((isfield(C, 'tone') && ~isempty(C.tone)) || ...
     (isfield(C, 'swept_sine') && ~isempty(C.swept_sine)));
% Testing the tone lookup needs a table to test and hardware to
% play it through. hasLut is the right condition rather than a
% tone-only one: with Tone Lookup From Swept Sine set, the sweep is
% the table a Tone stimulus is scaled by, so it is what the test
% has to verify.
if hasLut && hasAdapter
    obj.BtnTestTones.Enable = 'on';
else
    obj.BtnTestTones.Enable = 'off';
end

% The click table has no alternative source: only calibrate_clicks
% ever writes it, so its own data is the condition.
hasClickLut = obj.Engine.IsCalibrated && ...
    isfield(C, 'click') && ~isempty(C.click);
if hasClickLut && hasAdapter
    obj.BtnTestClicks.Enable = 'on';
else
    obj.BtnTestClicks.Enable = 'off';
end

if hasLut
    obj.BtnFilter.Enable = 'on';
else
    obj.BtnFilter.Enable = 'off';
end

% Testing needs both a designed (or loaded) filter and hardware to
% play it through.
hasFilter = obj.Engine.IsCalibrated && ...
    isfield(C, 'filter') && ~isempty(C.filter);
if hasFilter && hasAdapter
    obj.BtnTestFilter.Enable = 'on';
else
    obj.BtnTestFilter.Enable = 'off';
end

% Copying reads the taps that already exist, so unlike testing it
% asks nothing of the hardware -- a filter loaded from a .esgc on a
% machine with no rig attached is still exportable.
if hasFilter
    obj.BtnCopyFilter.Enable = 'on';
else
    obj.BtnCopyFilter.Enable = 'off';
end
end
