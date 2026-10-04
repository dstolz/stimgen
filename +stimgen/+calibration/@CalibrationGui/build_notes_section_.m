function build_notes_section_(obj, g)
% Free text about this calibration, in the operator's own words:
% which speaker and microphone, where they stood, what was odd
% about the rig that day. Last in the column because it is
% written once at the end rather than consulted during a step,
% and full width because prose does not belong in the caption/
% field pair every other row uses.
%
% It is the one control here that travels in the .esgc rather
% than in this window's preferences -- a note about Tuesday's
% calibration must not turn up on Wednesday's.
% No Placeholder property: it arrived after this package's
% R2021a baseline, and the section title and tooltip already say
% what the box is for.
obj.NotesArea = uitextarea(g, ...
    Tooltip=stimgen.util.tooltip('CalibrationGui', 'Notes'), ...
    ValueChangedFcn=@(~,~) obj.commit_notes_());
obj.NotesArea.Layout.Row = 1;
obj.NotesArea.Layout.Column = [1 2];
end
