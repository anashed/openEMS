%
% EXAMPLE / antennas / patch antenna array
%
% This example demonstrates how to:
%  - calculate the reflection coefficient of a patch antenna array
% 
%
% Tested with
%  - Matlab 2009b
%  - Octave 3.3.52
%  - openEMS v0.0.23
%
% (C) 2010 Thorsten Liebig <thorsten.liebig@uni-due.de>

close all
clear
clc

%% switches & options...
postprocessing_only = 0;
draw_3d_pattern = 0; % this may take a (very long) while...
use_pml = 0;         % use pml boundaries instead of mur
openEMS_opts = '';

%% setup the simulation
physical_constants;
unit = 1e-3; % all length in mm

% width in x-direction
% length in y-direction
% main radiation in z-direction
patch.width  = 32.86; % resonant length
patch.length = 41.37;

% define array size and dimensions
array.xn = 4;
array.yn = 4;
array.x_spacing = patch.width * 3;
array.y_spacing = patch.length * 3;

substrate.epsR   = 3.38;
substrate.kappa  = 1e-3 * 2*pi*2.45e9 * EPS0*substrate.epsR;
substrate.width  = 60 + (array.xn-1) * array.x_spacing;
substrate.length = 60 + (array.yn-1) * array.y_spacing;
substrate.thickness = 1.524;
substrate.cells = 4;

feed.pos = -5.5;
feed.width = 2;
feed.R = 50; % feed resistance

% size of the simulation box around the array
SimBox = [50+substrate.width 50+substrate.length 25];

%% prepare simulation folder
Sim_Path = 'tmp';
Sim_CSX = 'patch_array.xml';
if (postprocessing_only==0)
    [status, message, messageid] = rmdir( Sim_Path, 's' ); % clear previous directory
    [status, message, messageid] = mkdir( Sim_Path ); % create empty simulation folder
end

%% setup FDTD parameter & excitation function
max_timesteps = 30000;
min_decrement = 1e-5; % equivalent to -50 dB
f0 = 0e9; % center frequency
fc = 3e9; % 10 dB corner frequency (in this case 0 Hz - 3e9 Hz)
FDTD = InitFDTD( max_timesteps, min_decrement );
FDTD = SetGaussExcite( FDTD, f0, fc );
BC = {'MUR' 'MUR' 'MUR' 'MUR' 'MUR' 'MUR'}; % boundary conditions
if (use_pml>0)
    BC = {'PML_8' 'PML_8' 'PML_8' 'PML_8' 'PML_8' 'PML_8'}; % use pml instead of mur
end
FDTD = SetBoundaryCond( FDTD, BC );

%% setup CSXCAD geometry & mesh
% currently, openEMS cannot automatically generate a mesh
max_res = c0 / (f0+fc) / unit / 20; % cell size: lambda/20
CSX = InitCSX();
mesh.x = [-SimBox(1)/2 SimBox(1)/2 -substrate.width/2 substrate.width/2];
mesh.y = [-SimBox(2)/2 SimBox(2)/2 -substrate.length/2 substrate.length/2];

mesh.z = [-SimBox(3)/2 linspace(0,substrate.thickness,substrate.cells) SimBox(3) ];
mesh.z = SmoothMeshLines( mesh.z, max_res, 1.4 );

for xn=1:array.xn
    for yn=1:array.yn
        midX = (array.xn/2 - xn + 1/2) * array.x_spacing;
        midY = (array.yn/2 - yn + 1/2) * array.y_spacing;
        
        % feeding mesh
        mesh.x = [mesh.x midX+feed.pos];
        mesh.y = [mesh.y midY-feed.width/2 midY+feed.width/2];
         
        % add patch mesh with 2/3 - 1/3 rule
        mesh.x = [mesh.x midX-patch.width/2-max_res/2*0.66  midX-patch.width/2+max_res/2*0.33  midX+patch.width/2+max_res/2*0.66  midX+patch.width/2-max_res/2*0.33];
        % add patch mesh with 2/3 - 1/3 rule
        mesh.y = [mesh.y midY-patch.length/2-max_res/2*0.66 midY-patch.length/2+max_res/2*0.33 midY+patch.length/2+max_res/2*0.66 midY+patch.length/2-max_res/2*0.33];
    end
end
mesh.x = SmoothMeshLines( mesh.x, max_res, 1.4); % create a smooth mesh between specified mesh lines
mesh.y = SmoothMeshLines( mesh.y, max_res, 1.4 );

mesh = AddPML( mesh, [8 8 8 8 8 8] ); % add equidistant cells (air around the structure)
CSX = DefineRectGrid( CSX, unit, mesh );

%% create substrate
CSX = AddMaterial( CSX, 'substrate' );
CSX = SetMaterialProperty( CSX, 'substrate', 'Epsilon', substrate.epsR, 'Kappa', substrate.kappa);
start = [-substrate.width/2 -substrate.length/2 0];
stop  = [ substrate.width/2  substrate.length/2 substrate.thickness];
CSX = AddBox( CSX, 'substrate', 0, start, stop );

%% create ground (same size as substrate)
CSX = AddMetal( CSX, 'gnd' ); % create a perfect electric conductor (PEC)
start(3)=0;
stop(3) =0;
CSX = AddBox(CSX,'gnd',10,start,stop);
%%
CSX = AddMetal( CSX, 'patch' ); % create a perfect electric conductor (PEC)
number = 1;
for xn=1:array.xn
    for yn=1:array.yn
        
        midX = (array.xn/2 - xn + 1/2) * array.x_spacing;
        midY = (array.yn/2 - yn + 1/2) * array.y_spacing;
        
        % create patch
        start = [midX-patch.width/2 midY-patch.length/2 substrate.thickness];
        stop  = [midX+patch.width/2 midY+patch.length/2 substrate.thickness];
        CSX = AddBox(CSX,'patch',10,start,stop);

        % apply the excitation & resist as a current source
        start = [midX+feed.pos-feed.width/2 midY-feed.width/2 0];
        stop  = [midX+feed.pos+feed.width/2 midY+feed.width/2 substrate.thickness];
        [CSX] = AddLumpedPort(CSX, 5, number,feed.R, start, stop,[0 0 1],['excite_' int2str(xn) '_' int2str(yn)]);
        number=number+1;
    end
end

%%nf2ff calc
[CSX nf2ff] = CreateNF2FFBox(CSX, 'nf2ff', -SimBox/2, SimBox/2);

if (postprocessing_only==0)
    %% write openEMS compatible xml-file
    WriteOpenEMS( [Sim_Path '/' Sim_CSX], FDTD, CSX );

    %% show the structure
    CSXGeomPlot( [Sim_Path '/' Sim_CSX] );

    %% run openEMS
    RunOpenEMS( Sim_Path, Sim_CSX, openEMS_opts );
end

%% postprocessing & do the plots
freq = linspace( max([1e9,f0-fc]), f0+fc, 501 );
U = ReadUI( {'port_ut1','et'}, 'tmp/', freq ); % time domain/freq domain voltage
I = ReadUI( 'port_it1', 'tmp/', freq ); % time domain/freq domain current (half time step is corrected)

% plot time domain voltage
figure
[ax,h1,h2] = plotyy( U.TD{1}.t/1e-9, U.TD{1}.val, U.TD{2}.t/1e-9, U.TD{2}.val );
set( h1, 'Linewidth', 2 );
set( h1, 'Color', [1 0 0] );
set( h2, 'Linewidth', 2 );
set( h2, 'Color', [0 0 0] );
grid on
title( 'time domain voltage' );
xlabel( 'time t / ns' );
ylabel( ax(1), 'voltage ut1 / V' );
ylabel( ax(2), 'voltage et / V' );
% now make the y-axis symmetric to y=0 (align zeros of y1 and y2)
y1 = ylim(ax(1));
y2 = ylim(ax(2));
ylim( ax(1), [-max(abs(y1)) max(abs(y1))] );
ylim( ax(2), [-max(abs(y2)) max(abs(y2))] );

% plot feed point impedance
figure
Zin = U.FD{1}.val ./ I.FD{1}.val;
plot( freq/1e6, real(Zin), 'k-', 'Linewidth', 2 );
hold on
grid on
plot( freq/1e6, imag(Zin), 'r--', 'Linewidth', 2 );
title( 'feed point impedance' );
xlabel( 'frequency f / MHz' );
ylabel( 'impedance Z_{in} / Ohm' );
legend( 'real', 'imag' );

% plot reflection coefficient S11
figure
uf_inc = 0.5*(U.FD{1}.val + I.FD{1}.val * 50);
if_inc = 0.5*(I.FD{1}.val - U.FD{1}.val / 50);
uf_ref = U.FD{1}.val - uf_inc;
if_ref = I.FD{1}.val - if_inc;
s11 = uf_ref ./ uf_inc;
plot( freq/1e6, 20*log10(abs(s11)), 'k-', 'Linewidth', 2 );
grid on
title( 'reflection coefficient S_{11}' );
xlabel( 'frequency f / MHz' );
ylabel( 'reflection coefficient |S_{11}|' );

%%
number = 1;
P_in = 0;
for xn=1:array.xn
    for yn=1:array.yn
        
        U = ReadUI( ['port_ut' int2str(number)], 'tmp/', freq ); % time domain/freq domain voltage
        I = ReadUI( ['port_it' int2str(number)], 'tmp/', freq ); % time domain/freq domain current (half time step is corrected)

        P_in = P_in + 0.5*U.FD{1}.val .* conj( I.FD{1}.val );
        number=number+1;
    end
end


%% NFFF contour plots %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
f_res_ind = find(s11==min(s11));
f_res = freq(f_res_ind);

% calculate the far field at phi=0 degrees and at phi=90 degrees
thetaRange = (0:2:359) - 180;
r = 1; % evaluate fields at radius r
disp( 'calculating far field at phi=[0 90] deg...' );
[E_far_theta,E_far_phi,Prad,Dmax] = AnalyzeNF2FF( Sim_Path, nf2ff, f_res, thetaRange, [0 90], r );

Dlog=10*log10(Dmax);

% display power and directivity
disp( ['radiated power: Prad = ' num2str(Prad) ' Watt']);
disp( ['directivity: Dmax = ' num2str(Dlog) ' dBi'] );
disp( ['efficiency: nu_rad = ' num2str(100*Prad./real(P_in(f_res_ind))) ' %']);

% calculate the e-field magnitude for phi = 0 deg
E_phi0_far = zeros(1,numel(thetaRange));
for n=1:numel(thetaRange)
    E_phi0_far(n) = norm( [E_far_theta(n,1) E_far_phi(n,1)] );
end

E_phi0_far_log = 20*log10(abs(E_phi0_far)/max(abs(E_phi0_far)));
E_phi0_far_log = E_phi0_far_log + Dlog;

% display radiation pattern
figure
plot( thetaRange, E_phi0_far_log ,'k-' );
xlabel( 'theta (deg)' );
ylabel( 'directivity (dBi)');
grid on;
hold on;

% calculate the e-field magnitude for phi = 90 deg
E_phi90_far = zeros(1,numel(thetaRange));
for n=1:numel(thetaRange)
    E_phi90_far(n) = norm([E_far_theta(n,2) E_far_phi(n,2)]);
end

E_phi90_far_log = 20*log10(abs(E_phi90_far)/max(abs(E_phi90_far)));
E_phi90_far_log = E_phi90_far_log + Dlog;

plot( thetaRange, E_phi90_far_log ,'r-' );
legend('phi=0','phi=90')

drawnow

if (draw_3d_pattern==0)
    return
end
%% calculate 3D pattern
tic
phiRange = 0:3:360;
thetaRange = unique([0:0.5:15 10:3:180]);
r = 1; % evaluate fields at radius r
disp( 'calculating 3D far field...' );
[E_far_theta,E_far_phi] = AnalyzeNF2FF( Sim_Path, nf2ff, f_res, thetaRange, phiRange, r );
E_far = sqrt( abs(E_far_theta).^2 + abs(E_far_phi).^2 );

E_far_normalized = E_far / max(E_far(:)) * Dmax;
[theta,phi] = ndgrid(thetaRange/180*pi,phiRange/180*pi);
x = E_far_normalized .* sin(theta) .* cos(phi);
y = E_far_normalized .* sin(theta) .* sin(phi);
z = E_far_normalized .* cos(theta);

%%
figure
surf( x,y,z, E_far_normalized );
axis equal
xlabel( 'x' );
ylabel( 'y' );
zlabel( 'z' );
toc

%% visualize magnetic fields
% you will find vtk dump files in the simulation folder (tmp/)
% use paraview to visulaize them
