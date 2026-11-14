function was = hold_updates(obj, tf)
% was = hold_updates(obj, tf)
% Suspend (true) or resume (false) regeneration on property change.
%
% Every public observable property regenerates Signal when it is assigned
% (create_listeners / onPropertyChanged). That is right for an edit and wrong
% for a caller that assigns many properties in a row: the stimulus would be
% synthesized once per property, against a state that is only partly
% restored, and each of those generations would also advance the variant
% selection. Such a caller holds updates, assigns, releases, and then calls
% update_signal() once itself:
%
%   was = obj.hold_updates(true);
%   ... assign properties ...
%   obj.hold_updates(was);
%   obj.update_signal();
%
% Releasing does NOT regenerate; the caller decides whether and when.
% StimType.fromStruct and StimPlayer's remembered settings are the users.
% While held, a variant-policy edit still invalidates the combination cache
% (it never regenerated anyway), and property validation still runs.
%
% Public but hidden for the same reason as build_prop_widget: StimPlayer is
% not a StimType subclass.
%
% Parameters:
%   tf  - (1,1) logical. true holds, false resumes.
%
% Returns:
%   was - (1,1) logical, the state before this call, so a caller can put
%         back whatever it found rather than assume it was not held.
%
% See also: fromStruct, onPropertyChanged, update_signal
arguments
    obj (1,1) stimgen.StimType
    tf  (1,1) logical
end
was = obj.updatesHeld_;
obj.updatesHeld_ = tf;
end
