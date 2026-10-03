function c = list
% c = stimgen.StimType.list
% Enumerate available concrete stimgen stimulus class names.
%
% Candidates are the loose .m files in +stimgen/; a candidate is offered only if
% it is a concrete subclass of StimType. Filtering on the class rather than on a
% list of names is what keeps the package's other classes (StimPlay, HardwareHost,
% LogSink, ...) out of the stimulus dropdowns without anyone having to remember
% to add them to an exclusion list. There is no name-based exclusion at all:
% StimType itself and StimCalibration live in class folders the glob does not
% reach, and every other loose file is judged by its class alone.
r = which('stimgen.StimType');
pth = fileparts(fileparts(r)); % up from @StimType to +stimgen
d = dir(fullfile(pth,'*.m'));
f = {d.name};
c = cellfun(@(a) a(1:end-2),f,'uni',0);

base = ?stimgen.StimType;
keep = false(size(c));
for k = 1:numel(c)
    try
        mc = meta.class.fromName(['stimgen.' c{k}]);
        keep(k) = ~isempty(mc) && ~mc.Abstract && mc < base;
    catch
        keep(k) = false;    % not a class (a script or function): not a stimulus
    end
end
c = c(keep);
end
