module fields_arrays

   use common_types, only: response_matrix_type, eigen_type

   implicit none

   complex, dimension(:, :, :, :), allocatable :: phi, apar, phi_old
   ! (naky, nakx, -nzgrid:nzgrid, ntubes)

   ! DSO 0 the following is a band-aid for radially global simulations until
   ! we more fully incorporate shared memory
   complex, dimension(:, :, :, :), pointer :: phi_shared
   ! (naky, nakx, -nzgrid:nzgrid, ntubes)

   ! radial corrections to phi and apar from quasineutrality/whatever controls apar
   complex, dimension(:, :, :, :), allocatable :: phi_corr_QN, apar_corr_QN
   ! (naky, nakx, -nzgrid:nzgrid, ntubes)

   ! needed to implement time-delayed source when using projection method
   complex, dimension(:, :, :), allocatable :: phi_proj, phi_proj_stage
   ! (nakx, -nzgrid:nzgrid, ntubes)

   ! radial corrections to phi and apar from gyroaveraging
   ! may result in tight space constraints however
   complex, dimension(:, :, :, :, :), allocatable :: phi_corr_GA, apar_corr_GA
   ! (naky, nakx, -nzgrid:nzgrid, ntubes, -vmu-layout-)

   type(response_matrix_type), dimension(:), allocatable :: response_matrix

   real, dimension(:), allocatable :: shift_state

   real, dimension(:, :, :), allocatable :: gamtot, dgamtotdr
   real, dimension(:, :), allocatable :: gamtot3, dgamtot3dr
   !real :: gamtot_h, gamtot3_h, efac, efacp

   complex, dimension(:, :, :), allocatable :: theta
   ! (nakx, nakx, -nzgrid:nzgrid)

   complex, dimension(:, :), allocatable :: c_mat
   ! (nakx, nakx)

   complex, dimension(:), pointer :: phi_ext => null()
   ! (nakx*nztot)

   type(eigen_type), dimension(:, :), allocatable :: phi_solve
   type(eigen_type) :: phizf_solve

   !variables needed for the source
   logical :: exclude_boundary_regions_qn
   real :: tcorr_source_qn, exp_fac_qn
   integer :: qn_window, qn_zf_window

end module fields_arrays
