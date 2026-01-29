function ctx = init(dataset)
    if ~isa(dataset, 'analysis.Dataset'), error('Input must be an analysis.Dataset'); end
    ctx = struct();
    ctx.Dataset = dataset;
    ctx.Selection = struct('Groups', struct(), 'Conditions', {{}}, 'ROIs', struct(), 'TimeWindows', struct());
    ctx.Results = struct('ERPs', struct(), 'GA', struct(), 'Contrasts', struct(), 'Features', struct());
    % ctx.cfg can be added here if you want global config
end
