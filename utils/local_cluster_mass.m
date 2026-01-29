function [masses, clusters] = local_cluster_mass(tvec, tthr)
    % two-sided thresholding
    mask = abs(tvec) >= tthr;
    d = diff([false mask false]);
    starts = find(d==1); ends = find(d==-1)-1;
    clusters = arrayfun(@(a,b) a:b, starts, ends, 'UniformOutput', false);
    masses = cellfun(@(ix) sum(abs(tvec(ix))), clusters);
end
