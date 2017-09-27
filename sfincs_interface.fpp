module sfincs_interface

  implicit none
  
  public :: get_neo_from_sfincs

  private

  integer :: nproc_sfincs
  logical :: includeXDotTerm
  logical :: includeElectricFieldTermInXiDot
  integer :: magneticDriftScheme
  logical :: includePhi1
  logical :: includePhi1InKineticEquation
  integer :: geometryScheme
  integer :: coordinateSystem
  integer :: inputRadialCoordinate
  integer :: inputRadialCoordinateForGradients
  real :: aHat, psiAHat
  real :: nu_n
  integer :: nxi, nx

contains

  subroutine get_neo_from_sfincs (nradii, drho, f_neoclassical, phi_neoclassical)

# ifdef USE_SFINCS
    use geometry, only: geo_surf
    use mp, only: proc0, iproc
    use mp, only: comm_split, comm_free
    use sfincs_main, only: init_sfincs, prepare_sfincs, run_sfincs, finish_sfincs
# else
    use mp, only: mp_abort
# endif
    use zgrid, only: nzgrid
    use vpamu_grids, only: nvgrid
    
    implicit none

    integer, intent (in) :: nradii
    real, intent (in) :: drho
    real, dimension (-nzgrid:,-nvgrid:,:,:,-nradii/2:), intent (out) :: f_neoclassical
    real, dimension (-nzgrid:,-nradii/2:), intent (out) :: phi_neoclassical

# ifdef USE_SFINCS
    integer :: sfincs_comm
    integer :: color, ierr
    integer :: irad
    real :: rhoc_neighbor

    if (proc0) call read_sfincs_parameters
    call broadcast_sfincs_parameters
    if (iproc < nproc_sfincs) then
       color = 0
    else
       color = 1
    end if
    call comm_split (color, sfincs_comm, ierr)
    if (iproc < nproc_sfincs) then
       do irad = -nradii/2, nradii/2
          rhoc_neighbor = geo_surf%rhoc + irad*drho
          call init_sfincs (sfincs_comm)
          call pass_inputoptions_to_sfincs (irad*drho)
          call pass_outputoptions_to_sfincs
          call prepare_sfincs
          call pass_geometry_to_sfincs (irad*drho)
          call run_sfincs
          if (proc0) call get_sfincs_output &
               (f_neoclassical(:,:,:,:,irad), phi_neoclassical(:,irad))
          call broadcast_sfincs_output &
               (f_neoclassical(:,:,:,:,irad), phi_neoclassical(:,irad))
          call finish_sfincs
       end do
    end if
    call comm_free (sfincs_comm, ierr)
    ! NB: NEED TO BROADCAST SFINCS RESULTS
# else
    f_neoclassical = 0 ; phi_neoclassical = 0.
    call mp_abort ('to run with include_neoclassical_terms=.true., &
         & USE_SFINCS must be defined at compilation time.  Aborting.')
# endif

  end subroutine get_neo_from_sfincs

# ifdef USE_SFINCS
  subroutine read_sfincs_parameters

    use constants, only: pi
    use mp, only: nproc
    use file_utils, only: input_unit_exist
    use species, only: nspec, spec

    implicit none

    namelist /sfincs_input/ nproc_sfincs, &
         includeXDotTerm, &
         includeElectricFieldTermInXiDot, &
         magneticDriftScheme, &
         includePhi1, &
         includePhi1InKineticEquation, &
         geometryScheme, &
         coordinateSystem, &
         inputRadialCoordinate, &
         inputRadialCoordinateForGradients, &
         aHat, psiAHat, nu_N, nxi, nx

    logical :: exist
    integer :: in_file

    nproc_sfincs = 1
    includeXDotTerm = .false.
    includeElectricFieldTermInXiDot = .false.
    magneticDriftScheme = 0
    includePhi1 = .true.
    includePhi1InKineticEquation = .false.
    geometryScheme = 1
    coordinateSystem = 3
    ! option 3 corresponds to using sqrt of toroidal flux
    ! normalized by toroidal flux enclosed by the LCFS
    inputRadialCoordinate = 3
    ! option 3 corresponds to same choice
    ! when calculating gradients of density, temperature, and potential
    inputRadialCoordinateForGradients = 3
    ! corresponds to r_LCFS as reference length in sfincs
    aHat = 1.0
    ! corresponds to psitor_LCFS = B_ref * a_ref^2
    psiAHat = 1.0
    ! nu_n = nu_ref * aref/vt_ref
    ! nu_ref = 4*sqrt(2*pi)*nref*e**4*loglam/(3*sqrt(mref)*Tref**3/2)
    ! (with nref, Tref, and mref in Gaussian units)
    nu_N = spec(1)%vnew_ref*(4./(3.*pi))
    ! number of spectral coefficients in pitch angle
    nxi = 64
    ! number of speeds
    nx = 16

    in_file = input_unit_exist("sfincs_input", exist)
    if (exist) read (unit=in_file, nml=sfincs_input)

    if (nproc_sfincs > nproc) then
       write (*,*) 'requested number of processors for sfincs is greater &
            & than total processor count.'
       write (*,*) 'allocating ', nproc, ' processors for sfincs.'
    end if

    if (nspec == 1 .and. includePhi1) then
       write (*,*) 'includePhi1 = .true. is incompatible with a single-species run.'
       write (*,*) 'forcing includePhi1 = .false.'
       includePhi1 = .false.
    end if

  end subroutine read_sfincs_parameters

  subroutine broadcast_sfincs_parameters

    use mp, only: broadcast

    implicit none

    call broadcast (nproc_sfincs)
    call broadcast (includeXDotTerm)
    call broadcast (includeElectricFieldTermInXiDot)
    call broadcast (magneticDriftScheme)
    call broadcast (includePhi1)
    call broadcast (includePhi1InKineticEquation)
    call broadcast (geometryScheme)
    call broadcast (coordinateSystem)
    call broadcast (inputRadialCoordinate)
    call broadcast (inputRadialCoordinateForGradients)
    call broadcast (aHat)
    call broadcast (psiAHat)
    call broadcast (nu_N)
    call broadcast (nxi)
    call broadcast (nx)

  end subroutine broadcast_sfincs_parameters

  subroutine pass_inputoptions_to_sfincs (delrho)

    use mp, only: mp_abort
    use geometry, only: geo_surf
    use species, only: spec, nspec
    use zgrid, only: nzgrid
    use globalVariables, only: includeXDotTerm_sfincs => includeXDotTerm
    use globalVariables, only: includeElectricFieldTermInXiDot_sfincs => includeElectricFieldTermInXiDot
    use globalVariables, only: magneticDriftScheme_sfincs => magneticDriftScheme
    use globalVariables, only: includePhi1_sfincs => includePhi1
    use globalVariables, only: includePhi1InKineticEquation_sfincs => includePhi1InKineticEquation
    use globalVariables, only: geometryScheme_sfincs => geometryScheme
    use globalVariables, only: coordinateSystem_sfincs => coordinateSystem
    use globalVariables, only: RadialCoordinate => inputRadialCoordinate
    use globalVariables, only: RadialCoordinateForGradients => inputRadialCoordinateForGradients
    use globalVariables, only: rN_wish
    use globalVariables, only: Nspecies, nHats, THats, MHats, Zs
    use globalVariables, only: Nzeta, Ntheta
    use globalVariables, only: nxi_sfincs => Nxi
    use globalVariables, only: nx_sfincs => Nx
    use globalVariables, only: dnHatdrNs, dTHatdrNs, dPhiHatdrN
    use globalVariables, only: aHat_sfincs => aHat
    use globalVariables, only: psiAHat_sfincs => psiAHat
    use globalVariables, only: nu_n_sfincs => nu_n

    implicit none

    real, intent (in) :: delrho

    includeXDotTerm_sfincs = includeXDotTerm
    includeElectricFieldTermInXiDot_sfincs = includeElectricFieldTermInXiDot
    magneticDriftScheme_sfincs = magneticDriftScheme
    includePhi1_sfincs = includePhi1
    includePhi1InKineticEquation_sfincs = includePhi1InKineticEquation
    geometryScheme_sfincs = geometryScheme
    coordinateSystem_sfincs = coordinateSystem
    RadialCoordinate = inputRadialCoordinate
    RadialCoordinateForGradients = inputRadialCoordinateForGradients
    Nspecies = nspec
    nHats(:nspec) = spec%dens*(1.0-delrho*spec%fprim)
    THats(:nspec) = spec%temp*(1.0-delrho*spec%tprim)
    mHats(:nspec) = spec%mass
    Zs(:nspec) = spec%z
!     ! FLAG -- need to modify for stellarator simulations
!     ! I think nzeta will be 2*nzgrid+1
!     ! and ntheta will be ny_ffs
    Nzeta = 1
    Ntheta = 2*nzgrid+1
    nx_sfincs = nx
    nxi_sfincs = nxi
    aHat_sfincs = aHat
    psiAHat_sfincs = psiAHat
    nu_n_sfincs = nu_n

    if (inputRadialCoordinate == 3) then
       rN_wish = geo_surf%rhotor + delrho*geo_surf%drhotordrho
    else
       call mp_abort ('only inputRadialCoordinate=3 currently supported. aborting.')
    end if
    if (inputRadialCoordinateForGradients == 3) then
       ! radial density gradient with respect to rhotor = sqrt(psitor/psitor_LCFS)
       ! normalized by reference density (not species density)
       dnHatdrNs(:nspec) = -spec%dens/geo_surf%drhotordrho*(spec%fprim - delrho*spec%d2ndr2)
       ! radial temperature gradient with respect to rhotor = sqrt(psitor/psitor_LCFS)
       ! normalized by reference tmperatures (not species temperature)
       dTHatdrNs(:nspec) = -spec%temp/geo_surf%drhotordrho*(spec%tprim - delrho*spec%d2Tdr2)
       ! radial electric field
       dPhiHatdrN = 0.0
    else
       call mp_abort ('only inputRadialCoordinateForGradients=3 currently supported. aborting.')
    end if

  end subroutine pass_inputoptions_to_sfincs

  subroutine pass_outputoptions_to_sfincs
    use export_f, only: export_f_theta_option
    use export_f, only: export_f_zeta_option
    use export_f, only: export_f_xi_option
    use export_f, only: export_f_x_option
    use export_f, only: export_delta_f
    implicit none
    export_f_theta_option = 0
    export_f_zeta_option = 0
    export_f_xi_option = 0
    export_f_x_option = 0
    export_delta_f = .true.
  end subroutine pass_outputoptions_to_sfincs

  subroutine pass_geometry_to_sfincs (delrho)

    use zgrid, only: nzgrid
    use geometry, only: bmag, dbdthet, gradpar
    use geometry, only: dBdrho, d2Bdrdth, dgradpardrho, dIdrho
    use geometry, only: geo_surf
    use globalVariables, only: BHat
    use globalVariables, only: dBHatdtheta
    use globalVariables, only: iota
    use globalVariables, only: DHat
    use globalVariables, only: BHat_sup_theta
    use globalVariables, only: BHat_sub_zeta

    implicit none

    real, intent (in) :: delrho

    integer :: nzeta = 1
    real :: q_local
    real, dimension (-nzgrid:nzgrid) :: B_local, dBdth_local, gradpar_local

    call init_zero_arrays

    q_local = geo_surf%qinp*(1.0+delrho*geo_surf%shat/geo_surf%rhoc)
    B_local = bmag + delrho*dBdrho
    dBdth_local = dbdthet + delrho*d2Bdrdth
    gradpar_local = gradpar + delrho*dgradpardrho

    ! FLAG -- needs to be changed for stellarator runs
    BHat = spread(B_local,2,nzeta)
    dBHatdtheta = spread(dBdth_local,2,nzeta)
    iota = 1./q_local
    ! this is grad psitor . (grad theta x grad zeta)
    ! note that + sign below relies on B = I grad zeta + grad zeta x grad psi
    DHat = q_local*spread(B_local*gradpar_local,2,nzeta)
    ! this is bhat . grad theta
    BHat_sup_theta = spread(B_local*gradpar_local,2,nzeta)
    ! this is I(psi) / (aref*Bref)
    BHat_sub_zeta = geo_surf%rgeo + delrho*dIdrho

  end subroutine pass_geometry_to_sfincs

  subroutine init_zero_arrays
    use globalVariables, only: dBHatdzeta
    use globalVariables, only: dBHatdpsiHat
    use globalVariables, only: BHat_sup_zeta
    use globalVariables, only: BHat_sub_psi
    use globalVariables, only: BHat_sub_theta
    use globalVariables, only: dBHat_sub_psi_dtheta
    use globalVariables, only: dBHat_sub_psi_dzeta
    use globalVariables, only: dBHat_sub_theta_dpsiHat
    use globalVariables, only: dBHat_sub_theta_dzeta
    use globalVariables, only: dBHat_sub_zeta_dpsiHat
    use globalVariables, only: dBHat_sub_zeta_dtheta
    use globalVariables, only: dBHat_sup_theta_dpsiHat
    use globalVariables, only: dBHat_sup_theta_dzeta
    use globalVariables, only: dBHat_sup_zeta_dpsiHat
    use globalVariables, only: dBHat_sup_zeta_dtheta
    implicit none
    dBHatdzeta = 0.
    dBHatdpsiHat = 0.
    BHat_sup_zeta = 0.
    BHat_sub_psi = 0.
    BHat_sub_theta = 0.
    dBHat_sub_psi_dtheta = 0.
    dBHat_sub_psi_dzeta = 0.
    dBHat_sub_theta_dpsiHat = 0.
    dBHat_sub_theta_dzeta = 0.
    dBHat_sub_zeta_dpsiHat = 0.
    dBHat_sub_zeta_dtheta = 0.
    dBHat_sup_theta_dpsiHat = 0.
    dBHat_sup_theta_dzeta = 0.
    dBHat_sup_zeta_dpsiHat = 0.
    dBHat_sup_zeta_dtheta = 0.
  end subroutine init_zero_arrays

  subroutine get_sfincs_output (f_neoclassical, phi_neoclassical)

    use species, only: nspec, spec
    use zgrid, only: nzgrid
    use vpamu_grids, only: nvgrid, nmu
    use vpamu_grids, only: energy, vpa, maxwellian
    use export_f, only: h_sfincs => delta_f
    use globalVariables, only: nxi_sfincs => nxi
    use globalVariables, only: nx_sfincs => nx
    use globalVariables, only: x_sfincs => x
    use globalVariables, only: phi_sfincs => Phi1Hat
!    use globalVariables, only: ddx_sfincs => ddx
    use xGrid, only: xGrid_k

    implicit none

    real, dimension (-nzgrid:,-nvgrid:,:,:), intent (out) :: f_neoclassical
    real, dimension (-nzgrid:), intent (out) :: phi_neoclassical

    integer :: iz, iv, imu, is, ixi!, ix

    integer :: nxi_stella
    real, dimension (1) :: x_stella
    integer, dimension (2) :: sgnvpa
    real, dimension (:), allocatable :: xi_stella, hstella!, dhstella_dx
    real, dimension (:), allocatable :: htmp, dhtmp_dx
!    real, dimension (:), allocatable :: ddx_stella
    real, dimension (:,:), allocatable :: xsfincs_to_xstella, legpoly
    real, dimension (:,:), allocatable :: hsfincs

    allocate (htmp(nxi_sfincs))
    allocate (dhtmp_dx(nxi_sfincs))
    allocate (hsfincs(nxi_sfincs,nx_sfincs))
    allocate (xsfincs_to_xstella(1,nx_sfincs))
!    allocate (ddx_stella(nx_sfincs))

    phi_neoclassical = phi_sfincs(:,1)

    sgnvpa(1) = 1 ; sgnvpa(2) = -1
    do is = 1, nspec
       do iz = -nzgrid, nzgrid
          ! hsfincs is on the sfincs energy grid
          ! but is spectral in pitch-angle
          hsfincs = h_sfincs(is,iz+nzgrid+1,1,:,:)

          do imu = 1, nmu
             do iv = 0, nvgrid
                ! x_stella is the speed 
                ! corresponding to this (vpa,mu) grid point
                x_stella = sqrt(energy(iz,iv,imu))
                ! note that with exception of vpa=0
                ! can use symmetry of vpa grid to see that
                ! each speed arc has two pitch angles on it
                ! correspondong to +/- vpa
                if (iv == 0) then
                   nxi_stella = 1
                else
                   nxi_stella = 2
                end if
                allocate (xi_stella(nxi_stella))
                allocate (hstella(nxi_stella))
!                allocate (dhstella_dx(nxi_stella))
                allocate (legpoly(nxi_stella,0:nxi_sfincs-1))
                ! xi_stella is the pitch angle (vpa/v)
                ! corresponding to this (vpa,mu) grid point
                xi_stella = sgnvpa(:nxi_stella)*vpa(iv)/x_stella(1)

                ! set up matrix that interpolates from sfincs speed grid
                ! to the speed corresponding to this (vpa,mu) grid point
                call polynomialInterpolationMatrix (nx_sfincs, 1, &
                     x_sfincs, x_stella, exp(-x_sfincs*x_sfincs)*(x_sfincs**xGrid_k), &
                     exp(-x_stella*x_stella)*(x_stella**xGrid_k), xsfincs_to_xstella)
                
                ! do the interpolation
                do ixi = 1, nxi_sfincs
                   htmp(ixi) = sum(hsfincs(ixi,:)*xsfincs_to_xstella(1,:))
                end do

!                 ! get matrix that multiplies hsfincs to get dhsfincs/dx
!                 ! and multiply by interpolation matrix
!                 do ix = 1, nx_sfincs
!                    ddx_stella(ix) = sum(xsfincs_to_xstella(1,:)*ddx_sfincs(:,ix))
!                 end do
!                 ! get x derivative of hsfincs at requested stella speed grid point
!                 do ixi = 1, nxi_sfincs
!                    dhtmp_dx(ixi) = sum(hsfincs(ixi,:)*ddx_stella)
!                 end do

                ! next need to Legendre transform in pitch-angle
                ! first evaluate Legendre polynomials at requested pitch angles
                call legendre (xi_stella, legpoly)

                ! then do the transforms
                call legendre_transform (legpoly, htmp, hstella)
!                call legendre_transform (legpoly, dhtmpdx, dhstella_dx)

                f_neoclassical(iz,iv,imu,is) = hstella(1)
!                dfneo_dx(iz,iv,imu,is) = dhstella_dx(1)
                if (iv > 0) then
                   f_neoclassical(iz,-iv,imu,is) = hstella(2)
!                   dfneo_dx(iz,-iv,imu,is) = dhstella_dx(2)
                end if

                ! FLAG -- I think phi_sfincs is e phi / Tref.  need to ask Matt
                ! if correct, need to multiply by Z_s * Tref/T_s * F_{0,s}
                ! NB: f_neoclassical has not been scaled up by 1/rho*
                f_neoclassical(iz,iv,imu,is) = f_neoclassical(iz,iv,imu,is) &
                     - phi_neoclassical(iz)*spec(is)%z/spec(is)%temp*maxwellian(iv)

!                deallocate (xi_stella, hstella, dhstella_dx, legpoly)
                deallocate (xi_stella, hstella, legpoly)
             end do
          end do
       end do
    end do

    deallocate (htmp, dhtmp_dx)
    deallocate (hsfincs)
    deallocate (xsfincs_to_xstella)
!    deallocate (ddx_stella)

  end subroutine get_sfincs_output

  ! returns the Legendre polynomials (legp)
  ! on requested grid (x)
  subroutine legendre (x, legp)
    
    implicit none
    
    real, dimension (:), intent (in) :: x
    real, dimension (:,0:), intent (out) :: legp
    
    integer :: n, idx
    
    n = size(legp,2)-1
    
    legp(:,0) = 1.0
    legp(:,1) = x
    
    do idx = 2, n
       legp(:,idx) = ((2.*idx-1.)*x*legp(:,idx-1) + (1.-idx)*legp(:,idx-2))/idx
    end do
    
  end subroutine legendre
  
  subroutine legendre_transform (legp, coefs, func)

    implicit none
    
    real, dimension (:,0:), intent (in) :: legp
    real, dimension (:), intent (in) :: coefs
    real, dimension (:), intent (out) :: func
    
    integer :: i

    func = 0.
    do i = 1, size(coefs)
       func = func + legp(:,i-1)*coefs(i)
    end do

  end subroutine legendre_transform

  subroutine broadcast_sfincs_output (fneo, phineo)
    use mp, only: broadcast
    use zgrid, only: nzgrid
    use vpamu_grids, only: nvgrid
    implicit none
    real, dimension (-nzgrid:,-nvgrid:,:,:), intent (in out) :: fneo
    real, dimension (-nzgrid:), intent (in out) :: phineo
    call broadcast (fneo)
    call broadcast (phineo)
  end subroutine broadcast_sfincs_output

# endif

end module sfincs_interface