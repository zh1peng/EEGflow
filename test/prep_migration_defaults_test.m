function prep_migration_defaults_test()
% Compare prep parameter declarations and resolved defaults with sibling EEGdojo.
% This checks the migration contract; it does not run preprocessing algorithms.
root = fileparts(fileparts(mfilename('fullpath')));
reference = fullfile(fileparts(root), 'EEGdojo', '+prep');
addpath(root);
files = dir(fullfile(reference, '*.m'));
nOps = 0;
nParams = 0;
for k = 1:numel(files)
    [~, op] = fileparts(files(k).name);
    if strcmp(op, 'Pipeline'), continue; end
    original = fileread(fullfile(reference, files(k).name));
    migrated = fileread(fullfile(root, '+prep', files(k).name));
    pattern = '(?m)^\s*p\.add(?:Required|Parameter)\([^\r\n]*';
    originalDeclarations = regexp(original, pattern, 'match');
    migratedDeclarations = regexp(migrated, pattern, 'match');
    % Ignore formatting and trailing comments, but compare defaults and validators.
    normalize = @(x) regexprep(regexprep(x, ';\s*%[^\r\n]*', ';'), '\s+', '');
    assert(isequal(normalize(originalDeclarations), normalize(migratedDeclarations)), ...
        '%s: parameter declarations differ from EEGdojo.', op);

    p = inputParser;
    for j = 1:numel(originalDeclarations)
        eval(originalDeclarations{j});
    end
    if contains(original, "p.addRequired('EEG'")
        p.parse(struct());
    else
        p.parse();
    end
    expected = p.Results;
    if isfield(expected, 'EEG'), expected = rmfield(expected, 'EEG'); end
    state = feval(['prep.' op], struct('EEG', struct()), struct(), ...
        struct('validate_only', true));
    assert(isequaln(expected, state.history(end).params), ...
        '%s: resolved defaults differ from EEGdojo.', op);
    nOps = nOps + 1;
    nParams = nParams + numel(fieldnames(expected));
end
fprintf('PASS: %d prep operations, %d parameter defaults and validators match EEGdojo.\n', ...
    nOps, nParams);
end
