function summarize_rsa_mrqap(stats)
% SUMMARIZE_RSA_MRQAP  Print an R-like summary for rsa_mrqap output.
%
%   summarize_rsa_mrqap(stats)
%
%   stats : struct returned by rsa_mrqap, expected to contain at least:
%           .beta, .se, .tval, .ols, .p_main, .p_all (optional),
%           .partialR2, .partialR2_main (optional),
%           .names, .info, .scheme

names = stats.names;
if isempty(names)
    names = arrayfun(@(i)sprintf('b%d',i), 1:size(stats.beta,1), 'uni',0);
end
T = size(stats.beta,2);

fprintf('MRQAP (%s), nPerm=%d, scheme=%s', ...
        stats.info.test, stats.info.nPerm, stats.scheme);
if isfield(stats.info,'strata') && ~isempty(stats.info.strata)
    fprintf(' [stratified]');
end
fprintf(' | stat=%s\n', stats.info.statUsed);

if T>1
    fprintf('Time-resolved: T=%d, maxT=%d (FWER)\n', T, stats.info.maxT);
end

% Report OLS (use time-average for scalars if time-resolved)
R2    = mean(stats.ols.R2);
adjR2 = mean(stats.ols.adjR2);
sigma = mean(stats.ols.sigma);
AIC   = mean(stats.ols.AIC);
BIC   = mean(stats.ols.BIC);
dof   = stats.ols.dof;
fprintf('Residual SE: %.4f on %d df | R^2: %.4f  Adj R^2: %.4f  AIC: %.3f  BIC: %.3f\n', ...
        sigma, dof, R2, adjR2, AIC, BIC);

hasPR2  = isfield(stats,'partialR2')      && ~isempty(stats.partialR2);
hasPR2m = isfield(stats,'partialR2_main') && ~isempty(stats.partialR2_main);

if T==1
    % Single-time summary: per-coefficient row including partial R²
    fprintf('\nCoefficients:\n');
    if hasPR2
        fprintf('%-14s %10s %10s %10s %10s %12s\n', ...
                '', 'Estimate', 'Std.Err', 't', 'p(perm)', 'partialR2');
    else
        fprintf('%-14s %10s %10s %10s %10s\n', ...
                '', 'Estimate', 'Std.Err', 't', 'p(perm)');
    end

    for j = 1:numel(names)
        pj = NaN;
        % main effect p-value
        if j==2 && isfield(stats,'p_main') && ~isempty(stats.p_main)
            pj = stats.p_main(1);
        end
        % override if p_all is available
        if isfield(stats,'p_all') && ~isempty(stats.p_all) && size(stats.p_all,1)>=j
            if ~isnan(stats.p_all(j,1))
                pj = stats.p_all(j,1);
            end
        end

        if hasPR2
            pr2 = stats.partialR2(j,1);
            fprintf('%-14s %10.6f %10.6f %10.3f %10s %12.4f\n', ...
                    names{j}, stats.beta(j,1), stats.se(j,1), ...
                    stats.tval(j,1), pstr(pj), pr2);
        else
            fprintf('%-14s %10.6f %10.6f %10.3f %10s\n', ...
                    names{j}, stats.beta(j,1), stats.se(j,1), ...
                    stats.tval(j,1), pstr(pj));
        end
    end
else
    % Time-resolved summary: show main predictor aggregates across time
    j = 2;  % main predictor index

    est = stats.beta(j,:);
    se  = stats.se(j,:);
    t   = stats.tval(j,:);
    if isfield(stats,'p_main') && ~isempty(stats.p_main)
        p = stats.p_main(:)';
    else
        p = NaN(1,T);
    end

    fprintf('\n%s (time-resolved):\n', names{j});
    fprintf('  Estimate   min/med/max:  %.6f  %.6f  %.6f\n', ...
            min(est), median(est), max(est));
    fprintf('  Std.Err    min/med/max:  %.6f  %.6f  %.6f\n', ...
            min(se),  median(se),  max(se));
    fprintf('  t          min/med/max:  %.3f    %.3f    %.3f\n', ...
            min(t),   median(t),   max(t));

    if any(isfinite(p))
        fprintf('  p(perm)   min/med/max:  %s  %s  %s\n', ...
                pstr(min(p)), pstr(median(p)), pstr(max(p)));
    end

    if hasPR2m
        pr2 = stats.partialR2_main(:)';
        fprintf('  partialR2 min/med/max:  %.4f  %.4f  %.4f\n', ...
                min(pr2), median(pr2), max(pr2));
    end
end

fprintf('\n');

% --- nested helper for p-value formatting ---
function s = pstr(x)
    if ~isfinite(x)
        s = 'NA';
        return;
    end
    if x < 1e-4
        s = sprintf('%.1e', x);
    else
        s = sprintf('%.4f', x);
    end
end

end
