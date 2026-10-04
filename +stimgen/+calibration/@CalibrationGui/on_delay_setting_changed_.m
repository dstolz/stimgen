function on_delay_setting_changed_(obj)
% The probe's parameters are this window's own -- no engine holds
% them -- so the object keeps them and the window is a view.
obj.DelayMaxMs_ = obj.DelayMaxField.Value;
obj.DelayNumClicks_ = obj.DelayClicksField.Value;
end
