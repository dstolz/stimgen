function update(obj, d)
% update(obj, d)
% Render one live-update payload.
%
% Intermediate updates are dropped when they arrive faster than MinInterval;
% "start" and "done" always render, so the panels are correct at every run
% boundary no matter how fast the measurements came in.
%
% Rendering is guarded: a listener that throws is caught by MATLAB and
% re-warned on every notify, which for a per-measurement event means a console
% full of the same stack by the end of a sweep. A render error is instead
% logged once and rendering is suspended until the next run's "start" re-arms
% it -- the sweep itself is never at risk either way.
%
% Parameters:
%   d - stimgen.calibration.LiveUpdate
arguments
    obj
    d (1,1) stimgen.calibration.LiveUpdate
end

if d.Phase == "start"
    % A new run owns the panels: drop the previous run's traces rather than
    % leaving them to be silently overwritten point by point.
    if d.Stage ~= obj.LastStage_
        obj.reset();
    end
    obj.LastStage_ = d.Stage;
    obj.PrevSpectrum_ = {[], []};
    obj.drop_('spec_ghost');
    obj.RenderFailed_ = false;
elseif obj.RenderFailed_
    return
else
    now_ = toc(obj.Timer_);
    if d.Phase == "measure" && (now_ - obj.LastDraw_) < obj.MinInterval
        return
    end
end

try
    obj.render_(d);
catch ME
    obj.RenderFailed_ = true;
    stimgen.util.vprintf(0, 1, ...
        'LiveMonitor render failed; live plotting is suspended for this run.');
    stimgen.util.vprintf(0, 1, ME);
    return
end
obj.LastDraw_ = toc(obj.Timer_);

if d.Phase == "measure"
    drawnow limitrate;
else
    drawnow;
end
end
