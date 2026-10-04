function build_controls_panel_(obj)
% Left column: a scrolling stack of titled sections above a footer
% that does not scroll. One flat list of 23 rows made the reading
% order carry the whole workflow; the sections carry it instead, so
% a row is found by what it is about rather than by counting down
% from the top. Each section holds the settings a step consumes and
% then the button that consumes them.
%
% Stop, the conduction delay readout and the status line are in the
% footer because they are what is needed while a sweep is running,
% when the stack may be scrolled anywhere. The button that measures
% that delay is not: it is a step of the workflow like any other,
% and belongs with the microphone settings it is run against.
col = uigridlayout(obj.Grid, [2 1]);
col.Layout.Row = 1;
col.Layout.Column = 1;
col.RowHeight = {'1x', 92};
col.ColumnWidth = {'1x'};
col.Padding = [0 0 0 0];
col.RowSpacing = 6;

stack = uigridlayout(col, [5 1]);
stack.Layout.Row = 1;
stack.Layout.Column = 1;
stack.ColumnWidth = {'1x'};
stack.Padding = [0 0 0 0];
stack.RowSpacing = 6;
stack.Scrollable = 'on';

h = zeros(1, 5);

[g, h(1)] = obj.add_section_(stack, 1, 'Microphone', [24 24 24 30 30]);
obj.build_reference_section_(g);

[g, h(2)] = obj.add_section_(stack, 2, 'Calibration', [24 30 30 24]);
obj.build_calibration_section_(g);

[g, h(3)] = obj.add_section_(stack, 3, 'Verification & Equalization', [30 30 30 24]);
obj.build_verification_section_(g);

[g, h(4)] = obj.add_section_(stack, 4, 'Display', [24 24]);
obj.build_display_section_(g);

[g, h(5)] = obj.add_section_(stack, 5, 'Notes', 96);
obj.build_notes_section_(g);

stack.RowHeight = num2cell(h);

obj.build_footer_(col);
end
