function cp = copyElement(obj)
% cp = copyElement(obj)
% Deep-copy hook for matlab.mixin.Copyable.
%
% StimType is Copyable but defines no copyElement, so the default shallow copy
% would leave the clone sharing this patch's component handle objects: changing
% one patch's NoiseSource band would change the other's. It would also leave
% the clone holding listener handles that belong to the original.
%
% Dynamic properties are not carried over by the default copy, so the clone
% needs its parameter set rebuilt explicitly. Note that assigning cp.Graph
% would NOT do it: the shallow copy already gave the clone an identical Graph,
% and Graph is AbortSet, so the setter would never run.

cp = copyElement@matlab.mixin.Copyable(obj);

% Drop everything that still points at the original.
cp.components_      = {};
cp.componentLabels_ = string.empty(1,0);
cp.paramProps_      = string.empty(1,0);
cp.paramListeners_  = {};
cp.lastOutputs_     = {};

cp.create_listeners();   % fresh PostSet listeners for the static properties
cp.rebuild_params_();    % fresh components and dynamic properties from Graph

for name = obj.paramProps_
    cp.(char(name)) = obj.(char(name));
end

cp.OutputNode = obj.OutputNode;
end
