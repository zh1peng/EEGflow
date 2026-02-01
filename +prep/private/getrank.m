function tmprank2 = getrank(tmpdata)
    % GETRANK - Computes the numerical rank of a data matrix robustly.
    %
    % Description:
    %   This function calculates the numerical rank of a data matrix using two methods:
    %   1. Direct rank computation using MATLAB's `rank` function.
    %   2. Alternate method based on the eigenvalues of the covariance matrix.
    %   If discrepancies occur between methods, the minimum of the two ranks is returned.
    %
    % Inputs:
    %   tmpdata - (double) Input data matrix (channels x time points).
    %
    % Outputs:
    %   tmprank2 - Robust rank estimate of the input matrix.
    %
    % Notes:
    %   - A small tolerance value (`1e-7`) is used to determine rank based on eigenvalues.
    %   - This function is particularly useful for EEG data where numerical precision
    %     can vary due to preprocessing.
    %
    % Example:
    %   rank_estimate = getrank(EEG.data);
    %
    % Authors:
    %   Original by Sven Hoffman, Improved and documented by Zhipeng Cao (zhipeng30@foxmail.com) (2024).

    tmpdata = double(tmpdata);  % Ensure the input is double precision
    tmprank = rank(tmpdata);  % Rank using MATLAB's built-in rank function
    % Compute covariance matrix (column-wise)
    covarianceMatrix = cov(tmpdata', 1); % Normalized covariance matrix (biased estimator)
    % Eigenvalue decomposition of the covariance matrix
    [~, D] = eig(covarianceMatrix);  % D contains eigenvalues on the diagonal
    % Define tolerance for rank estimation
    rankTolerance = 1e-7;  % Threshold to consider eigenvalues non-zero
    % Count eigenvalues greater than the tolerance
    tmprank2 = sum(diag(D) > rankTolerance);
    if tmprank ~= tmprank2
        % Use the minimum of the two rank estimates for safety
        warning('Rank estimates differ. Returning the minimum value.');
        tmprank2 = min(tmprank, tmprank2);
    end
    % Return the robust rank estimate
    return;
end
