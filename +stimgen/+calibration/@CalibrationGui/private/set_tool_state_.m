function set_tool_state_(h, tf)
% Pressed state of a toolbar toggle tool. Same guard, same reason.
if ~isempty(h) && all(isgraphics(h))
    h.State = matlab.lang.OnOffSwitchState(tf);
end
end
