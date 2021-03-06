classdef SpkSort
    properties (SetAccess=public)
        % Filter Data
        highPassCutoff=500;
        lowPassCutoff=2000;
        
        % Spike Threshold
        median=1; % use median instead of standard deviation
        factorThreshold=25; % multiply constant by deviation for threshold %was 20
        threshold; % store final threshold
        stdThreshold; % store standard deviation threshold
        medianThreshold; % store median threshold
        spikeLength=90; % number of samples per spike
        
        % Data
        useDiode=1; % enable to use diode timing
        Events; % event trigger times (from Recording)
        onTimes; % On event times
        offTimes; % Off event times
        avgOn;
        avgOff;
        avgOnInfo;
        avgOffInfo;
        Mon; % On events spike matrix
        Moff; % Off events spike matrix
        doubleMon; % On events spike matrix (double stim)
        doubleMoff; % Off events spike matrix (double stim)
        Mon_clusters; % On events spike matrix (per spike cluster)
        Moff_clusters; % Off events spike matrix (per spike cluster)
        FilteredData; % data after filtering
        m; %max X position index
        n; %max Y position index
        
        % Spikes
        Spikes;
        SortedSpikes;
        SortedSpikesIndex;
        SpikesTime;
        bin=5;
        window=500;
        clusters=2; % number of spike clusters to sort
        kernelPrint=1; % enable to print kernels on top of PSTH
        kernelW = 8; % weight of kernel
        kernel='Gauss'; % supported kernels: 'boxcar'/'Gauss'/'exp'
        
        % Plot
        axis={'Spacing',0.002,'Padding',0.002,'Margin',0.05};
        x;
        savePlots=1;
        closePlots=1;
        
        % Stim
        doubleStim=0; % indicator for double square stim
        nPos; % number of unique positions
        nTrials; % number of trials
        Pos; % trial indexes of single squares stim
        doublePos; % trial indexes of double squares stim
        
        %LTI plots
        LTI_bins=10; % num of bins after combining for LTI plot
        LTI_cutoffBins=0.5; % percent of bins from start to allocate for LTI plot
        pvalue_intensity=5;
        LTI_pvalue_On;
        LTI_pvalue_Off;
        LTI_doubleMon;
        LTI_doubleMoff;
            
        % Objects/Directories
        RecordingObj;
        FilterObj;
        VSP;
        SpikeDir;
        tempDir=0;
        StimDir;
        OutputDir;
        diodeFile;
        dataFile;
    end
    
    methods (Hidden)
        %% class construct
        function obj=SpkSort(RecordingObj, StimDir, OutputDir, varargin)
            
            % Arguments
            for i=1:2:length(varargin)
                eval(['obj.' varargin{i} '=' 'varargin{i+1};'])
            end
            
            % Objects and Paths
            obj.RecordingObj=RecordingObj;
            obj.StimDir=StimDir;
            obj.OutputDir=OutputDir;
            obj.SpikeDir=[OutputDir filesep RecordingObj.recordingName '_SpkSort_Thresh' num2str(obj.factorThreshold) '_Cluster' num2str(obj.clusters)];
            while exist(obj.SpikeDir,'dir')
                %obj.SpikeDir=[OutputDir filesep RecordingObj.recordingName '_' num2str(obj.factorThreshold) 'thresh_spikeSort_temp' num2str(obj.tempDir)];
                obj.SpikeDir=[obj.SpikeDir '_temp' num2str(obj.tempDir)];
                obj.tempDir=obj.tempDir+1;
                disp(['SpkSort output directory already exists, creating ' obj.SpikeDir]);
            end
            mkdir(obj.SpikeDir);
   
            % Extract Recording Data and Timing
            obj=DataConstruct(obj);
            
            % Set threshold
            obj.stdThreshold=obj.factorThreshold*std(obj.FilteredData);
            obj.medianThreshold=obj.factorThreshold*mad(obj.FilteredData,1);
            if obj.median
                obj.threshold=obj.medianThreshold;
            else
                obj.threshold=obj.stdThreshold;
            end
            
            % Detect Spikes
            obj=obj.DetectThreshold;
            
            % load stimulation
            obj=LoadStim(obj);
            
            % Build Mon/Moff spike matrixes
            obj.x=obj.bin/2:obj.bin:obj.window;
            obj=BuildSpikeMatrix(obj,0);
            
        end
    end
    
    methods
        %% Construct data from recording
        function obj=DataConstruct(obj)
            
            % event triggers
            obj.Events=obj.RecordingObj.getTrigger;
            
            % diode event triggers
            if obj.useDiode
                obj.diodeFile=[obj.RecordingObj.recordingDir filesep 'diodeData.mat'];
                if ~exist(obj.diodeFile,'file')
                    [frameShifts,upCross,downCross,~,transitionNotFound]=frameTimeFromDiode(obj.RecordingObj,'trialStartEndDigiTriggerNumbers',[3 4],'T',obj.Events,'noisyAnalog',0,'delay2Shift',2.5/60*1000);
                    %upCross=upCross(1:end-1);
                    %downCross=downCross(1:end-1);
                    save(obj.diodeFile,'frameShifts','upCross','downCross','transitionNotFound');
                else
                    load(obj.diodeFile);
                end
                if isequal(upCross,downCross)
                    upCross=frameShifts{1,2}.';
                    downCross=frameShifts{1,1}.';
                end
                obj.onTimes=upCross;
                obj.offTimes=downCross;
            else
                obj.onTimes=obj.Events{1,3};
                obj.offTimes=obj.Events{1,4};
            end
            
            % extract data
            obj.dataFile=[obj.RecordingObj.recordingDir filesep 'SpkSortRecordData.mat'];
            if ~exist(obj.dataFile,'file')
                [Data,~]=obj.RecordingObj.getData([],0,obj.onTimes(end)+5000);
                if size(Data,1)~=1
                    Data=Data(24,:,:);
                end
                save(obj.dataFile,'Data');
            else
                load(obj.dataFile);
            end

            % filter data
            F=filterData(obj.RecordingObj.samplingFrequency);
            F.highPassCutoff=obj.highPassCutoff;
            F.lowPassCutoff=obj.lowPassCutoff;
            F=F.designBandPass;
            F.padding=1;
            obj.FilterObj=F;
            obj.FilteredData=squeeze(obj.FilterObj.getFilteredData(Data));
            %figure;plot(obj.FilteredData(1:10000));
        end
        
        %% Load Stimulation
        function obj=LoadStim(obj)
            load(obj.StimDir);
            fieldsToExtract={'trialsPerCategory','luminosities','pos','pos2X','pos2Y','rotation','stimDuration','tilingRatio'};
            for i=1:numel(fieldsToExtract)
                VSP.(fieldsToExtract{i})=VSMetaData.allPropVal(strcmp(VSMetaData.allPropName,fieldsToExtract{i}));
                VSP.(fieldsToExtract{i})=VSP.(fieldsToExtract{i}){1};
            end
            if numel(VSP.luminosities)==(numel(VSP.pos)+1)
                VSP.luminosities(end)=[];
            end
            if size(VSP.pos,1)==2
                zeroIndex=VSP.pos(2,:)==0;
                VSP.pos(2,zeroIndex)=VSP.pos(1,zeroIndex); % change 0's into index duplicate
            end
            
            % Sort trial positions
            obj.VSP=VSP;
            obj.m=max(VSP.pos2X);
            obj.n=max(VSP.pos2Y);
            %singlePos=VSP.pos(1,VSP.pos(2,:)==0); % extract events of single squares
            %[sortedPos, sortedTrials]=sort(VSP.pos);
            obj.nPos=numel(VSP.pos2X);
            %obj.nTrials=numel(sortedTrials);
            
            % single square stim
            obj.Pos=cell(obj.nPos,obj.nPos);
            for i=1:obj.nPos
                for j=1:obj.nPos
                    Pos=VSP.pos==[i;j];
                    Pos=(sum(Pos)==2);
                    obj.Pos{i,j}=find(Pos);
                end
            end
        end
                      
        %% Spike Matrixes
        function obj=BuildSpikeMatrix(obj, index)
            if index==0 % pre-sort spikes
                spikes=obj.SpikesTime;
            else
                spikes=obj.SpikesTime(obj.SortedSpikesIndex==index);
            end
            iSpk=[1;1;1;numel(spikes)];
            Mon=BuildBurstMatrix(iSpk,round(spikes/obj.bin),round(obj.onTimes)/obj.bin,obj.window/obj.bin);
            Moff=BuildBurstMatrix(iSpk,round(spikes/obj.bin),round(obj.offTimes)/obj.bin,obj.window/obj.bin);
            
            for i=1:obj.nPos
                if index==0    %Mon=(810,1,100)
                    obj.Mon{i}=squeeze(Mon(obj.Pos{i,i},1,:));
                    obj.Moff{i}=squeeze(Moff(obj.Pos{i,i},1,:));
                    if obj.doubleStim
                        for j=1:obj.nPos
                            obj.doubleMon{i,j}=squeeze(Mon(obj.Pos{i,j},1,:));
                            obj.doubleMoff{i,j}=squeeze(Moff(obj.Pos{i,j},1,:));
                        end
                    end

                else
                    obj.Mon_clusters{i,index}=squeeze(Mon(obj.Pos{i,i},1,:));
                    obj.Moff_clusters{i,index}=squeeze(Moff(obj.Pos{i,i},1,:));
                end
            end
        end  
        
        %% Spike Sorting
        function obj=SortSpikes(obj)
            
            % spike sort into clusters
            K=3;
            Sorter=FMM(obj.Spikes,K,obj.clusters);
            Sorter.align=false;
            Sorter.initialize;
            Sorter.runVBfit;
            f1=Sorter.drawPCA3d(1,true);
            obj.SavePlot(f1, 'PCA');
            f2=Sorter.drawClusters(2);
            legend;
            obj.SavePlot(f2, 'SpikeClusters');

            % seperate clusters
            obj.SortedSpikes=cell(obj.clusters,1);
            obj.SortedSpikesIndex=Sorter.z;
            obj.Mon_clusters=cell(obj.nPos,obj.clusters);obj.Moff_clusters=cell(obj.nPos,obj.clusters);
            for i=1:obj.clusters
               obj.SortedSpikes{i}=obj.Spikes(:,Sorter.z==i);
               
               % build spike matrix per cluster
               obj=BuildSpikeMatrix(obj,i);
            end

        end
        
        %% Average response across screen
        function obj=AvgResponse(obj)
            M=cat(1,obj.Mon{:});
            Mon=sum(M);
            M=cat(1,obj.Moff{:});
            Moff=sum(M);
            
            [Mon ~] = msdf(transpose(Mon),obj.kernel,obj.kernelW);
            [Moff ~] = msdf(transpose(Moff),obj.kernel,obj.kernelW);
            obj.avgOn=Mon/obj.nPos;
            obj.avgOff=Moff/obj.nPos;
            
            % On print
            f=figure('name','Avg On');
            plot(obj.x, obj.avgOn, 'b');
            obj.avgOnInfo = stepinfo(obj.avgOn,obj.x);
            hold on
            peaktime=obj.avgOnInfo.PeakTime;
            peak=obj.avgOnInfo.Peak;
            settlingtime=obj.avgOnInfo.SettlingTime;
            std1=std(obj.avgOn);
            str=[' Peak: ' num2str(peak) '\n Peak Time: ' num2str(peaktime) '\n Settling Time: ' num2str(settlingtime) '\n Std: ' num2str(std1)];
            str=sprintf(str);
            ylim=get(gca,'ylim');
            xlim=get(gca,'xlim');
            text(xlim(2)-200,ylim(2)-0.1,str)
            obj.SavePlot(f, 'AvgResponseOn');
            
            % Off print
            f=figure('name','Avg Off');
            plot(obj.x, obj.avgOff, 'b');
            
            hold on
            obj.avgOffInfo = stepinfo(obj.avgOff,obj.x);
            peaktime=obj.avgOffInfo.PeakTime;
            peak=obj.avgOffInfo.Peak;
            settlingtime=obj.avgOffInfo.SettlingTime;
            std1=std(obj.avgOff);
            str=[' Peak: ' num2str(peak) '\n Peak Time: ' num2str(peaktime) '\n Settling Time: ' num2str(settlingtime) '\n Std: ' num2str(std1)];
            str=sprintf(str);
            ylim=get(gca,'ylim');
            xlim=get(gca,'xlim');
            text(xlim(2)-200,ylim(2)-0.1,str)
            obj.SavePlot(f, 'AvgResponseOff');
        end
        
        %% Average response for clusters
        function obj=AvgResponseCluster(obj)
            for i=1:obj.clusters
                Mon=obj.Mon_clusters(:,i);
                Mon=cat(1,Mon{:});
                Mon=sum(Mon);
                
                Moff=obj.Moff_clusters(:,i);
                Moff=cat(1,Moff{:});
                Moff=sum(Moff);

                [Mon ~] = msdf(transpose(Mon),obj.kernel,obj.kernelW);
                [Moff ~] = msdf(transpose(Moff),obj.kernel,obj.kernelW);
                avgOn=Mon/obj.nPos;
                avgOff=Moff/obj.nPos;

                % On print
                f=figure('name','Avg On');
                plot(obj.x, avgOn, 'b');
                avgOnInfo = stepinfo(avgOn,obj.x);
                hold on
                peaktime=avgOnInfo.PeakTime;
                peak=avgOnInfo.Peak;
                settlingtime=avgOnInfo.SettlingTime;
                std1=std(avgOn);
                str=[' Peak: ' num2str(peak) '\n Peak Time: ' num2str(peaktime) '\n Settling Time: ' num2str(settlingtime) '\n Std: ' num2str(std1)];
                str=sprintf(str);
                ylim=get(gca,'ylim');
                xlim=get(gca,'xlim');
                text(xlim(2)-200,ylim(2)-0.1,str)
                obj.SavePlot(f, ['AvgResponseOn_cluster' num2str(i)]);
                
                % On print
                f=figure('name','Avg Off');
                plot(obj.x, avgOff, 'b');
                avgOffInfo = stepinfo(avgOff,obj.x);
                hold on
                peaktime=avgOffInfo.PeakTime;
                peak=avgOffInfo.Peak;
                settlingtime=avgOffInfo.SettlingTime;
                std1=std(avgOff);
                str=[' Peak: ' num2str(peak) '\n Peak Time: ' num2str(peaktime) '\n Settling Time: ' num2str(settlingtime) '\n Std: ' num2str(std1)];
                str=sprintf(str);
                ylim=get(gca,'ylim');
                xlim=get(gca,'xlim');
                text(xlim(2)-200,ylim(2)-0.1,str)
                obj.SavePlot(f, ['AvgResponseOff_cluster' num2str(i)]);
            end
        end
        
        %% print compare for Double Square Stim        
        function obj=DoubleStimPrint(obj)
            for i=1:obj.nPos
                for j=1:obj.nPos
                    if (i==j)
                        % create reduced bin matrix for LTI
                        obj.LTI_doubleMon{i,j}=obj.ReduceBins(obj.doubleMon{i,j});
                        obj.LTI_doubleMoff{i,j}=obj.ReduceBins(obj.doubleMoff{i,j});
                    elseif (isempty(obj.doubleMon{i,j}))
                        continue
                    else
                        % print raster + psth for double stim
                        obj.PrintDoublePlot(obj.doubleMon{i,i}, obj.doubleMon{j,j}, obj.doubleMon{i,j}, i, j, 'on');
                        obj.PrintDoublePlot(obj.doubleMoff{i,i}, obj.doubleMoff{j,j}, obj.doubleMoff{i,j}, i, j, 'off');
                        
                        % LTI reduced matrixes
                        obj.LTI_doubleMon{i,j}=obj.ReduceBins(obj.doubleMon{i,j});
                        obj.LTI_doubleMoff{i,j}=obj.ReduceBins(obj.doubleMoff{i,j});
                    end
                end
            end
            
            % find p values
            for i=1:obj.nPos
                for j=1:obj.nPos
                    if (i==j) || (isempty(obj.doubleMon{i,j}))
                        continue
                    else
                        obj=obj.calc_pvalue(i, j);
                    end
                end
            end
            
            obj.Print_pvalue('on');
            obj.Print_pvalue('off');
        end
        
        %% reduce bins of spike matrix from bins to LTI_bins
        function N=ReduceBins(obj, M)
            % new bins cutoff
            bins=obj.window/obj.bin;            %100
            cutoffBins=obj.LTI_cutoffBins*bins; %70
            binVector=1:cutoffBins/obj.LTI_bins:cutoffBins; % 1 8 15 ... 64
            
            % transform matrix (trials, bins) -> (trials, LTI_bins)
            N=[];
            for t=1:obj.LTI_bins
                N=[N sum(M(:,binVector(t):binVector(t)+(cutoffBins/obj.LTI_bins)-1),2)];
            end
        end
        
        %% calculate p values for all squares
        function obj=calc_pvalue(obj, i, j)
            % on
            M_add=obj.LTI_doubleMon{i,i}+obj.LTI_doubleMon{j,j};
            M_stim=obj.LTI_doubleMon{i,j};
            P=[];
            for t=1:obj.LTI_bins
                a=M_add(:,t);
                b=M_stim(:,t);
                [~,p_value]=ttest2(a,b);
                P=[P p_value];
            end
            obj.LTI_pvalue_On{i,j}=P;
            
            % off
            M_add=obj.LTI_doubleMoff{i,i}+obj.LTI_doubleMoff{j,j};
            M_stim=obj.LTI_doubleMoff{i,j};
            P=[];
            for t=1:obj.LTI_bins
                a=M_add(:,t);
                b=M_stim(:,t);
                [~,p_value]=ttest2(a,b);
                P=[P p_value];
            end
            obj.LTI_pvalue_Off{i,j}=P;
        end
        
        %% print pvalue
        function Print_pvalue(obj, type)
            if isequal(type,'on')
                pvalue=obj.LTI_pvalue_On;
            else
                pvalue=obj.LTI_pvalue_Off;
            end
            f=figure;
            file=fopen([obj.SpikeDir filesep 'pvalue_' type '.txt'], 'wt');
            
            
            % Build Screen
            for i=1:obj.nPos
                h=subaxis(f,obj.n,obj.m,obj.VSP.pos2X(i),obj.VSP.pos2Y(i),obj.axis{:});
                h.XTickLabel=[];h.YTickLabel=[];
                pos=h.Position;
                midx{i}=pos(1)+pos(3)/2;
                midy{i}=pos(2)+pos(4)/2;
                if obj.VSP.pos2Y(i)==1 && obj.VSP.pos2X(i)==round(obj.m/2)
                    title('Double Square Stimulation: p value')
                end
            end
            
            % Add Arrows
            for i=1:obj.nPos
                for j=1:obj.nPos
                    if (i==j) || (isempty(obj.doubleMon{i,j}))
                        continue
                    else
                        annotation('line', [midx{i} midx{j}], [midy{i} midy{j}], 'LineWidth', obj.pvalue_intensity*mean(pvalue{i,j}));
                        fprintf(file, '%d-%d:\n', i, j);
                        fprintf(file, '%.3f ', pvalue{i,j});
                        fprintf(file, '\n');
                    end
                end
            end
            fclose(file);
            SavePlot(obj, f, ['pvalue_' type]);
        end
        
        %% Plot Raster
        function f=RasterPlot(obj, M, f)
            
            % quantization values
            centrality = 0;
            left_right = 0;
            top_bottom = 0;
            
            % iterate over squares
            for i=1:obj.nPos
                % Screen Raster
                h=subaxis(f,obj.n,obj.m,obj.VSP.pos2X(i),obj.VSP.pos2Y(i),obj.axis{:});
                imagesc(obj.x,[],M{i});colormap(flipud(gray(5)));
                if i~=1
                    h.XTickLabel=[];h.YTickLabel=[];
                else
                    xlabel('Time [ms]', 'fontsize', 7);
                    ylabel('Trial #', 'fontsize', 7);
                end
                
                % Centrality (weights 1,3,9 based on central proximity)
                if obj.VSP.pos2X(i) == 1 || obj.VSP.pos2X(i) == obj.m || obj.VSP.pos2Y(i) == 1 || obj.VSP.pos2Y(i) == obj.n
                    centralityFactor = 1;
                elseif obj.VSP.pos2X(i) == round(obj.m/2) && obj.VSP.pos2Y(i) == round(obj.n/2)
                    centralityFactor = 9;
                else
                    centralityFactor = 3;
                end
                centrality = centrality + (centralityFactor * sum(sum(M{i})));
                
                % Left/Right
                if obj.VSP.pos2X(i) <= floor(obj.m/2) %left
                    factor = -1;
                elseif obj.VSP.pos2X(i) > round(obj.m/2) %right
                    factor = 1;
                else
                    factor = 0;
                end
                left_right = left_right + (factor * sum(sum(M{i})));
                
                % Top/Bottom
                if obj.VSP.pos2Y(i) <= floor(obj.n/2) %top
                    factor = 1;
                elseif obj.VSP.pos2Y(i) > round(obj.n/2) %bottom
                    factor = -1;
                else
                    factor = 0;
                end
                top_bottom = top_bottom + (factor * sum(sum(M{i})));
            end
            
            centrality = centrality/sum(sum([M{:}]))/9;
            left_right = left_right/sum(sum([M{:}]));
            top_bottom = top_bottom/sum(sum([M{:}]));
            h=subaxis(f, obj.n, obj.m, round(obj.m/2), obj.n);
            xlabel(['Centrality: ' num2str(centrality) ', Left vs Right: ' num2str(left_right) ', Top vs Bottom: ' num2str(top_bottom)]);

        end
        
        %% Plot PSTH
        function f=PsthPlot(obj, M, type, f)
            
            m=obj.m; n=obj.n;
            % find max over all tiles
            tilesMax=0;
            for i=1:obj.nPos
                tilesMax=max(tilesMax, max(sum(M{i})));
            end
            for i=1:obj.nPos
                % Screen
                psth=sum(M{i});
                h=subaxis(f,n,m,obj.VSP.pos2X(i),obj.VSP.pos2Y(i),obj.axis{:});
                
                % only print PSTH
                if type==0
                    bar(obj.x, psth, 'k', 'BarWidth',1);
                    axis([min(obj.x) max(obj.x) 0 tilesMax*1.2]);
                    
                % print PSTH + kernel
                elseif type==1
                    bar(obj.x, psth, 'EdgeColor', [0.3 0.3 0.3], 'FaceColor', [0.3 0.3 0.3], 'BarWidth',1);
                    axis([min(obj.x) max(obj.x) 0 tilesMax*1.2]);
                    hold on
                    [sdf ~] = msdf(transpose(psth),obj.kernel,obj.kernelW);
                    plot(obj.x, sdf(:,1),'m');
                    hold off
                    
                % print kernels of clusters on top of eachother (only done after sort)
                else
                    axis([min(obj.x) max(obj.x) 0 tilesMax*1]);
                    colormap=['r' 'b' 'g' 'm'];
                    hold on
                    for j=1:obj.clusters
                        M_cluster=M(:,j);
                        psth=sum(M_cluster{i});
                        [sdf ~] = msdf(transpose(psth),obj.kernel,obj.kernelW);
                        plot(obj.x, sdf(:,1),colormap(j));
                    end
                    hold off
                end
                
                % x/y axis
                if i~=n
                    h.XTickLabel=[];h.YTickLabel=[];
                else
                    xlabel('Time [ms]', 'fontsize', 7);
                    ylabel('Trial #', 'fontsize', 7);
                    if type==2
                        legend;
                    end
                end
            end
        end

        %% plot Raster+PSTH for double stim
        function PrintDoublePlot(obj, Mi, Mj, Mij, i, j, type)
            % dir
            figure;
            name = [num2str(i) '-' num2str(j)];
            dir=[obj.SpikeDir filesep 'Double Stim ' type];
            if ~exist(dir, 'dir')
                mkdir(dir);
            end

            % Raster
            h=subaxis(2,2,1,1,obj.axis{:});
            imagesc(obj.x,[],Mi);colormap(flipud(gray(5)));
            title(['Square: ' num2str(i)], 'FontSize', 9, 'color', 'b');
            
            h=subaxis(2,2,2,1,obj.axis{:});
            imagesc(obj.x,[],Mj);colormap(flipud(gray(5)));
            title(['Square: ' num2str(j)], 'FontSize', 9, 'color', 'b');
            
            h=subaxis(2,2,1,2,obj.axis{:});
            imagesc(obj.x,[],Mi+Mj);colormap(flipud(gray(5)));
            title('Addition', 'FontSize', 9, 'color', 'b');
            
            h=subaxis(2,2,2,2,obj.axis{:});
            imagesc(obj.x,[],Mij);colormap(flipud(gray(5)));
            title('Double-Stim', 'FontSize', 9, 'color', 'b');
            
            saveas(gca, fullfile(dir, ['Raster' name]), 'jpeg'); close;
            
            % PSTH
            figure;
            color_map=['r' 'b' 'g' 'm'];
            tilesMax=0;
            for t=1:obj.nPos
                tilesMax=max(tilesMax, max(sum(Mi+Mj)));
            end
            axis([min(obj.x) max(obj.x) 0 tilesMax]);

            hold on
            psth=sum(Mi);
            [sdf ~] = msdf(transpose(psth),obj.kernel,obj.kernelW);
            plot(obj.x, sdf(:,1),color_map(1));
            
            psth=sum(Mj);
            [sdf ~] = msdf(transpose(psth),obj.kernel,obj.kernelW);
            plot(obj.x, sdf(:,1),color_map(2));
            
            psth=sum(Mi+Mj);
            [sdf ~] = msdf(transpose(psth),obj.kernel,obj.kernelW);
            plot(obj.x, sdf(:,1),color_map(3));
            
            psth=sum(Mij);
            [sdf ~] = msdf(transpose(psth),obj.kernel,obj.kernelW);
            plot(obj.x, sdf(:,1),color_map(4));
            hold off
            legend(num2str(i), num2str(j), 'addition', 'double stim');
            saveas(gca, fullfile(dir, ['PSTH' name]), 'jpeg'); close;
        end
        
        %% Save and/or close a plot
        function SavePlot(obj, f, name)
            if obj.savePlots==1
                saveas(gca, fullfile(obj.SpikeDir, name), 'jpeg')
                if obj.closePlots==1
                    close(f)
                end
            end
        end
        
        %% plot before applying Spike Sort
        function obj=PlotBeforeSort(obj)
            
            % Raster plots
            f=figure('name','Raster On');f=obj.RasterPlot(obj.Mon, f);
            obj.SavePlot(f, 'GridRasterOn');
            
            f=figure('name','Raster Off');f=obj.RasterPlot(obj.Moff, f);
            obj.SavePlot(f, 'GridRasterOff');

            % PSTH plots
            f=figure('name','PSTH On');f=obj.PsthPlot(obj.Mon, obj.kernelPrint, f);
            obj.SavePlot(f, 'GridKernelOn');
            f=figure('name','PSTH On');f=obj.PsthPlot(obj.Mon, 0, f);
            obj.SavePlot(f, 'GridPSTHOn');

            f=figure('name','PSTH Off');f=obj.PsthPlot(obj.Moff, obj.kernelPrint, f);
            obj.SavePlot(f, 'GridKernelOff');
            f=figure('name','PSTH On');f=obj.PsthPlot(obj.Moff, 0, f);
            obj.SavePlot(f, 'GridPSTHOff');
            
            % average kernel
            obj=obj.AvgResponse;
            
            % Pre-sort SpikeCheck
            f=figure('units','normalized','position',[0.02 .1 .6 .6]);
            f=obj.SpkCheck(f, 0);
            obj.SavePlot(f, 'SpikeCheck(PreSort)');
        end
        
        %% plot after applying Spike Sort
        function PlotAfterSort(obj)
            
            % Raster + SpikeCheck for each cluster
            for i=1:obj.clusters
                clusterdir=[obj.SpikeDir filesep 'cluster_' num2str(i)];
                mkdir(clusterdir);
                f=figure('name','Raster On');f=obj.RasterPlot(obj.Mon_clusters(:,i), f);
                saveas(gca, fullfile(clusterdir, 'GridRasterOn'), 'jpeg'); close(f);

                f=figure('name','Raster Off');f=obj.RasterPlot(obj.Moff_clusters(:,i), f);
                saveas(gca, fullfile(clusterdir, 'GridRasterOff'), 'jpeg'); close(f);

                f=figure('units','normalized','position',[0.02 .1 .6 .6]);
                f=obj.SpkCheck(f, i);
                obj.SavePlot(f, ['SpikeCheck(cluster ' num2str(i) ')']);
            end
            
            % Kernel PSTH plots
            f=figure('name','PSTH On');f=obj.PsthPlot(obj.Mon_clusters, 2, f);
            obj.SavePlot(f, 'clustersPSTHOn');

            f=figure('name','PSTH Off');f=obj.PsthPlot(obj.Moff_clusters, 2, f);
            obj.SavePlot(f, 'clustersPSTHOff');

        end
        
        obj=DetectThreshold(obj);
        
        obj=SpkCheck(obj, f, i);
        
    end
end