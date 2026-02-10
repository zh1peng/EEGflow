function features2csv(matFileList, outputCSV)
    % export_fc_features processes a list of .mat files containing the 'res'
    % structure and exports connectivity and peak frequency features to a CSV file.
    %
    % USAGE:
    %   export_fc_features(matFileList, outputCSV)
    %
    % INPUTS:
    %   matFileList - cell array of file paths to .mat files (each must contain a
    %                 variable 'res' with the expected structure).
    %   outputCSV   - string specifying the full path for the output CSV file.
    %
    % For each frequency band (e.g., 'alpha'), the function expects:
    %   - res.(band).dwpli_net_sum: a structure with global (net) dwPLI measures.
    %   - res.(band).dwpli_node_sum: a structure with nodal dwPLI measures.
    %   - res.(band).aec_net_sum: a structure with global (net) AEC measures.
    %   - res.(band).aec_node_sum: a structure with nodal AEC measures.
    %
    % Global measures will be saved with column names like:
    %   dwpli_alpha_net_aCp, dwpli_alpha_net_aLp, ..., dwpli_alpha_net_amodratio
    %
    % Nodal measures will be saved with column names like:
    %   dwpli_alpha_node1_aCp, dwpli_alpha_node1_aLp, ..., dwpli_alpha_nodeN_abwratio
    %
    % Peak frequency measures (assumed global) are stored as:
    %   alphapeak_localmax, alphapeak_cog
    %
    % The final CSV file will have one row per subject and one column per feature.
    
    % Define measure lists for net and nodal features.
    netMeasures = {'aCp', 'aLp', 'alocE', 'agE', 'adeg', 'abw', 'amod', ...
        'aCpratio', 'aLpratio', 'alocEratio', 'agEratio', 'adegratio', 'abwratio', 'amodratio'};
    nodeMeasures = {'aCp', 'aLp', 'alocE', 'agE', 'adeg', 'abw', ...
        'aCpratio', 'aLpratio', 'alocEratio', 'agEratio', 'adegratio', 'abwratio'};
    
    result_T = table();  % Initialize overall results table
    
    for iFile = 1:length(matFileList)
        curFile = matFileList{iFile};
        try
            S = load(curFile, 'res');
        catch ME
            warning('Error loading file %s: %s', curFile, ME.message);
            continue;
        end
        if ~isfield(S, 'res')
            warning('File %s does not contain variable res. Skipping.', curFile);
            continue;
        end
        res = S.res;
        
        % Initialize a structure to hold features for the current subject.
        subjFeat = struct();
        
        % Subject ID extraction (assumed to be stored in res.subid)
        if isfield(res, 'subid')
            subjFeat.subid = res.subid;
        else
            subjFeat.subid = 'unknown';
        end

          % Subject ID extraction (assumed to be stored in res.subid)
        if isfield(res, 'nTrial')
            subjFeat.nTrial = res.nTrial;
        else
            subjFeat.nTrial = -999;
        end
        
        % Determine frequency bands from res.params.FreqBand (e.g., 'alpha', 'beta', etc.)
        if isfield(res, 'params') && isfield(res.params, 'FreqBand')
            freqBands = fields(res.params.FreqBand);
        else
            warning('File %s missing params.FreqBand. Skipping.', curFile);
            continue;
        end
        
        % Process each frequency band
        for iBand = 1:length(freqBands)
            band = freqBands{iBand};
            
            % --- Process dwPLI Global (net) Measures ---
            if isfield(res.(band), 'dwpli_net_sum')
                for m = 1:length(netMeasures)
                    measureName = netMeasures{m};
                    if isfield(res.(band).dwpli_net_sum, measureName)
                        fieldName = sprintf('dwpli_%s_net_%s', band, measureName);
                        subjFeat.(fieldName) = res.(band).dwpli_net_sum.(measureName);
                    else
                        subjFeat.(sprintf('dwpli_%s_net_%s', band, measureName)) = NaN;
                    end
                end
            end
            
            % --- Process dwPLI Nodal Measures ---
            if isfield(res.(band), 'dwpli_node_sum')
                for m = 1:length(nodeMeasures)
                    measureName = nodeMeasures{m};
                    if isfield(res.(band).dwpli_node_sum, measureName)
                        nodeVector = res.(band).dwpli_node_sum.(measureName);
                        nNodes = numel(nodeVector);
                        for node = 1:nNodes
                            fieldName = sprintf('dwpli_%s_node%d_%s', band, node, measureName);
                            subjFeat.(fieldName) = nodeVector(node);
                        end
                    end
                end
            end
            
            % --- Process AEC Global (net) Measures ---
            if isfield(res.(band), 'aec_net_sum')
                for m = 1:length(netMeasures)
                    measureName = netMeasures{m};
                    if isfield(res.(band).aec_net_sum, measureName)
                        fieldName = sprintf('aec_%s_net_%s', band, measureName);
                        subjFeat.(fieldName) = res.(band).aec_net_sum.(measureName);
                    else
                        subjFeat.(sprintf('aec_%s_net_%s', band, measureName)) = NaN;
                    end
                end
            end
            
            % --- Process AEC Nodal Measures ---
            if isfield(res.(band), 'aec_node_sum')
                for m = 1:length(nodeMeasures)
                    measureName = nodeMeasures{m};
                    if isfield(res.(band).aec_node_sum, measureName)
                        nodeVector = res.(band).aec_node_sum.(measureName);
                        nNodes = numel(nodeVector);
                        for node = 1:nNodes
                            fieldName = sprintf('aec_%s_node%d_%s', band, node, measureName);
                            subjFeat.(fieldName) = nodeVector(node);
                        end
                    end
                end
            end
        end
        
        % --- Extract Peak Frequency Information ---
        if isfield(res, 'peakfrequency')
            if isfield(res.peakfrequency, 'localmax') && ~isempty(res.peakfrequency.localmax)
                subjFeat.alphapeak_localmax = res.peakfrequency.localmax;
            else
                subjFeat.alphapeak_localmax = NaN;
            end
            if isfield(res.peakfrequency, 'cog') && ~isempty(res.peakfrequency.cog)
                subjFeat.alphapeak_cog = res.peakfrequency.cog;
            else
                subjFeat.alphapeak_cog = NaN;
            end
        end
        
        % Convert subject's feature structure to a table row and append to the overall table.
        Trow = struct2table(subjFeat);
        result_T = [result_T; Trow];  % Vertical concatenation
    end
    
    % Write the final table to the specified CSV file.
    writetable(result_T, outputCSV);
    fprintf('CSV file saved: %s\n', outputCSV);
    end
    