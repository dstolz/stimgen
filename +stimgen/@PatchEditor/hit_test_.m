function hit = hit_test_(obj, pt)
% hit = hit_test_(obj, pt)
% What lies under a canvas point, for the current geometry and graph.

hit = stimgen.PatchEditor.hit_test_at_(obj.geom, obj.Patch.Graph, pt);
end
