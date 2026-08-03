function set_status_(obj, msg, kind)
% set_status_(obj, msg, kind)
% Write the status line. kind is "info" | "warn" | "error".

if nargin < 3
    kind = "info";
end
if isempty(obj.fig) || ~isvalid(obj.fig) || ~isfield(obj.h, 'Status')
    return
end

switch kind
    case "error", col = [0.70 0.10 0.10];
    case "warn",  col = [0.70 0.45 0.05];
    otherwise,    col = [0.25 0.25 0.30];
end

obj.h.Status.Text      = char(msg);
obj.h.Status.FontColor = col;

if kind == "error"
    stimgen.util.vprintf(1, 'PatchEditor: %s', char(msg));
end
end
