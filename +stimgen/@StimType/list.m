function c = list
% c = stimgen.StimType.list
% Enumerate available concrete stimgen stimulus class names.
%
% Two layouts are scanned in +stimgen: loose Class.m files (Tone, Noise, ...)
% and @Class class folders. Loose files keep the historical filename-based
% filter; class folders are admitted only when the class actually derives from
% stimgen.StimType, so infrastructure folders (@StimType, @StimPlayer,
% @StimInspector, @StimCalibration) are excluded without needing a name list.
r = which('stimgen.StimType');
pth = fileparts(fileparts(r)); % up from @StimType to +stimgen

d = dir(fullfile(pth,'*.m'));
f = {d.name};
f(ismember(f,{'StimType.m','StimPlay.m','donotsavedatafcn.m','multiTone.m','HardwareHost.m'})) = [];
f(contains(f,'Calib')) = [];
c = cellfun(@(a) a(1:end-2),f,'uni',0);

dd = dir(fullfile(pth,'@*'));
dd = dd([dd.isdir]);
for i = 1:numel(dd)
    name = dd(i).name(2:end); % strip '@'
    if isempty(name) || any(strcmp(c, name))
        continue
    end
    mc = meta.class.fromName(['stimgen.' name]);
    if isempty(mc) || mc.Abstract
        continue
    end
    if mc < ?stimgen.StimType % meta.class inheritance test, covers indirect subclasses
        c{end+1} = name; %#ok<AGROW>
    end
end
c = sort(c);
end
