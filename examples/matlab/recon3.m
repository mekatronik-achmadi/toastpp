function recon3

disp('MATLAB-TOAST sample script:')
disp('2D image reconstruction using structural priors')
disp('-------------------------------------------------------')

% ======================================================================
% User-defined parameters
% ======================================================================
verbosity = 1;
meshdir = '../../test/2D/meshes/';       % example mesh repository
qmname  = [meshdir 'circle25_32x32.qm']; % source-detector definitions
fwdmesh = [meshdir 'ellips_tri10.msh'];  % mesh for data generation
invmesh = [meshdir 'circle25_32.msh'];   % mesh for inverse solver forward model

refind = 1.4;                           % refractive index

grd = [100 100];                        % solution basis: grid dimension
freq = 100;                             % modulation frequency [MHz]
noiselevel = 0.01;                      % additive data noise level
tau = 1e-3;                             % regularisation parameter
beta = 0.01;                            % TV regularisation parameter
tolGN = 1e-5;                           % Gauss-Newton convergence criterion
tolKrylov = 1e-2;                       % Krylov convergence criterion
itrmax = 100;                           % Gauss-Newton max. iterations
Himplicit = true;                       % Implicit/explicit Hessian matrix
cmap = 'gray';

% ======================================================================
% End user-defined parameters
% ======================================================================

% Initialisations
toastCatchErrors();                     % redirect toast library errors
toastSetVerbosity(verbosity);           % output verbosity level
c0 = 0.3;                               % lightspeed in vacuum [mm/ps]
cm = c0/refind;                         % lightspeed in medium

%% Generate target data

hmesh = toastReadMesh (fwdmesh);        % load FEM mesh from file
toastReadQM (hmesh, qmname);            % add source-detector descriptions
n = toastMeshNodeCount (hmesh);         % number of nodes
dmask = toastDataLinkList (hmesh);      % source-detector connectivity

mua = toastReadNIM([meshdir 'tgt_mua_ellips_tri10.nim']); % target absorption
mus = toastReadNIM([meshdir 'tgt_mus_ellips_tri10.nim']); % target scattering
ref = ones(n,1)*refind;   % target refractive index (homogeneous)

qvec = toastQvec (hmesh, 'Neumann', 'Gaussian', 2); % source specification
mvec = toastMvec (hmesh, 'Gaussian', 2);            % detector specification

smat = toastSysmat (hmesh, mua, mus, ref, freq);    % compute FEM system matrix
phi = full (smat\qvec);                             % solve linear FEM problem for photon density

lgamma = reshape (log(mvec.' * phi), [], 1);        % map to measurements
lgamma = lgamma(dmask);                             % remove unused source-detector combinations
mdata = real(lgamma);                               % log amplitude data
pdata = imag(lgamma);                               % phase data

% add some noise
mdata = mdata + mdata.*noiselevel.*randn(size(mdata));
pdata = pdata + pdata.*noiselevel.*randn(size(pdata));
data = [mdata;pdata];                               % linear data vector
m = length(data);                                   % number of measurement data

% display the target parameter distributions for comparison
muarng = [min(mua)*0.9, max(mua)*1.1];
musrng = [min(mus)*0.9, max(mus)*1.1];
hbasis = toastSetBasis(hmesh,grd);
muatgt = toastMapBasis (hbasis, 'M->B', mua);
mustgt = toastMapBasis (hbasis, 'M->B', mus);
muatgt_img = reshape (muatgt, grd);
mustgt_img = reshape (mustgt, grd);
mua_img = [muatgt_img, zeros(size(muatgt_img))];
mus_img = [mustgt_img, zeros(size(mustgt_img))];

hfig = figure;
set(hfig,'Position',[1 1, 800 400]);
subplot(2,2,1);
imagesc (mua_img, muarng);
colormap(cmap); colorbar; axis equal tight off
title ('\mu_a tgt, recon');
set(gca,'Position',[0.01 0.52 0.4 0.4]);
subplot(2,2,3);
imagesc (mus_img, musrng);
colormap(cmap); colorbar; axis equal tight off
title ('\mu_s tgt, recon');
set(gca,'Position',[0.01 0.05 0.4 0.4]);
drawnow

toastDeleteBasis(hbasis);                           % clean up basis mapper
toastDeleteMesh(hmesh);                             % clean up mesh


%% Inverse solver

% Read a TOAST mesh definition from file.
hmesh = toastReadMesh (invmesh);                    % read inverse solver mesh
toastReadQM (hmesh, qmname);                        % add source/detector descriptions
n = toastMeshNodeCount (hmesh);                     % number of nodes
dmask = toastDataLinkList (hmesh);                  % source-detector connectivity

% Set up homogeneous initial parameter estimates
mua = ones(n,1) * 0.025;                            % initial mua estimate
mus = ones(n,1) * 2;                                % initial mus estimate
ref = ones(n,1) * refind;                           % refractive index estimate
kap = 1./(3*(mua+mus));                             % diffusion coefficient

% Set up the mapper between FEM and solution bases
hbasis = toastSetBasis ('LINEAR', hmesh, grd);      % maps between mesh and reconstruction basis
solmask = toastSolutionMask (hbasis);               % mask unused voxels

% Generate source vectors
qvec = toastQvec (hmesh, 'Neumann', 'Gaussian', 2); % nodal source vectors

% Generate measurement vectors
mvec = toastMvec (hmesh, 'Gaussian', 2);            % nodal measurement vectors

% Initial data set f[x0]
smat = toastSysmat (hmesh, mua, mus, ref, freq);    % FEM system matrix
lgamma = reshape (log(mvec.' * (smat\qvec)), [], 1);% solve for photon density and map to boundary measurements
lgamma = lgamma(dmask);                             % remove unused source-detector combinations
mproj = real(lgamma);                               % log amplitude data
pproj = imag(lgamma);                               % phase data
proj = [mproj;pproj];                               % linear measurement vector

% data scaling
msd = ones(size(lgamma)) * norm(mdata-mproj);       % scale log amp data with data difference
psd = ones(size(lgamma)) * norm(pdata-pproj);       % scale phase data with data difference
sd = [msd;psd];                                     % linear scaling vector

% map initial parameter estimates to solution basis
bmua = toastMapMeshToBasis (hbasis, mua);           % mua mapped to full grid
bmus = toastMapMeshToBasis (hbasis, mus);           % mus mapped to full grid
bkap = toastMapMeshToBasis (hbasis, kap);           % kap mapped to full grid
bcmua = bmua*cm;                                    % scale parameters with speed of light
bckap = bkap*cm;                                    % scale parameters with speed of light
scmua = bcmua(solmask);                             % map to solution basis
sckap = bckap(solmask);                             % map to solution basis

% solution vector
x = [scmua;sckap];                                  % linea solution vector
logx = log(x);                                      % transform to log
p = length(x);                                      % solution vector dimension

% Initialise regularisation
% For simplicity, we use the target images for defining the edge priors
regul.method = 'TV';
regul.tau = tau;
regul.prior.smooth = 0.5;
regul.prior.threshold = 0.25;
regul.prior.refimg = [muatgt;mustgt];
regul.tv.beta = beta;
hreg = toastRegul (regul, hbasis, logx);

% initial data error (=2 due to data scaling)
err0 = privObjective (proj, data, sd, hreg, logx);  %initial error
err = err0;                                         % current error
errp = inf;                                         % previous error
erri(1) = err0;                                     % keep history
itr = 1;                                            % iteration counter
fprintf (1, '\n**** INITIAL ERROR %f\n\n', err);
step = 1.0;                                         % initial step length for line search

% Gauss-Newton loop
while (itr <= itrmax) && (err > tolGN*err0) && (errp-err > tolGN)

    errp = err;
    
    % Construct the Jacobian
    fprintf (1,'Calculating Jacobian\n');
    J = toastJacobian (hmesh, hbasis, qvec, mvec, mua, mus, ref, freq, 'direct');

    % data normalisation
    for i = 1:m
        J(i,:) = J(i,:) / sd(i);
    end

    % parameter normalisation (map to log)
    for i = 1:p
        J(:,i) = J(:,i) * x(i);
    end
    
    % Normalisation of Hessian (map to diagonal 1)
    psiHdiag = toastRegulHDiag (hreg, logx);
    M = zeros(p,1);
    for i = 1:p
        M(i) = sum(J(:,i) .* J(:,i));
        M(i) = M(i) + psiHdiag(i);
        M(i) = 1 ./ sqrt(M(i));
    end
    for i = 1:p
        J(:,i) = J(:,i) * M(i);
    end
    
    % Gradient of cost function
    r = J' * ((data-proj)./sd);
    r = r - toastRegulGradient (hreg, logx) .* M;
    
    if Himplicit == true
        % Update with implicit Krylov solver
        fprintf (1, 'Entering Krylov solver\n');
        dx = toastKrylov (x, J, r, M, 0, hreg, tolKrylov);
    else
        % Update with explicit Hessian
        H = J' * J;
        lambda = 0.01;
        H = H + eye(size(H)).* lambda;
        dx = H \ r;
        clear H;
    end
    
    clear J;
    
    % Line search
    fprintf (1, 'Entering line search\n');
    step0 = step;
    [step, err] = toastLineSearch (logx, dx, step0, err, @objective, 'verbose', verbosity>0);
    if errp-err <= tolGN
        dx = r; % try steepest descent
        step = toastLineSearch (logx, dx, step0, err, @objective, 'verbose', verbosity>0);
    end

    % Add update to solution
    logx = logx + dx*step;
    x = exp(logx);
    
    % Map parameters back to mesh
    scmua = x(1:size(x)/2);
    sckap = x(size(x)/2+1:size(x));
    smua = scmua/cm;
    skap = sckap/cm;
    smus = 1./(3*skap) - smua;
    mua = toastMapSolToMesh (hbasis, smua);
    mus = toastMapSolToMesh (hbasis, smus);
    bmua(solmask) = smua;
    bmus(solmask) = smus;

    % display the reconstructions
    subplot(2,2,1);
    muarec_img = reshape(bmua,grd);
    mua_img(:,size(muarec_img,2)+1:end) = muarec_img;
    imagesc(mua_img, muarng);
    colormap(cmap); colorbar; axis equal tight off
    title ('\mu_a tgt, recon');
    set(gca,'Position',[0.01 0.52 0.4 0.4]);
    subplot(2,2,3);
    musrec_img = reshape(bmus,grd);
    mus_img(:,size(musrec_img,2)+1:end) = musrec_img;
    imagesc(mus_img, musrng); 
    colormap(cmap); colorbar; axis equal tight off
    title ('\mu_s tgt, recon');
    set(gca,'Position',[0.01 0.05 0.4 0.4]);
    
    % update projection from current parameter estimate
    proj = toastProject (hmesh, mua, mus, ref, freq, qvec, mvec);

    % update objective function
    err = privObjective (proj, data, sd, hreg, logx);
    fprintf (1, '**** GN ITERATION %d, ERROR %f\n\n', itr, err);

    itr = itr+1;
    erri(itr) = err;
    
    % show objective function
    subplot(1,2,2);
    semilogy(erri);
    axis([1 itr 1e-2 2])
    xlabel('iteration');
    ylabel('objective function');
    drawnow
end

disp('recon3: finished')

    % =====================================================================
    % Callback function for objective evaluation (called by toastLineSearch)
    function p = objective(x)

    proj = privProject (hmesh, hbasis, x, ref, freq, qvec, mvec);
    [p, p_data, p_prior] = privObjective (proj, data, sd, hreg, x);
    if verbosity > 0
        fprintf (1, '    [LH: %f, PR: %f]\n', p_data, p_prior);
    end
    end

end