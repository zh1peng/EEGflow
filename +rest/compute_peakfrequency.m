function [peakfrequency] = compute_peakfrequency(power,params)
% Average power across channels
avgpow = mean(power.powspctrm,1);

% Frequency range (search limits for the peak = alpha band)
freqRange = find(power.freq >= params.FreqBand.alpha(1) & power.freq <= params.FreqBand.alpha(2));

% Peak frequency computed on the power spectrum averaged across channels
% Approach 1. Find highest local maximum in the power spectrum averaged across epochs
[~, pf_localmax] = findpeaks(avgpow(freqRange),power.freq(freqRange),'SortStr','descend','NPeaks',1);
peakfrequency.localmax = pf_localmax;

% Approach 2. Compute center of gravity on the power spectrum averaged across epochs
pf_cog = sum(avgpow(freqRange).*power.freq(freqRange))/sum(avgpow(freqRange));
peakfrequency.cog = pf_cog;
end
