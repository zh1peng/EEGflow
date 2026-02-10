function [net_sum, node_sum]= compute_graph_measures(W, params)
W(find(eye(size(W)))) = 0; % Change diagonal NaN to 0
W2use = {W};
[net_sum, node_sum] = gretna_sw_batch_networkanalysis_weight(W2use, params.GRETNA_s1, params.GRETNA_s2, params.GRETNA_deltas, params.GRETNA_n, 's');
end
