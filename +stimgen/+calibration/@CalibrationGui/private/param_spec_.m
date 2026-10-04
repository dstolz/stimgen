% Run parameter windows. Every run that needs parameters asks for them through
% parameter_dialog_, BEFORE with_busy_state_: typed fields (numeric edit fields
% with limits, dropdowns for fixed choices, a text field only for a list of
% numbers) that will not close on a value the engine would refuse. A typo is
% then corrected where it was typed instead of surfacing, after the button has
% been pressed, as a red Calibration Error. They replaced six inputdlg prompts
% raised inside the busy state.

function s = param_spec_(key, label, kind, value, options)
% s = param_spec_(key, label, kind, value, Name=Value)
% One field of a parameter_dialog_.
%
% Parameters:
%   key   - field name of the value in the returned struct
%   label - caption, units included
%   kind  - "numeric" | "integer" | "text" | "dropdown"
%   value - initial value; must lie inside Limits for a numeric kind
%   Limits    - [lo hi] for a numeric kind (default [-Inf Inf])
%   LowerOpen - true when lo itself is not allowed (a positive quantity)
%   Format    - ValueDisplayFormat for a numeric kind
%   Items     - string choices for a dropdown (also its values)
%   Tip       - tooltip text, from tooltips.json
%   Validate  - @(raw) value | error, run on OK; its error text is shown
%               in the window and the window stays open
arguments
    key (1,1) string
    label (1,1) string
    kind (1,1) string {mustBeMember(kind, ["numeric", "integer", "text", "dropdown"])}
    value
    options.Limits (1,2) double = [-Inf Inf]
    options.LowerOpen (1,1) logical = false
    options.Format (1,:) char = '%g'
    options.Items (1,:) string = strings(1, 0)
    options.Tip (1,:) char = ''
    options.Validate = []
end
s = struct('key', key, 'label', label, 'kind', kind, 'value', {value}, ...
    'limits', options.Limits, 'lowerOpen', options.LowerOpen, ...
    'format', options.Format, 'items', options.Items, 'tip', options.Tip, ...
    'validate', {options.Validate});
end
