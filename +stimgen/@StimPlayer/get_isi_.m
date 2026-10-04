function get_isi_(obj)
% get_isi_() - Sample a scalar ISI from obj.ISI range.
% Updates obj.currentISI.
lo = obj.ISI(1);
hi = obj.ISI(2);
if hi > lo
    obj.currentISI = lo + rand * (hi - lo);
else
    obj.currentISI = lo;
end
end
