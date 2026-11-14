function S = presentation_log_struct_(obj)
% S = presentation_log_struct_() - The presentation log as the struct a log file holds.
% The one layout of a saved presentation log: the automatic save at the
% end of a hardware Run and save_presentation_log both write it.
%
% The run's settings and bank come from RunInfo, the snapshot timer_startfcn
% took, not from the player as it is now -- the bank may have been edited
% since the run ended. The trial columns are row-aligned: row k of each
% describes presentation k.
%
% Returns:
%   S - struct:
%     FormatVersion    1
%     SavedAt          'yyyy-mm-ddTHH:MM:SS', local time, when this was built
%     RunStartedAt     same form; when the timer started
%     RunStoppedAt     same form; '' while the run has not stopped
%     HardwareRun      true if the run had hardware output; false = dry run
%     Completed        true if every presentation the bank asked for was made
%     NPresented       presentations logged
%     NTotal           presentations a full run of the bank makes
%     Fs               bank sample rate, Hz
%     ISI              [min max] onset-to-onset interval, s
%     SelectionType    "Serial" | "Shuffle", the order of bank items
%     BankFile         the .spl the bank came from ("" = none)
%     CalibrationFile  the calibration loaded in the player ("" = none/embedded)
%     BankNames        bank item names, in bank order
%     StimOrder        (n,1) bank item index presented
%     StimOrderTime    (n,1) seconds since the run started
%     StimPolarity     (n,1) sign played, +1 / -1
%     StimVariant      (n,1) variant combination index played
%     StimLateness     (n,1) seconds the trigger came after it was due
%     StimRecord       (n,1) cell: StimType.generation_record of the
%                      stimulus triggered ([] if it could not be made)
%     Bank             the bank as save_bank writes it (ISI, SelectionType,
%                      NItems, Items), as it was when the run started
info = obj.RunInfo;

S = struct();
S.FormatVersion   = 1;
S.SavedAt         = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
S.RunStartedAt    = field_(info, 'StartedAt', '');
S.RunStoppedAt    = field_(info, 'StoppedAt', '');
S.HardwareRun     = logical(field_(info, 'HardwareRun', false));
S.Completed       = logical(field_(info, 'Completed', false));
S.NPresented      = numel(obj.StimOrder);
S.NTotal          = field_(info, 'NTotal', NaN);
S.Fs              = field_(info, 'Fs', obj.Fs);
S.ISI             = field_(info, 'ISI', obj.ISI);
S.SelectionType   = field_(info, 'SelectionType', obj.SelectionType);
S.BankFile        = field_(info, 'BankFile', obj.BankFile);
S.CalibrationFile = field_(info, 'CalibrationFile', obj.CalibrationFile);
S.BankNames       = field_(info, 'BankNames', string.empty(0, 1));
S.StimOrder       = obj.StimOrder;
S.StimOrderTime   = obj.StimOrderTime;
S.StimPolarity    = obj.StimPolarity;
S.StimVariant     = obj.StimVariant;
S.StimLateness    = obj.StimLateness;
S.StimRecord      = obj.StimRecord;
S.Bank            = field_(info, 'Bank', []);
end


function v = field_(s, name, fallback)
% A field of the run snapshot, or the fallback when the snapshot lacks it.
if isfield(s, name)
    v = s.(name);
else
    v = fallback;
end
end
