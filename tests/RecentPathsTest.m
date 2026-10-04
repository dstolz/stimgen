classdef RecentPathsTest < matlab.unittest.TestCase
    % stimgen.util.recent_paths: the most-recent-first file lists StimPlayer
    % and CalibrationGui keep in MATLAB preferences, and the Recent submenu
    % built from one. Runs against a throwaway preference group.
    %
    % Run from the repository root:
    %   addpath(pwd); results = runtests('tests');
    % See tests/README.md.

    properties (Constant)
        Group = 'stimgenRecentPathsTest'
    end

    methods (TestClassSetup)
        function addPackageRoot(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (TestMethodSetup)
        function clearGroup(testCase)
            if ispref(testCase.Group)
                rmpref(testCase.Group);
            end
            testCase.addTeardown(@() rm_group_(testCase.Group));
        end
    end

    methods (Test)

        function emptyUntilSomethingIsAdded(testCase)
            p = stimgen.util.recent_paths(testCase.Group, 'Banks');
            testCase.verifyEqual(p, cell(1, 0));
        end

        function addPromotesToTheHeadWithoutDuplicates(testCase)
            g = testCase.Group;
            stimgen.util.recent_paths(g, 'Banks', "add", 'C:\a.spl');
            stimgen.util.recent_paths(g, 'Banks', "add", "  C:\b.spl ");
            p = stimgen.util.recent_paths(g, 'Banks', "add", 'c:\A.SPL');   % same file, case aside
            testCase.verifyEqual(p, {'c:\A.SPL', 'C:\b.spl'});
            testCase.verifyEqual(stimgen.util.recent_paths(g, 'Banks'), p);
            % Lists are independent of one another.
            testCase.verifyEmpty(stimgen.util.recent_paths(g, 'Protocols'));
        end

        function keepsTheNineMostRecent(testCase)
            g = testCase.Group;
            for k = 1:12
                stimgen.util.recent_paths(g, 'Banks', "add", sprintf('f%02d.spl', k));
            end
            p = stimgen.util.recent_paths(g, 'Banks');
            testCase.verifyEqual(numel(p), 9);
            testCase.verifyEqual(p{1}, 'f12.spl');
            testCase.verifyEqual(p{end}, 'f04.spl');
        end

        function removeDropsAPath(testCase)
            g = testCase.Group;
            stimgen.util.recent_paths(g, 'Banks', "add", 'a.spl');
            stimgen.util.recent_paths(g, 'Banks', "add", 'b.spl');
            p = stimgen.util.recent_paths(g, 'Banks', "remove", 'A.spl');
            testCase.verifyEqual(p, {'b.spl'});
        end

        function menuOffersEachPathNewestFirst(testCase)
            g = testCase.Group;
            stimgen.util.recent_paths(g, 'Banks', "add", fullfile('x', 'one.spl'));
            stimgen.util.recent_paths(g, 'Banks', "add", fullfile('x', 'two.spl'));
            f = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(f));
            testCase.addTeardown(@() evalin('base', 'clear stimgenRecentPathsOpened'));
            m = uimenu(f, 'Text', 'Recent');
            pick = @(p) assignin('base', 'stimgenRecentPathsOpened', p);
            stimgen.util.recent_paths(g, 'Banks', "menu", m, pick);
            items = flip(m.Children(:).');          % Children is newest-last
            testCase.verifyEqual(numel(items), 2);
            testCase.verifyTrue(startsWith(items(1).Text, '1. two.spl | '));
            feval(items(2).MenuSelectedFcn, items(2), []);
            testCase.verifyEqual(evalin('base', 'stimgenRecentPathsOpened'), ...
                fullfile('x', 'one.spl'));

            % An empty list says so instead of leaving the submenu bare.
            stimgen.util.recent_paths(g, 'Banks', "remove", fullfile('x', 'one.spl'));
            stimgen.util.recent_paths(g, 'Banks', "remove", fullfile('x', 'two.spl'));
            stimgen.util.recent_paths(g, 'Banks', "menu", m, pick);
            testCase.verifyEqual(numel(m.Children), 1);
            testCase.verifyEqual(m.Children.Text, '(None)');
            testCase.verifyEqual(char(m.Children.Enable), 'off');
        end

    end
end


function rm_group_(group)
if ispref(group)
    rmpref(group);
end
end
