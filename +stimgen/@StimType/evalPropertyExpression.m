function value = evalPropertyExpression(obj, propName, expressionText)
% value = evalPropertyExpression(obj, propName, expressionText)
% Evaluate a guarded MATLAB expression for a vectorizable numeric property.
% Accepts range syntax (0:10:50), vector literals ([1 2 3]), general
% MATLAB expressions, and cross-property references using bare property
% names or qualified ClassName.PropertyName notation.
%
% Both the expression and the returned value are in GUI display units (see
% the 'scale' field of propMeta) — time properties are therefore in
% milliseconds, not the seconds used by the property itself. Callers must
% divide by stimgen.StimType.display_scale before assigning to the property.
%
% Parameters:
%   propName       - Name of the target property.
%   expressionText - MATLAB expression string to evaluate, in display units.
%
% Returns:
%   value - Resulting double scalar or vector, in display units.
value = obj.evaluate_property_expression_(propName, char(string(expressionText)));
