function [chan_properties, bad_channels] = FASTER_rejchan(EEG, varargin)
    % FASTER_REJCHAN - Compute channel properties and flag bad channels.
    %
    % Usage:
    %   >> [chan_properties, bad_channels] = FASTER_rejchan(EEG, 'elec', Chan2Check, ...
    %                                                      'threshold', Threshold, ...
    %                                                      'measure', 'meanCorr', ...
    %                                                      'refchan', RefChan);
    %
    % Inputs:
    %   EEG        - EEG data structure.
    %   'elec'     - Indices of EEG channels to analyze (default: all EEG channels).
    %   'threshold'- Z-score threshold for flagging bad channels (default: 3).
    %   'measure'  - Measure to compute: 
    %                'meanCorr' (mean correlation), 
    %                'variance' (variance), 
    %                'hurst' (Hurst exponent).
    %   'refchan'  - Reference channel index for distance correction (default: none).
    %
    % Outputs:
    %   chan_properties - Z-scored properties of the channels.
    %   bad_channels    - Indices of channels flagged as bad based on threshold.
    
    % Parse inputs
    p = inputParser;
    addRequired(p, 'EEG');
    addParameter(p, 'elec', 1:size(EEG.data, 1), @isnumeric);
    addParameter(p, 'threshold', 3, @isnumeric);
    addParameter(p, 'measure', 'meanCorr', @(x) ismember(x, {'meanCorr', 'variance', 'hurst'}));
    addParameter(p, 'refchan', [], @isnumeric);
    
    parse(p, EEG, varargin{:});
    eeg_chans = p.Results.elec;
    threshold = p.Results.threshold;
    measure_type = p.Results.measure;
    ref_chan = p.Results.refchan;
    
    % Initialize
    chan_properties = zeros(length(eeg_chans), 1);
    
    % Calculate distances if ref_chan is provided
    if ~isempty(ref_chan) && length(ref_chan) == 1
        pol_dist = distancematrix(EEG, eeg_chans);
        [s_pol_dist, dist_inds] = sort(pol_dist(ref_chan, eeg_chans));
        [~, idist_inds] = sort(dist_inds);
    end
    
    % Measure selection
    switch measure_type
        case 'meanCorr'
            % Mean correlation between channels
            ignore = [];
            for u = eeg_chans
                if max(EEG.data(u, :)) == 0 && min(EEG.data(u, :)) == 0
                    ignore = [ignore u];
                end
            end
            % Calculate correlations
            calc_indices=setdiff(eeg_chans,ignore);
            ignore_indices=intersect(eeg_chans,ignore);
            corrs = abs(corrcoef(EEG.data(setdiff(eeg_chans,ignore),:)'));
            mcorrs=zeros(size(eeg_chans));
            for u=1:length(calc_indices)
                mcorrs(calc_indices(u))=mean(corrs(u,:));
            end
            mcorrs(ignore_indices)=mean(mcorrs(calc_indices));
            if (~isempty(ref_chan) && length(ref_chan)==1)
                p = polyfit(s_pol_dist,mcorrs(dist_inds),2);
                fitcurve = polyval(p,s_pol_dist);
                corrected = mcorrs(dist_inds) - fitcurve(idist_inds);
                chan_properties(:,1)=corrected;
            else
                chan_proerties(:,1)=mcoors(dist_inds);
            end

    
        case 'variance'
            vars = var(EEG.data(eeg_chans,:)');
            vars(~isfinite(vars))=mean(vars(isfinite(vars)));
            % Quadratic correction for distance from reference electrode
            
            if (~isempty(ref_chan) && length(ref_chan)==1)
                p = polyfit(s_pol_dist,vars(dist_inds),2);
                fitcurve = polyval(p,s_pol_dist);
                corrected = vars - fitcurve(idist_inds);
            
                chan_properties(:,1) = corrected;
            else
                chan_properties(:,1) = vars;
            end
        case 'hurst'
            % Hurst exponent for each channel
            for u = 1:length(eeg_chans)
                chan_properties(u,1) = hurst_exponent(EEG.data(eeg_chans(u), :));
            end
    end
    
    
    
    % Post-processing: Handle NaN and subtract median
    chan_properties(isnan(chan_properties),1) = nanmean(chan_properties);
    chan_properties = chan_properties - median(chan_properties);
%     for u = 1:size(chan_properties,2)
%     chan_properties(isnan(chan_properties(:,u)),u)=nanmean(chan_properties(:,u));
% 	chan_properties(:,u) = chan_properties(:,u) - median(chan_properties(:,u));
% end
    
    % Z-score normalization
     zs = chan_properties - mean(chan_properties, 'omitnan');
    zs = zs ./ std(zs, 'omitnan');
    zs(isnan(zs))=0;
    
    % Find bad channels using the threshold
    bad_channels = eeg_chans(abs(zs) > threshold);
    
    % Print channel properties and bad channels
    fprintf('\n#\tChannel\tMeasure(z)\tStatus\n');
    fprintf('------------------------------------\n');
    for i = 1:length(eeg_chans)
        if ~isempty(EEG.chanlocs)
            chan_name = EEG.chanlocs(eeg_chans(i)).labels;
        else
            chan_name = num2str(eeg_chans(i));
        end
        status = '';
        if ismember(eeg_chans(i), bad_channels)
            status = '*Bad*';
        end
        fprintf('%d\t%s\t%.3f\t%s\n', i, chan_name, zs(i), status);
    end
    end
    


function [distmatrixpol distmatrixxyz distmatrixproj] = distancematrix(EEG,eeg_chans)

% Copyright (C) 2010 Hugh Nolan, Robert Whelan and Richard Reilly, Trinity College Dublin,
% Ireland
% nolanhu@tcd.ie, robert.whelan@tcd.ie
%
% This program is free software; you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation; either version 2 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program; if not, write to the Free Software
% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

num_chans = size(EEG.data,1);
distmatrix = zeros(length(eeg_chans),length(eeg_chans));
distmatrixpol = [];
for chan2tst = eeg_chans;
	for q=eeg_chans
		distmatrixpol(chan2tst,q)=sqrt(((EEG.chanlocs(chan2tst).radius^2)+(EEG.chanlocs(q).radius^2))-(2*((EEG.chanlocs(chan2tst).radius)*...
			(EEG.chanlocs(q).radius)*cosd(EEG.chanlocs(chan2tst).theta - EEG.chanlocs(q).theta))));%calculates the distance between electrodes using polar format
	end
end

locs = EEG.chanlocs;
for u = eeg_chans
	if ~isempty(locs(u).X)
		Xs(u) = locs(u).X;
	else
		Xs(u) = 0;
	end
	if ~isempty(locs(u).Y)
		Ys(u) = locs(u).Y;
	else
		Ys(u) = 0;
		end
	if ~isempty(locs(u).Z)
		Zs(u) = locs(u).Z;
	else
		Zs(u) = 0;
	end
end
Xs = round2(Xs,6);
Ys = round2(Ys,6);
Zs = round2(Zs,6);

for u = eeg_chans
	for v=eeg_chans
		distmatrixxyz(u,v) = dist(Xs(u),Xs(v))+dist(Ys(u),Ys(v))+dist(Zs(u),Zs(v));
	end
end
D = max(max(distmatrixxyz));
distmatrixproj = (pi-2*(acos(distmatrixxyz./D))).*(D./2);
	function d = dist(in1,in2)
		d = sqrt(abs(in1.^2 - in2.^2));
	end

	function num = round2(num,decimal)
		num = num .* 10^decimal;
		num = round(num);
		num = num ./ 10^decimal;
	end
end



% The Hurst exponent
%--------------------------------------------------------------------------
% This function does dispersional analysis on a data series, then does a 
% Matlab polyfit to a log-log plot to estimate the Hurst exponent of the 
% series.
%
% This algorithm is far faster than a full-blown implementation of Hurst's
% algorithm.  I got the idea from a 2000 PhD dissertation by Hendrik J 
% Blok, and I make no guarantees whatsoever about the rigor of this approach
% or the accuracy of results.  Use it at your own risk.
%
% Bill Davidson
% 21 Oct 2003

function [hurst] = hurst_exponent(data0)   % data set

data=data0;         % make a local copy

[M,npoints]=size(data0);

yvals=zeros(1,npoints);
xvals=zeros(1,npoints);
data2=zeros(1,npoints);

index=0;
binsize=1;

while npoints>4
    
    y=std(data);
    index=index+1;
    xvals(index)=binsize;
    yvals(index)=binsize*y;
    
    npoints=fix(npoints/2);
    binsize=binsize*2;
    for ipoints=1:npoints % average adjacent points in pairs
        data2(ipoints)=(data(2*ipoints)+data((2*ipoints)-1))*0.5;
    end
    data=data2(1:npoints);
    
end % while

xvals=xvals(1:index);
yvals=yvals(1:index);

logx=log(xvals);
logy=log(yvals);

p2=polyfit(logx,logy,1);
hurst=p2(1); % Hurst exponent is the slope of the linear fit of log-log plot

end
