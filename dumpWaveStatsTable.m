function dumpWaveStatsTable();
handles.mydata.wavefile = [];
if isempty(handles.mydata.wavefile),
    [filename, pathname] = uigetfile('p-cal.nc','Open a netCDF file containing ADCP wave data');
    if ~filename, return; end
    handles.mydata.wavefile = fullfile(pathname, filename);
end
if ~isfield(handles.mydata,'velfile') || isempty(handles.mydata.velfile),
    handles.mydata.velfile = [];
end
if ~isfield(handles.mydata,'windfile') || isempty(handles.mydata.windfile),
    handles.mydata.windfile = [];
end
if ~isfield(handles.mydata,'lf') || isempty(handles.mydata.lf),
    handles.mydata.lf = 0.03;
end
if ~isfield(handles.mydata,'hf') || isempty(handles.mydata.hf),
    handles.mydata.hf = 0.5;
end

% open the netCDF file and do the basic checks
if ~exist(handles.mydata.wavefile,'file'), disp(['Unable to find netCDF wave data file ',handles.mydata.wavefile]); return; end
ncwinfo = ncinfo(handles.mydata.wavefile);
fprintf('Reading from %s\n',handles.mydata.wavefile)
% if ~exist(handles.mydata.velfile,'file'), disp(['Unable to find netCDF velocity data file ',handles.mydata.velfile]); return; end
% ncvinfo = ncinfo(handles.mydata.velfile);
% fprintf('Reading from %s\n',handles.mydata.velfile)
if ~isempty(handles.mydata.windfile) || ~exist(handles.mydata.windfile,'file'), 
    disp(['Unable to find netCDF wind data file ',handles.mydata.windfile]); 
else
    ncwindinfo = ncinfo(handles.mydata.windfile);
    fprintf('Reading from %s\n',handles.mydata.windfile)
end

n = find(strncmp('direction',{ncwinfo.Variables.Name},length('direction')));
if ~isempty(n),
    handles.mydata.ndirs = ncwinfo.Variables(n).Size;
    handles.mydata.dirvals = ncread(handles.mydata.wavefile,'direction');
else
    fprintf('Wave directional spectra not found in %s\n',handles.mydata.wavefile);
    return; 
end
n = find(strncmp('frequency',{ncwinfo.Variables.Name},length('frequency')));
if ~isempty(n),
    handles.mydata.nfreqs = ncwinfo.Variables(n).Size;
    handles.mydata.freqvals = ncread(handles.mydata.wavefile,'frequency');
    for n=1:handles.mydata.nfreqs,
        handles.mydata.lstrings{n} = sprintf('%d',handles.mydata.freqvals(n));
    end
end

% the time dimension (the burst start)
info = ncinfo(handles.mydata.wavefile,'time');
handles.mydata.nbursts = info.Size; 

handles.mydata.insttype = 'unknown';
n = find(strncmp('instrument_type',{ncwinfo.Attributes.Name},length('instrument_type')),1);
if ~isempty(n), % defined
    handles.mydata.insttype = ncreadatt(handles.mydata.wavefile,'/','instrument_type');
end
n = find(strncmp('INST_TYPE',{ncwinfo.Attributes.Name},length('INST_TYPE')),1);
if ~isempty(n), % defined
    handles.mydata.insttype = ncreadatt(handles.mydata.wavefile,'/','INST_TYPE');
end
handles.mydata.awacscaling = 0;

n=1;
dspecidx = [];
varnames = {ncwinfo.Variables.Name};
for i=1:length(varnames), % remove burstnum and time
    if strcmp(varnames{i},'burst') || strcmp(varnames{i},'direction') || strcmp(varnames{i},'frequency') || ...
            strcmp(varnames{i},'depth') || strcmp(varnames{i},'lat') || strcmp(varnames{i},'lon') ||...
            strcmp(varnames{i},'time') || strcmp(varnames{i},'time2') ||...
            strcmp(varnames{i},'wh_4061') || strcmp(varnames{i},'wp_4060') || strcmp(varnames{i},'mwh_4064') ||...
            strcmp(varnames{i},'hght_18') || strcmp(varnames{i},'wp_peak') || strcmp(varnames{i},'wvdir') ||...
            strcmp(varnames{i},'dspecfirstdir'),
        % do nothing
    else % add to the list
        if strcmp(varnames{i},'dspec'), dspecidx = n; end % find directional spectrum
        fprintf('%s\n',varnames{i})
        handles.mydata.varnames{n} = varnames{i}; 
        n=n+1;
    end
end
if isempty(dspecidx), 
    fprintf('No directional spectrum variable dspec found in %s\n', handles.mydata.wavefile)
    return; 
end
handles.mydata.vartoplot = handles.mydata.varnames{dspecidx};

handles.mydata.iburst = 1;
handles.mydata.ifreq = 1; 
handles.mydata.rot_corr = 0;
handles.mydata.nfreqsinview = handles.mydata.nfreqs;
handles.mydata.freqs = [1 handles.mydata.nfreqs];
if handles.mydata.nfreqs < 500,
    handles.mydata.minfreqsinview = 1;
else handles.mydata.minfreqsinview = 500;
end

handles.mydata.burstNum = 1:handles.mydata.nbursts;
% the time dimension (the burst start)
% note we track three things here - the burst number given by the
% instrument, the burst number we've computed based on the number of bursts, 
% - which will be the index into the data
if ~isempty(find(strncmp('burst', {ncwinfo.Variables.Name}, length('burst')), 1)),
    disp('Loading the burst numbers, one moment...')
    handles.mydata.burstNumInst = ncread(handles.mydata.wavefile,'burst');
else
    disp('Computing burst numbers based on length of time variable, one moment...')
    info = ncinfo(handles.mydata.wavefile,'time');
    handles.mydata.burstNumInst = 1:info.Size;    
end
% load in the time for convenience
info = ncinfo(handles.mydata.wavefile,'time');
if length(info.Dimensions) == 1,
    t1 = double(ncread(handles.mydata.wavefile,'time',1,Inf));
    t2 = double(ncread(handles.mydata.wavefile,'time2',1,Inf));
elseif length(info.Dimensions) == 2,
    t1 = double(ncread(handles.mydata.wavefile,'time',[1 1],[1 Inf]));
    t2 = double(ncread(handles.mydata.wavefile,'time2',[1 1],[1 Inf]));
else
    fprintf('Time has more than two dimensions (it has %d)\n',length(info.Dimensions))
end
handles.mydata.tm = datenum(gregorian(t1+t2./(1000*3600*24)));

% put the psdev data in memory - checking the wave file
varnames = {ncwinfo.Variables.Name};
names2find = {'wh_4061','mwh_4064','SDP_850'}; % there have been several flavors
for idx=1:length(names2find), % make sure this is a burst data file
    n = find(strncmp(names2find{idx}, varnames, length(names2find{idx})),1);
    if ~isempty(n),
        info = ncinfo(handles.mydata.wavefile,varnames{n});
        break;
    end
end
if ~isempty(n), % we never found a burst dimension we know
    disp('Loading the psdev or height time series time series data')
    handles.mydata.psdev = ncread(handles.mydata.wavefile,info.Name);
    handles.mydata.psdev = squeeze(handles.mydata.psdev);
    handles.mydata.psdevunits = ncreadatt(handles.mydata.wavefile,info.Name,'units');
    try % files may not have 'name' attribute
        handles.mydata.psdevname = ncreadatt(handles.mydata.wavefile,info.Name,'name');
    catch
        try handles.mydata.psdevname = ncreadatt(handles.mydata.wavefile,info.Name,'generic_name');    
        catch 
            handles.mydata.psdevname = varnames{n}; 
        end
    end
    handles.mydata.tmvel = handles.mydata.tm;
else
    disp('no known psdev or height time series found in file')
end

% now look up some things ahead because the Native calls are so unforgiving
names2find = {'dspecfirstdir'}; % there have been several flavors
for idx=1:length(names2find), % make sure this is a burst data file
    n = find(strncmp(names2find{idx}, varnames, length(names2find{idx})));
    if ~isempty(n),
        info = ncinfo(handles.mydata.wavefile,varnames{n});
        handles.mydata.dir1name = info.Name;
        break;
    end
end
if isempty(n), handles.mydata.dir1name = []; end

% set(handles.textStats,'String',sprintf(...
%     ' %s %5.1f %s; %s %5.1f %s;  %s %5.1f %s; %s %5.1f %s; %s',...
%     ncw{'wh_4061'}.name(:), ncw{'wh_4061'}(handles.mydata.iburst), ncw{'wh_4061'}.units(:),...
%     ncw{'wp_4060'}.name(:), ncw{'wp_4060'}(handles.mydata.iburst), ncw{'wp_4060'}.units(:),...
%     ncw{'wp_peak'}.name(:), ncw{'wp_peak'}(handles.mydata.iburst), ncw{'wp_peak'}.units(:),...
%     ncw{'wvdir'}.name(:), ncw{'wvdir'}(handles.mydata.iburst)+handles.mydata.rot_corr,...
%     ncw{'wvdir'}.units(:), ncw{'wvdir'}.NOTE(:)));
names2find = {'wh_4061','wp_4060','wp_peak','wvdir'}; % there have been several flavors
statidx = 0;
for idx=1:length(names2find), % make sure this is a burst data file
    n = find(strncmp(names2find{idx}, varnames, length(names2find{idx})),1);
    if ~isempty(n),
        statidx = statidx+1;
        handles.mydata.stats.info(statidx) = ncinfo(handles.mydata.wavefile,varnames{n});
    end
end



%%
% these stats are from the vendor's software calculations
nstats = length(handles.mydata.stats.info);
tabledata = {}; 
tableheader = {'Burst Number', 'Datetime'};
tableunits = {'integer', 'dd-mmm-yyyy HH:MM:SS'};
for istat = 1:nstats,
    tableunits(1,istat+2) = {ncreadatt(handles.mydata.wavefile,...
        handles.mydata.stats.info(istat).Name,'units')};
    tableheader(1,istat+2) = {handles.mydata.stats.info(istat).Name};
end
for j=handles.mydata.burstNum
    tabledata(j,1) = num2cell(j);  % Burst No
    tabledata(j,2) = {datestr(handles.mydata.tm(j))};  % Date
    handles.mydata.iburst = j;
    nstats = length(handles.mydata.stats.info);
    buf = []; 
    for istat = 1:nstats,
        ndims = length(handles.mydata.stats.info(istat).Dimensions);
        if ndims == 3, % RDI version lat, lon, time
            corner = [1,1,handles.mydata.iburst];
            edges = [1 1 1];
        else
            corner = handles.mydata.iburst;
            edges = 1;
        end
        statdata = squeeze(ncread(handles.mydata.wavefile,handles.mydata.stats.info(istat).Name,corner,edges));
        statunits = ncreadatt(handles.mydata.wavefile,handles.mydata.stats.info(istat).Name,'units');
        tabledata(j,istat+2) = num2cell(statdata);
        
        if strncmp('wvdir',handles.mydata.stats.info(istat).Name,length('wvdir')),
            statdata = statdata+handles.mydata.rot_corr;
            buf = sprintf('%s %s %5.1f %s; ',buf,handles.mydata.stats.info(istat).Name,statdata,statunits);
            % want the note about direction from
            n = find(strncmp('NOTE',{handles.mydata.stats.info(istat).Attributes.Name}, length('NOTE')),1);
            buf = [buf ' ' handles.mydata.stats.info(istat).Attributes(n).Value ' '];
        else
            buf = sprintf('%s %s %5.1f %s; ',buf,handles.mydata.stats.info(istat).Name,statdata,statunits);
        end
        
    end
end
% set(handles.textStats,'String',buf);
% set(handles.textInstBurstNum,'String',sprintf('Inst. Burst #%4d',...
%     handles.mydata.burstNumInst(handles.mydata.iburst)));

%%
% Check for existing file
[excel_file,excel_path] = uiputfile('*.xlsx','Save *.xlsx file',...
    fullfile(pwd));

if ischar(excel_path) % The user did not hit "Cancel"
    outfile = fullfile(excel_path,excel_file);
    %log_text = vertcat(log_text,{outfile});
    
    % Delete the old file if it exists
    if exist(outfile, 'file') == 2
        log_text = {'Warning: The file';...
            ['   ' outfile];...
            'already exists. Overwriting file...'};
        delete(outfile)
    end
end

outtable = vertcat(tableheader,tableunits,tabledata);

fileName = fullfile(excel_path,excel_file);
xlswrite(fileName,outtable);

%%
function H = ActiveXHeadings()
% Create ActiveX Property Structures for formatting Excel documents
% All heading types are sub-structs of H, and can be passed to
% Excel_Write_Format.

% Property Types

% Heading 1
H.h1.Font.Bold = 0;
H.h1.Font.Color = RGB_2_BGR_Hex([0.05 0.35 0.7]); %note RGB_2_BGR_HEX call
H.h1.Font.Name = 'Arial Black';
H.h1.Font.Size = 14;
H.h1.Range.ColumnWidth = 83;
H.h1.Range.RowHeight = 20;
H.h1.Range.HorizontalAlignment = 'Left';
H.h1.Range.VerticalAlignment = 'Center';

% Heading 2
H.h2.Font.Bold = 1;
H.h2.Font.Color = RGB_2_BGR_Hex([0 0 0]); %note RGB_2_BGR_HEX call
H.h2.Font.Name = 'Arial';
H.h2.Font.Size = 12;
H.h2.Range.ColumnWidth = 83;
H.h2.Range.RowHeight = 15;
H.h2.Range.HorizontalAlignment = 'Left';
H.h2.Range.VerticalAlignment = 'Distributed';

% Heading 3
H.h3.Font.Bold = 1;
H.h3.Font.Color = RGB_2_BGR_Hex([0 0 0]); %note RGB_2_BGR_HEX call
H.h3.Font.Name = 'Arial';
H.h3.Font.Size = 12;
H.h3.Range.WrapText = 1;
H.h3.Range.ColumnWidth = 20;
%H.h3.Range.RowHeight = 15;
H.h3.Range.HorizontalAlignment = 'Left';
H.h3.Range.VerticalAlignment = 'Top';

% Body Text 1 (wide column)
H.t1.Font.Bold = 0;
H.t1.Font.Color = RGB_2_BGR_Hex([0 0 0]); %note RGB_2_BGR_HEX call
H.t1.Font.Name = 'Calibri';
H.t1.Font.Size = 11;
H.t1.Range.ColumnWidth = 83;
H.t1.Range.RowHeight = 15;
H.t1.Range.HorizontalAlignment = 'Left';

% Body Text 2 (narrow column)
H.t2.Font.Bold = 0;
H.t2.Font.Color = RGB_2_BGR_Hex([0 0 0]); %note RGB_2_BGR_HEX call
H.t2.Font.Name = 'Calibri';
H.t2.Font.Size = 11;
H.t2.Range.ColumnWidth = 10;
H.t2.Range.RowHeight = 15;
H.t2.Range.HorizontalAlignment = 'Left';

% Date and Time
H.d1.Font.Bold = 0;
H.d1.Font.Color = RGB_2_BGR_Hex([0 0 0]); %note RGB_2_BGR_HEX call
H.d1.Font.Name = 'Calibri';
H.d1.Font.Size = 11;
H.d1.Range.ColumnWidth = 31;
H.d1.Range.RowHeight = 15;
H.d1.Range.HorizontalAlignment = 'Right';
H.d1.Range.NumberFormat = 'mm/dd/yyyy h:mm:ss';

% Number 1 (rounded to nearest whole number)
H.n1.Font.Bold = 0;
H.n1.Font.Color = RGB_2_BGR_Hex([0 0 0]); %note RGB_2_BGR_HEX call
H.n1.Font.Name = 'Calibri';
H.n1.Font.Size = 11;
H.n1.Range.ColumnWidth = 31;
H.n1.Range.RowHeight = 15;
H.n1.Range.HorizontalAlignment = 'Right';
H.n1.Range.NumberFormat = '0';

% Number 2 (Rounded to nearest tenth)
H.n2.Font.Bold = 0;
H.n2.Font.Color = RGB_2_BGR_Hex([0 0 0]); %note RGB_2_BGR_HEX call
H.n2.Font.Name = 'Calibri';
H.n2.Font.Size = 11;
H.n2.Range.ColumnWidth = 31;
H.n2.Range.RowHeight = 15;
H.n2.Range.HorizontalAlignment = 'Right';
H.n2.Range.NumberFormat = '0.0';

