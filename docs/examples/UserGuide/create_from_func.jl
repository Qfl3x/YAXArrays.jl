using YAXArrays, Zarr
using Dates

# Define function in space and time

f(lo, la, t) = (lo + la + Dates.dayofyear(t))

# ## Wrap function for mapCube output

function g(xout,lo,la,t)
    xout .= f.(lo,la,t)
end

# Note the applied `.` after `f`, this is because we will slice/broadcasted across time.

# ## Create Cube's Axes

# We wrap the dimensions of every axis into a YAXArray to use them in the mapCube function.
lon = YAXArray(Dim{:lon}(range(1, 15)))
lat = YAXArray(Dim{:lat}(range(1, 10)))
# And a time axis
tspan =  Date("2022-01-01"):Day(1):Date("2022-01-30")
time = YAXArray(Dim{:time}( tspan))


# ## Generate Cube from function
# The following generates a new `cube` using `mapCube` and saving the output directly to disk.

gen_cube = mapCube(g, (lon, lat, time);
    indims = (InDims(), InDims(), InDims("time")),
    outdims = OutDims("time", overwrite=true,
    path = "my_gen_cube.zarr", backend=:zarr, outtype=Float32),
    #max_cache=1e9
    )

# !!! warning "time axis is first"
#     Note that currently the `time` axis in the output cube goes first.

# Check that it is working

gen_cube.data[1,:,:]

# ## Generate Cube: change output order

# The following generates a new `cube` using `mapCube` and saving the output directly to disk.

gen_cube = mapCube(g, (lon, lat, time);
    indims = (InDims("lon"), InDims(), InDims()),
    outdims = OutDims("lon", overwrite=true,
    path = "my_gen_cube.zarr", backend=:zarr, outtype=Float32),
    #max_cache=1e9
    )

# !!! info "slicing dim"
#     Note that now the broadcasted dimension is `lon`.

gen_cube.data[:, :, 1]
