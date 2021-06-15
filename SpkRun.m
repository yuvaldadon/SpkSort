%% Recording list
OutputDir='/home/nadav_yuval/PolarizationOutputFinal_Final';
RecordingFolder{1}='/media/sil2/Data/Locust/March 20/010320/Rect_grid_002_2020-03-01_16-49-46';
StimDir{1}='/media/sil2/Data/Locust/March 20/010320/Expt_200301_VStim/Exp_200301/Rect_grid_an1_002.mat';
RecordingFolder{2}='/media/sil2/Data/Locust/March 20/010320/Rect_grid_003_2020-03-01_17-33-51';
StimDir{2}='/media/sil2/Data/Locust/March 20/010320/Expt_200301_VStim/Exp_200301/Rect_grid_an1_003.mat';
RecordingFolder{3}='/media/sil2/Data/Locust/August 20/170820/RectGrid_An1_001_2020-08-17_10-30-28';
StimDir{3}='/media/sil2/Data/Locust/August 20/170820/Vstim/RectGrid_An1_001.mat';
RecordingFolder{4}='/media/sil2/Data/Locust/August 20/310820/RectGrid_An1_001_2020-08-31_10-49-54';
StimDir{4}='/media/sil2/Data/Locust/August 20/310820/Vstim/RectGrid_An1_001.mat';
RecordingFolder{5}='/media/sil2/Data/Locust/September 20/030920/RectGrid_An2_001_2020-09-03_17-07-22';
StimDir{5}='/media/sil2/Data/Locust/September 20/030920/Vstim/RectGrid_An2_001.mat';
RecordingFolder{6}='/media/sil2/Data/Locust/September 20/070920/RectGrid_An1_002_2020-09-07_14-57-47';
StimDir{6}='/media/sil2/Data/Locust/September 20/070920/Vstim/RectGrid_An1_002.mat';
RecordingFolder{7}=['/media/sil2/Data/Locust/polariztaion_newData/data_2405' filesep 'experiment1_100.raw.kwd'];
StimDir{7}='/media/sil2/Data/Locust/polariztaion_newData/24_05/rectPairs_2021_5_24_16_8_8_799.mat';

% 3 -> lower threshold to 10-15
% 4,6 -> inc threshold to 30-35
%

%% initialize
for i=4:4
   %recording object
   [~, ~, fExt] = fileparts(RecordingFolder{i});
   if isempty(fExt)
       RecordingObj=OERecording(RecordingFolder{i});
       doubleStim=0;
   else
       RecordingObj=KwikRecording(RecordingFolder{i});
       doubleStim=1;
   end
    
   %spike object
   SpikeObj=SpkSort(RecordingObj, StimDir{i}, OutputDir, 'doubleStim', doubleStim, 'factorThreshold', 37);
   
   %plots before sorting
   SpikeObj.PlotBeforeSort;
   
   %sort spikes
   SpikeObj=SpikeObj.SortSpikes;
   
   %plots after sorting
   SpikeObj.PlotAfterSort;
   
   %LTI plots
   if doubleStim
       SpikeObj=SpikeObj.DoubleStimPrint;
   end
end

