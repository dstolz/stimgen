function reset(obj)
% reset(obj)
% Delete every graphics object this monitor created and forget the cached
% spectrum. Objects drawn into the same axes by anyone else are untouched, so
% a host GUI can call this before drawing its own static plots.

keys = fieldnames(obj.H_);
for k = 1:numel(keys)
    h = obj.H_.(keys{k});
    delete(h(isgraphics(h)));
end
obj.H_ = struct();
obj.PrevSpectrum_ = {[], []};
obj.LastStage_ = "";
end
