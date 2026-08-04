function update(obj, d)
% update(obj, d)
% Render one live-update payload.
%
% Intermediate updates are dropped when they arrive faster than MinInterval;
% "start" and "done" always render, so the panels are correct at every run
% boundary no matter how fast the measurements came in.
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
    obj.render_(d);
    drawnow;
    obj.LastDraw_ = toc(obj.Timer_);
    return
end

now_ = toc(obj.Timer_);
if d.Phase == "measure" && (now_ - obj.LastDraw_) < obj.MinInterval
    return
end

obj.render_(d);
obj.LastDraw_ = toc(obj.Timer_);

if d.Phase == "done"
    drawnow;
else
    drawnow limitrate;
end
end
