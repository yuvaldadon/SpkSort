function obj=DetectThreshold(obj)

data=obj.FilteredData;
L=obj.spikeLength;
N=numel(data);
maxpoint=round(.5*L);
timepoints=[];

for t=2*L+1:L:N-L
    window=data(t-L:t+L);
    [val,index]=min(window);
    if val<-obj.threshold
        if index<L*3/2;
            timepoints=[timepoints,t-L-1+index];
            data(timepoints(end)+(-L:L))=0;
        end
    end
end
spikes=zeros(L,numel(timepoints));
for t=1:numel(timepoints)
    spikes(:,t)=obj.FilteredData(timepoints(t)+(-maxpoint+1:L-maxpoint));
end
obj.SpikesTime=timepoints/20000*1000; % 20kHz in ms
obj.Spikes=spikes;