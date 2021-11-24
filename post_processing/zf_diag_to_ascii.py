from scipy.io import netcdf
import numpy as np

fpref='center'
basedir = '/work/e607/e607/dstonge/zf_test/test_proj/'
center_file = basedir +fpref + '.out.nc'


center_nc = netcdf.netcdf_file(center_file,'r')
zf_diag  = np.copy(center_nc.variables['zf_diag'][:])
zf_shape = np.shape(zf_diag)
nx   = zf_shape[1]
ncol = zf_shape[2]
print('#' + str(zf_shape))

t  = np.copy(center_nc.variables['t'][:])
nt = t.size

ind  = 1

zf_sum = np.zeros(zf_shape)
zf_sum[0,:,:] = zf_diag[0,:,:]

for i in range(nt):
  for j in range(zf_shape[2]):
      zf_sum[i,:,j] = zf_sum[i-1,:,j]+zf_diag[i,:,j]*(t[i]-t[i-1])

#what measurements are in zf_diag, along with the time
header = ['time',
          'prl_str',
          'prl_str_rad',
          'prl_str_rad_phi',
          'mirror',
          'mirror_rad',
          'mgn_drft',
          'mgn_drft_rad',
          'mgn_drft_rad_phi',
          'exb_nl',
          'zf_source',
          'zf_comm'
          ]

#print the header
#print('#')
print('#',end=' ')
for i in range(len(header)):
#    print('['+str(i+1) + ']'),
#    print(header[i]),
    print('['+str(i+1) + ']',end=' ')
    print(header[i],end=' ')
print('')

#print the data
for i in range(nt):
# print(t[i]),
  print(t[i],end=' ')
  for j in range(ncol):
#   print(zf_diag[i,ind,j]+zf_diag[i,nx-ind,j]),
    print(zf_diag[i,ind,j]+zf_diag[i,nx-ind,j],end=' ')
  for j in range(ncol):
#   print(zf_sum[i,ind,j]+zf_sum[i,nx-ind,j]),
    print(zf_sum[i,ind,j]+zf_sum[i,nx-ind,j],end=' ')
  print('')
