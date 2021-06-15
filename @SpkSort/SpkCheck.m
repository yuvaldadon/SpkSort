function f=SpkCheck(obj, f, i)

if i>0
    waveforms=obj.SortedSpikes{i};
else
    waveforms=obj.Spikes;
end

if size(waveforms,1)<size(waveforms,2)
  waveforms=waveforms';
end
target  = 1;
binsz   = [];
plotno  = 5000;
markvec = ones(size(waveforms,1),1);
timevec = zeros(size(waveforms,1),1);
%% rearrange input
if size(markvec,1)<size(markvec,2)
  markvec=markvec';
end
markvec = markvec(:,1);
wavs = double(waveforms(markvec==target,:));
spxtimes = double(timevec(markvec==target));
%% calculate indices...
c.spx       = size(wavs,1);
c.fr        = 1/mean(diff(spxtimes));
c.meanwave  = mean(wavs,1);
c.stdev     = std(wavs,0,1);
c.skew      = skewness(wavs,0,1);
%% raw waveforms
subplot(221)
title(['up to ' num2str(plotno) ' waveforms']),hold all
if plotno>size(wavs,1),plotno=size(wavs,1);end
plot(wavs(randsample(1:size(wavs,1),plotno),:)','b')
plot(c.meanwave,'k','LineWidth',2);
plot(c.meanwave+c.stdev,'k');
plot(c.meanwave+2*c.stdev,'k');
plot(c.meanwave-c.stdev,'k');
plot(c.meanwave-2*c.stdev,'k');
lower = min(c.meanwave)-max(c.stdev)*3;
upper = max(c.meanwave)+max(c.stdev)*3;
axis([0 size(wavs,2)+1 lower upper])
xlabel('time (bins)'),ylabel('ADC units')
%% density plots
subplot(223)
title('density plot'),hold on
clear n b
numTicks = size(wavs,2);
for i = 1:numTicks
  [n(i,:),b(i,:)] = hist(wavs(:,i),linspace(lower,upper,min([numel(unique(wavs))/4 500])));
end
colormap(hot)
% remove extreme outliers
cutoff = 5*std(reshape(n,numel(n),1));
n(n>cutoff) = cutoff;
pcolor(n'),shading interp
axis([1 numTicks 1 size(n,2)])
xlabel('time (bins)')
ylabel('ADC units (bins)')

% density plot in log-coordinates
subplot(224)
title('density plot in log space'),hold on
colormap(hot)
pcolor(log10(n)'),shading interp
axis([1 numTicks 1 size(n,2)])
xlabel('time (bins)')
ylabel('ADC units (bins)')
%% sample waveforms
subplot(222)
[numWavs numTicks] = size(wavs);
toPlot = floor(min([numWavs/3 200]));
%if numWavs>200
  plot(1:numTicks,wavs(1:toPlot,:)','b'),hold on
  plot(numTicks+1:numTicks*2,wavs(round(numWavs/2-toPlot/2):round(numWavs/2+toPlot/2),:),'c')
  plot(numTicks*2+1:numTicks*3,wavs(end-ceil(toPlot/2):end,:)','r')
  axis([0 numTicks*3+1 lower upper])
  mult = 16:-4:-16;
  x = mult.*ones(1,numel(mult))*c.stdev(1)+c.meanwave(1);
  for i = 1:numel(x)
    plot([1,numTicks*3+1],[c.meanwave(1)+x(i) c.meanwave(1)+x(i)],'k:')
  end
%end
axis off
ypos = double((max(c.meanwave)+2*c.stdev(1)));
text(1,ypos,['first ' num2str(toPlot)],'FontWeight','bold')
text(1+numTicks,ypos,['mid ' num2str(toPlot)],'FontWeight','bold')
text(1+numTicks*2,ypos,['last ' num2str(toPlot)],'FontWeight','bold')