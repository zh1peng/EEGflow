function wins = ctx_get_sig_windows(mask, times)
    mask = logical(mask(:)');
    starts = find(diff([0 mask 0])==1);
    ends = find(diff([0 mask 0])==-1);
    wins = [];
    for i = 1:numel(starts)
        wins = [wins; times(starts(i)), times(ends(i)-1)]; %#ok<AGROW>
    end
end