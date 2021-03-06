%%%%% Task 1

%clc
clear;

addpath(fullfile(pwd, 'matlab_bgl'));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Dataset Path
dataDir = './Large_Dataset/with_landmask';

%%% R Threshold
R_THRESH = 0.90;

%%% Super Nodes XLS File
SuperNodes_XLS_File = ['SuperNodes_Task_3_S1_R_', num2str(R_THRESH), '.xls'];
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
YearRange = 1979:2005;
s = 1; % s = {1, 2, 3, 4};
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
WeekRange = 1:52;
NumRows = 448;
NumCols = 304;
NumYear = size(YearRange, 2);
NumWeek = size(WeekRange, 2);
DATA_VAL_LAND = 168;
DATA_VAL_MISS = 157;

CORR_BLOCK_LEN = 10000;
WRITE_XLS_ENABLE = true;

i = 1;
Data_Raw_Vect = zeros(NumRows*NumCols, NumYear*NumWeek);
for Year = YearRange
    for Week = WeekRange
        if(Week < 10)
            WeekStr = ['0', num2str(Week)];
        else
            WeekStr = num2str(Week);
        end
        
        FileName = ['/', num2str(Year), '/', 'diff', ...
                    'w', WeekStr, 'y', num2str(Year), '+', 'landmask'];
        FullFilePath = fullfile(dataDir, FileName);
        FileID = fopen(FullFilePath);
        Data_Raw_Vect(:, i) =  fread(FileID, 'float', 'ieee-le');
        i = i + 1;
        fclose(FileID);
    end
end
clearvars Year Week WeekStr FileName FullFilePath FileID i;

%%% MAP
Land_Miss_Mask = (Data_Raw_Vect(:,1)==DATA_VAL_LAND) .* DATA_VAL_LAND;
Land_Miss_Mask = Land_Miss_Mask + (Data_Raw_Vect(:,1)==DATA_VAL_MISS) .* DATA_VAL_MISS;

Land_Miss_Map = zeros(NumRows, NumCols, 3);
Map_Temp = logical(reshape(Land_Miss_Mask, [NumCols NumRows])');
Land_Miss_Map(:,:,1) = 255 * Map_Temp;
Land_Miss_Map(:,:,2) = 255 * Map_Temp;
Land_Miss_Map(:,:,3) = 255 * Map_Temp;
clearvars Map_Temp;
%%%

%%% Corr
Data_Vect = Data_Raw_Vect(~Land_Miss_Mask, :);
NumDataPoints = size(Data_Vect, 1);
clearvars Data_Raw_Vect;

Total_Edges = 0;
Corr_Graph = logical( sparse(NumDataPoints, NumDataPoints) );
for x = 1:CORR_BLOCK_LEN:(NumDataPoints-1)
    r = corr(Data_Vect(x:min((x+CORR_BLOCK_LEN-1),end), 1:end-s)', Data_Vect(:, s+1:end)', 'type', 'Pearson');
    r = abs(r)';
    for i = 1:size(r, 2)
        r_i = r(:,i);
        r_i( x+(i-1) ) = [];
        r_i = find(r_i >= R_THRESH);
        if( ~isempty(r_i) )
            Corr_Graph(x+(i-1), r_i) = logical(true);
            Total_Edges = Total_Edges + length(r_i);
        end
    end
end
%Corr_Graph = Corr_Graph + Corr_Graph';
    
clearvars r
%%%


Degree_Temp = sum(Corr_Graph, 2);
clearvars Degree
[Degree(:,1), ~, Degree(:,2)] = find(Degree_Temp);
clearvars Degree_Temp;
NumVert = size(Degree, 1);

figure(1);
histogram(Degree(:,2), 'BinMethod', 'integers');


Degree_Mean = mean(Degree(:,2));

Nodes_Temp = zeros(NumDataPoints, 1);
Nodes_Temp(Degree(:,1), :) = Degree(:,2);
Nodes_2D = zeros(NumRows*NumCols, 1);
Nodes_2D( ~Land_Miss_Mask ) = Nodes_Temp;
Nodes_2D = reshape(Nodes_2D, [NumCols NumRows])';
clearvars Nodes_Temp;

% Super_Nodes = Degree((Degree(:,2)>Degree_Mean), :);
% Super_Nodes_Temp = zeros(NumDataPoints, 1);
% Super_Nodes_Temp(Super_Nodes(:,1)) = Super_Nodes(:,2);
% Super_Nodes_2D = zeros(NumRows*NumCols, 1);
% Super_Nodes_2D( ~Land_Miss_Mask ) = Super_Nodes_Temp;
% Super_Nodes_2D = reshape(Super_Nodes_2D, [NumCols NumRows])';
% clearvars Super_Nodes_Temp;

Super_Nodes_2D = (Nodes_2D>Degree_Mean) .* Nodes_2D;

ColorMap = parula(range(Nodes_2D(:))+1);
ColorMap(1,:) = [0 0 0];
Nodes_RGB = ind2rgb(Nodes_2D - min(Nodes_2D(:)) + 1, ColorMap);
Super_Nodes_RGB = ind2rgb(Super_Nodes_2D - min(Super_Nodes_2D(:)) + 1, ColorMap);

Super_Red_Map = Land_Miss_Map;
Super_Red_Map(:,:,1) = Land_Miss_Map(:,:,1) + (Super_Nodes_2D ~= 0) * 255;

figure(2);
image( Super_Red_Map );
figure(3);
image( Land_Miss_Map + Nodes_RGB );
figure(4);
image( Land_Miss_Map + Super_Nodes_RGB );


if WRITE_XLS_ENABLE
[Super_Nodes_XY(:,1), Super_Nodes_XY(:,2), Super_Nodes_XY(:,3)] = find(Super_Nodes_2D);
try
    if( exist( SuperNodes_XLS_File, 'file') )
        delete( SuperNodes_XLS_File );
    end
    title = {'Super Node (Row)' 'Super Node (Col)' 'Degree'};
    xlswrite(SuperNodes_XLS_File, [title; num2cell(Super_Nodes_XY)]);
catch
   disp('Cannot write file'); 
end
end


index = 1;
Total_Pairs = 0;
Short_Path_Sum = 0;
Cluster_E = zeros(size(Degree, 1), 1);
for v=1:NumDataPoints
    N = find(Corr_Graph(v, :))';
    if(isempty(N))
        continue;
    end
    E_v = 0;
    for x=1:size(N, 1)
        for y=x+1:size(N, 1)
            if(Corr_Graph(N(x,1), N(y,1)) == true)
                E_v = E_v + 1;
            end
        end
    end
    Cluster_E(index, 1) = E_v;
    
    %Dist = shortest_paths(Corr_Graph, v)';
    Dist = shortest_paths(double(Corr_Graph), v)';
    %[Dist, ~, ~] = graphshortestpath(Corr_Graph, v, 'Method', 'BFS', 'Directed', false);
    Dist( isinf(Dist) ) = [];
    Short_Path_Sum = Short_Path_Sum + sum( Dist );
    Total_Pairs = Total_Pairs + size(Dist, 2) - 1;
    
    index = index + 1;
end
clearvars N E_v;


Cluster_Coeff_v = (2 * Cluster_E(:,1)) ./ (Degree(:,2) .* (Degree(:,2)-1));
Cluster_Coeff_Size = size(Cluster_Coeff_v, 1); 
Cluster_Coeff_v( isnan(Cluster_Coeff_v) ) = [];
Cluster_Coeff_v( isinf(Cluster_Coeff_v) ) = [];
Cluster_Coeff = sum(Cluster_Coeff_v) / Cluster_Coeff_Size;


CharPath_Len = Short_Path_Sum / Total_Pairs;

%%% Random Graph
Cluster_Coeff_Rand = Degree_Mean / NumVert;
CharPath_Len_Rand = log(NumVert) / log(Degree_Mean);
%%%%%%%%%%%%%%%

fprintf('\nDegree Mean = %f', Degree_Mean);
fprintf('\nClustering Coeff (G_r) =\t %f', Cluster_Coeff);
fprintf('\nClustering Coeff (G_rand) = %f', Cluster_Coeff_Rand);
fprintf('\nCharacteristic Path Length (L_r) =\t %f', CharPath_Len);
fprintf('\nCharacteristic Path Length (L_rand) = %f', CharPath_Len_Rand);
fprintf('\n');



