function dlg = edit_capture_settings(obj)
% edit_capture_settings(obj)
% dlg = edit_capture_settings(obj)
% Set how capture_stim acquires: the silence before and after the stimulus,
% and how many acquisitions to average.
%
% Shown in milliseconds, stored in seconds, per the package convention.
% OK applies the values and remembers them for the next session -- the
% round-trip latency the tail has to cover is a property of the rig, not of
% one sitting -- and Cancel changes nothing.
%
% Modal but not blocking: the call returns at once, and OK/Cancel close the
% window. The figure is returned so a caller (or a test) can drive it; its
% fields are tagged CapturePreDelayField, CapturePostDelayField and
% CaptureRepeatsField, its buttons CaptureSettingsOK and CaptureSettingsCancel.
%
% Returns:
%   dlg - the dialog's uifigure (only when asked for)
%
% See also: stimgen.StimPlayer.capture_stim

tip = @(key) stimgen.util.tooltip('StimPlayer', key);

w = 380; hgt = 210;
pos = [200 200 w hgt];
if ~isempty(obj.hFig) && isvalid(obj.hFig)
    p = obj.hFig.Position;
    pos(1:2) = p(1:2) + (p(3:4) - [w hgt]) / 2;
end

f = uifigure('Name', 'Capture Settings', 'Position', pos, ...
    'WindowStyle', 'modal', 'Resize', 'off');

g = uigridlayout(f, [5 2]);
g.ColumnWidth = {150, '1x'};
g.RowHeight   = {24, 24, 24, '1x', 28};
g.Padding     = [10 10 10 10];
g.RowSpacing  = 6;

pre  = field_(g, 1, 'Lead-in (ms):', obj.CapturePreDelay * 1e3, [0 1e4], ...
    '%.0f', 'CapturePreDelayField', tip('CapturePreDelay'));
post = field_(g, 2, 'Tail (ms):', obj.CapturePostDelay * 1e3, [0 1e4], ...
    '%.0f', 'CapturePostDelayField', tip('CapturePostDelay'));
reps = field_(g, 3, 'Acquisitions to average:', obj.CaptureRepeats, [1 1000], ...
    '%d', 'CaptureRepeatsField', tip('CaptureRepeats'));
reps.RoundFractionalValues = 'on';

note = uilabel(g, 'WordWrap', 'on', 'FontColor', [0.35 0.35 0.35], ...
    'Text', ['The noise floor is measured over the lead-in. The tail bounds ' ...
             'the search for the response, so it must be longer than the ' ...
             'rig''s round trip (converter latency plus the acoustic path).']);
note.Layout.Row    = 4;
note.Layout.Column = [1 2];

bg = uigridlayout(g, [1 3]);
bg.Layout.Row    = 5;
bg.Layout.Column = [1 2];
bg.ColumnWidth   = {'1x', 90, 90};
bg.Padding       = [0 0 0 0];

ok = uibutton(bg, 'Text', 'OK', 'Tag', 'CaptureSettingsOK', 'FontWeight', 'bold');
ok.Layout.Column = 2;
ok.ButtonPushedFcn = @(~,~) on_ok_();

cancel = uibutton(bg, 'Text', 'Cancel', 'Tag', 'CaptureSettingsCancel');
cancel.Layout.Column = 3;
cancel.ButtonPushedFcn = @(~,~) delete(f);

if nargout > 0
    dlg = f;
end

    function on_ok_()
        % Apply all three or none: a value the property rejects leaves
        % every setting as it was and the dialog open to correct it.
        previous = [obj.CapturePreDelay, obj.CapturePostDelay, obj.CaptureRepeats];
        try
            obj.CapturePreDelay  = pre.Value / 1e3;
            obj.CapturePostDelay = post.Value / 1e3;
            obj.CaptureRepeats   = reps.Value;
        catch ME
            obj.CapturePreDelay  = previous(1);
            obj.CapturePostDelay = previous(2);
            obj.CaptureRepeats   = previous(3);
            uialert(f, ME.message, 'Capture Settings', 'Icon', 'error');
            return
        end
        obj.save_capture_settings_();
        obj.set_status_(sprintf('Capture: %.0f ms lead-in, %.0f ms tail, %d acquisition(s).', ...
            obj.CapturePreDelay * 1e3, obj.CapturePostDelay * 1e3, obj.CaptureRepeats));
        delete(f);
    end
end


function h = field_(g, row, labelText, value, limits, fmt, tag, tooltipText)
% One labelled numeric field on the dialog's grid.
lbl = uilabel(g, 'Text', labelText, 'HorizontalAlignment', 'right', ...
    'Tooltip', tooltipText);
lbl.Layout.Row    = row;
lbl.Layout.Column = 1;

h = uieditfield(g, 'numeric', 'Tag', tag, 'Limits', limits, ...
    'ValueDisplayFormat', fmt, 'Value', value, 'Tooltip', tooltipText);
h.Layout.Row    = row;
h.Layout.Column = 2;
end
