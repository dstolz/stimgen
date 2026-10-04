function build_calibration_section_(obj, g)
% The level every sweep's table is anchored to. The drive voltage
% and the tone burst rise/fall time are also settings every sweep
% runs at, but live in Options > Excitation Settings... instead: a
% window rather than a place in this column, since neither is a
% step of its own.
obj.NormativeField = numeric_row_(g, 1, 'Normative Value (dB SPL)', ...
    [1, 180], '%.1f');

% Tones and the refinement that follows them share the top row,
% and the two optional sweeps the row below: the layout says which
% one an experiment normally needs. The refinement is a modifier of
% the sweep beside it rather than a step of its own, so it reads as
% one line -- run tones, refined -- instead of as a setting several
% rows away that has to be remembered.
%
% Its own row rather than a check_row_ caption in column 1: that
% column belongs to the button here, and a checkbox carrying its
% own label is the only way to put a toggle beside one.
row = uigridlayout(g, [1 2]);
row.Layout.Row = 2;
row.Layout.Column = [1 2];
row.ColumnWidth = {'1x', 186};
row.Padding = [0 0 0 0];
row.ColumnSpacing = 8;

obj.BtnTones = action_button_(row, 1, 1, 'Calibrate Tones', ...
    'BtnTones', @(~,~) obj.on_calibrate_tones_());

% Follows each tone or click sweep with Engine.refine_tones/
% refine_clicks: the finished table is tested at its own points
% and corrected from the errors that come back, until every point
% lands within a target accuracy. The sweep dialog collects the
% pass limit and target while this is checked.
obj.IterativeCheck = uicheckbox(row, Text='Iterative Level Refinement', ...
    Tooltip=stimgen.util.tooltip('CalibrationGui', 'IterativeRefinement'));
obj.IterativeCheck.Layout.Row = 1;
obj.IterativeCheck.Layout.Column = 2;

obj.BtnClicks = action_button_(g, 3, 1, 'Calibrate Clicks', ...
    'BtnClicks', @(~,~) obj.on_calibrate_clicks_());
obj.BtnSweptSine = action_button_(g, 3, 2, 'Calibrate Swept Sine', ...
    'BtnSweptSine', @(~,~) obj.on_calibrate_swept_sine_());

% Directly under the sweep it redirects tone lookups to.
obj.ToneSweptSineCheck = check_row_(g, 4, 'Tone Lookup From Swept Sine', ...
    stimgen.util.tooltip('CalibrationGui', 'ToneLutFromSweptSine'), ...
    @(~,~) obj.on_tone_lut_source_());
end
