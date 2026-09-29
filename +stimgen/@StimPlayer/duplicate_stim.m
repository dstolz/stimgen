function duplicate_stim(obj, ~, ~)
% duplicate_stim(obj) - Add a copy of the selected bank item directly below it.
% The copy is a freshly constructed StimType given the source's settings --
% the same base and UserProperties set save_bank/load_bank round-trip --
% rather than copy(), which would carry over the source's property
% listeners and GUI widget handles. The calibration is shared, not cloned,
% so the whole bank keeps one calibration state. Presentation counters
% start from zero, as for any newly added item.

h = obj.handles;

if isempty(h.BankList.ItemsData) || isempty(h.BankList.Value)
	obj.set_status_("Select a stimulus to duplicate.");
	return
end

idx = h.BankList.Value;
if idx < 1 || idx > numel(obj.StimPlayObjs)
	return
end

try
	src    = obj.StimPlayObjs(idx);
	srcObj = src.CurrentStimObj;

	stimObj = feval(class(srcObj));

	baseProps = {'SoundLevel','Duration','WindowDuration','WindowFcn', ...
	             'ApplyCalibration','ApplyWindow','Fs', ...
	             'VariantSelectionMode','VariantCombinationMode', ...
	             'VariantSelectorClass','VariantSelectorConfig', ...
	             'VariantReselectOnUpdate','DisplayName'};
	for j = 1:numel(baseProps)
		p = baseProps{j};
		if isprop(srcObj, p)
			stimObj.(p) = srcObj.(p);
		end
	end

	for j = 1:numel(srcObj.UserProperties)
		p = char(srcObj.UserProperties(j));
		if isprop(srcObj, p)
			stimObj.(p) = srcObj.(p);
		end
	end

	if isa(srcObj.Calibration, 'stimgen.StimCalibration')
		stimObj.Calibration = srcObj.Calibration;
	end

	% Open on the combination the source is showing.
	try
		info = srcObj.get_variant_info();
		if info.NumCombinations > 1
			stimObj.set_variant_index(info.ActiveIndex);
		end
	catch
	end

	sp               = stimgen.StimPlay(stimObj);
	sp.Fs            = obj.Fs;
	sp.Reps          = src.Reps;
	sp.ISI           = src.ISI;
	sp.SelectionType = src.SelectionType;
	sp.Name          = unique_copy_name_(src.Name, [obj.StimPlayObjs.Name]);

	obj.StimPlayObjs = [obj.StimPlayObjs(1:idx); sp; obj.StimPlayObjs(idx+1:end)];

	obj.refresh_listbox_;
	obj.refresh_combo_controls_;
	obj.update_counter_;
	obj.update_calibration_status_;

	h.BankList.Value = idx + 1;
	obj.on_bank_selection_changed(h.BankList, []);

	stimgen.util.vprintf(2, 'StimPlayer: duplicated "%s" as "%s"', src.Name, sp.Name);
	obj.set_status_("Duplicated stimulus: " + string(src.Name) + " -> " + string(sp.Name));
catch ME
	obj.report_gui_error_(ME, "Duplicate Stimulus Error", ...
		"StimPlayer could not duplicate the selected stimulus.");
end
end


function name = unique_copy_name_(base, existing)
% "Tone_1" -> "Tone_1_copy", then "Tone_1_copy2", "Tone_1_copy3", ...
name = string(base) + "_copy";
k = 1;
while any(existing == name)
	k = k + 1;
	name = string(base) + "_copy" + k;
end
end
