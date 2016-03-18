module CubeAPI
export Cube, getCubeData,getTimeRanges,CubeMem,CubeAxis, TimeAxis, VariableAxis, LonAxis, LatAxis, CountryAxis, SpatialPointAxis, SubCube, axes, AbstractCubeData
export VALID, OCEAN, OUTOFPERIOD, MISSING, FILLED, isvalid, isinvalid, isvalid, isvalidorfilled

include("Axes.jl")
include("Mask.jl")

importall .Axes, .Mask
using DataStructures
using Base.Dates

type ConfigEntry{LHS}
    lhs
    rhs
end



"
 A data cube's static configuration information.

 - `spatial_res`: The spatial image resolution in degree.
 - `grid_x0`: The fixed grid X offset (longitude direction).
 - `grid_y0`: The fixed grid Y offset (latitude direction).
 - `grid_width`: The fixed grid width in pixels (longitude direction).
 - `grid_height`: The fixed grid height in pixels (latitude direction).
 - `temporal_res`: The temporal resolution in days.
 - `ref_time`: A datetime value which defines the units in which time values are given, namely days since *ref_time*.
 - `start_time`: The start time of the first image of any variable in the cube given as datetime value.
                    ``None`` means unlimited.
 - `end_time`: The end time of the last image of any variable in the cube given as datetime value.
                  ``None`` means unlimited.
 - `variables`: A list of variable names to be included in the cube.
 - `file_format`: The file format used. Must be one of 'NETCDF4', 'NETCDF4_CLASSIC', 'NETCDF3_CLASSIC'
                     or 'NETCDF3_64BIT'.
 - `compression`: Whether the data should be compressed.
 "
type CubeConfig
    end_time::DateTime
    ref_time::DateTime
    start_time::DateTime
    grid_width::Int
    variables::Any
    temporal_res::Int
    grid_height::Int
    calendar::UTF8String
    file_format::UTF8String
    spatial_res::Float64
    model_version::UTF8String
    grid_y0::Int
    compression::Bool
    grid_x0::Int
end
t0=DateTime(0)
CubeConfig()=CubeConfig(t0,t0,t0,0,0,0,0,"","",0.0,"",0,false,0)

parseEntry(d,e::ConfigEntry)=setfield!(d,Symbol(e.lhs),parse(e.rhs))
parseEntry(d,e::ConfigEntry{:compression})=setfield!(d,Symbol(e.lhs),e.rhs=="False" ? false : true)
parseEntry(d,e::Union{ConfigEntry{:model_version},ConfigEntry{:file_format},ConfigEntry{:calendar}})=setfield!(d,Symbol(e.lhs),utf8(strip(e.rhs,'\'')))
function parseEntry(d,e::Union{ConfigEntry{:ref_time},ConfigEntry{:start_time},ConfigEntry{:end_time}})
    m=match(r"datetime.datetime\(\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\)",e.rhs).captures
    setfield!(d,Symbol(e.lhs),DateTime(parse(Int,m[1]),parse(Int,m[2]),parse(Int,m[3]),parse(Int,m[4]),parse(Int,m[5])))
end

function parseConfig(cubepath)
  configfile=joinpath(cubepath,"cube.config")
  x=split(readchomp(configfile),"\n")
  d=CubeConfig()
  for ix in x
    s1,s2=split(ix,'=')
    s1=strip(s1);s2=strip(s2)
    e=ConfigEntry{symbol(s1)}(s1,s2)
    parseEntry(d,e)
  end
  d
end

abstract AbstractCubeData{T}

"
Represents a data cube. The default constructor is

    Cube(base_dir)

where `base_dir` is the datacube's base directory.
"
type Cube
    base_dir::UTF8String
    config::CubeConfig
    dataset_files::Vector{UTF8String}
    var_name_to_var_index::OrderedDict{UTF8String,Int}
    firstYearOffset::Int
end
function Cube(base_dir::AbstractString)
  cubeconfig=parseConfig(base_dir)
  data_dir=joinpath(base_dir,"data")
  data_dir_entries=readdir(data_dir)
  sort!(data_dir_entries)
  var_name_to_var_index=OrderedDict{UTF8String,Int}()
  for i=1:length(data_dir_entries) var_name_to_var_index[data_dir_entries[i]]=i end
  firstYearOffset=div(dayofyear(cubeconfig.start_time)-1,cubeconfig.temporal_res)
  Cube(base_dir,cubeconfig,data_dir_entries,var_name_to_var_index,firstYearOffset)
end

"A SubCube is a representation of a certain region or time range returned by the getCube function."
immutable SubCube{T} <: AbstractCubeData{T}
  cube::Cube #Parent cube
  variable::UTF8String #Variable
  sub_grid::Tuple{Int,Int,Int,Int} #grid_y1,grid_y2,grid_x1,grid_x2
  sub_times::NTuple{6,Int} #y1,i1,y2,i2,ntime,NpY
  lonAxis::LonAxis
  latAxis::LatAxis
  timeAxis::TimeAxis
end
axes(s::SubCube)=CubeAxis[s.lonAxis,s.latAxis,s.timeAxis]

Base.eltype{T}(s::SubCube{T})=T
Base.ndims(s::SubCube)=3
Base.size(s::SubCube)=(length(s.lonAxis),length(s.latAxis),length(s.timeAxis))

"A SubCube containing several variables"
immutable SubCubeV{T} <: AbstractCubeData{T}
    cube::Cube #Parent cube
    variable::Vector{UTF8String} #Variable
    sub_grid::Tuple{Int,Int,Int,Int} #grid_y1,grid_y2,grid_x1,grid_x2
    sub_times::NTuple{6,Int} #y1,i1,y2,i2,ntime,NpY
    lonAxis::LonAxis
    latAxis::LatAxis
    timeAxis::TimeAxis
    varAxis::VariableAxis
end
axes(s::SubCubeV)=CubeAxis[s.lonAxis,s.latAxis,s.timeAxis,s.varAxis]
Base.eltype{T}(s::SubCubeV{T})=T
Base.ndims(s::SubCubeV)=4
Base.size(s::SubCubeV)=(length(s.lonAxis),length(s.latAxis),length(s.timeAxis),length(s.varAxis))

type CubeMem{T,N} <: AbstractCubeData
  axes::Vector{CubeAxis}
  data::Array{T,N}
  mask::Array{UInt8,N}
end
axes(c::CubeMem)=c.axes

Base.linearindexing(::CubeMem)=Base.LinearFast()
Base.getindex(c::CubeMem,i::Integer)=getindex(c.data,i)
Base.setindex!(c::CubeMem,i::Integer,v)=setindex!(c.data,i,v)
Base.size(c::CubeMem)=size(c.data)
Base.similar(c::CubeMem)=cubeMem(c.axes,similar(c.data),copy(c.mask))



"""

    getCubeData(cube::Cube;variable,time,latitude,longitude)

The following keyword arguments are accepted:

- *variable*: an variable index or name or an iterable returning multiple of these (var1, var2, ...)
- *time*: a single datetime.datetime object or a 2-element iterable (time_start, time_end)
- *latitude*: a single latitude value or a 2-element iterable (latitude_start, latitude_end)
- *longitude*: a single longitude value or a 2-element iterable (longitude_start, longitude_end)

Returns a dictionary mapping variable names --> arrays of dimension (longitude, latitude, time)

http://earthsystemdatacube.org
"""
function getCubeData(cube::Cube;variable=Int[],time=[],latitude=[],longitude=[])
    #First fill empty inputs
    isempty(variable) && (variable = defaultvariable(cube))
    isempty(time)     && (time     = defaulttime(cube))
    isempty(latitude) && (latitude = defaultlatitude(cube))
    isempty(longitude)&& (longitude= defaultlongitude(cube))
    getCubeData(cube,variable,time,latitude,longitude)
end

defaulttime(cube::Cube)=cube.config.start_time,cube.config.end_time-Day(1)
defaultvariable(cube::Cube)=cube.dataset_files
defaultlatitude(cube::Cube)=(-90.0,90.0)
defaultlongitude(cube::Cube)=(-180.0,180.0)

using NetCDF
vartype{T,N}(v::NcVar{T,N})=T
"Function to get the years and times to read from user input."
function getTimesToRead(time1,time2,config)
    NpY    = ceil(Int,365/config.temporal_res)
    y1     = year(time1)
    y2     = year(time2)
    d1     = dayofyear(time1)
    index1 = round(Int,d1/config.temporal_res)+1
    d2     = dayofyear(time2)
    index2 = min(round(Int,d2/config.temporal_res)+1,NpY)
    ntimesteps = -index1 + index2 + (y2-y1)*NpY + 1
    return y1,index1,y2,index2,ntimesteps,NpY
end

"Returns a vector of DateTime objects giving the time indices returned by a respective call to getCubeData."
function getTimeRanges(c::Cube,y1,y2,i1,i2)
    NpY    = ceil(Int,365/c.config.temporal_res)
    yrange = y1:y2
    a=DateTime[]
    i=i1
    for y=y1:y2
      lasti= y==y2 ? i2 : NpY
      while (i<=lasti)
        push!(a,DateTime(y)+Dates.Day((i-1)*c.config.temporal_res))
        i=i+1
      end
      i=1
    end
    a
end

#Convert single input to vectors
function getCubeData{T<:Union{Integer,AbstractString}}(cube::Cube,
                variable::Union{AbstractString,Integer,AbstractVector{T}},
                time::Union{Tuple{TimeType,TimeType},TimeType},
                latitude::Union{Tuple{Real,Real},Real},
                longitude::Union{Tuple{Real,Real},Real})

  isa(time,TimeType) && (time=(time,time))
  isa(latitude,Real) && (latitude=(latitude,latitude))
  isa(longitude,Real) && (longitude=(longitude,longitude))
  isa(variable,AbstractVector) && isa(eltype(variable),Integer) && (variable=[cube.config.dataset_files[i] for i in variable])
  isa(variable,Integer) && (variable=dataset_files[i])
  getCubeData(cube,variable,time,longitude,latitude)
end



function getLonLatsToRead(config,longitude,latitude)
  grid_y1 = round(Int,(90.0 - latitude[2]) / config.spatial_res) - config.grid_y0 + 1
  grid_y2 = round(Int,(90.0 - latitude[1]) / config.spatial_res) - config.grid_y0
  grid_x1 = round(Int,(180.0 + longitude[1]) / config.spatial_res) - config.grid_x0 + 1
  grid_x2 = round(Int,(180.0 + longitude[2]) / config.spatial_res) - config.grid_x0
  grid_y1,grid_y2,grid_x1,grid_x2
end

function getLandSeaMask!(mask::Array{UInt8,3},cube::Cube,grid_x1,grid_x2,grid_y1,grid_y2)
  filename=joinpath(cube.base_dir,"mask","mask.nc")
  if isfile(filename)
      ncread!(filename,"mask",sub(mask,:,:,1),start=[grid_x1,grid_y1],count=[grid_x2-grid_x1+1,grid_y2-grid_y1+1])
      nT=size(mask,3)
      for itime=2:nT,ilat=1:size(mask,2),ilon=1:size(mask,1)
          mask[ilon,ilat,itime]=mask[ilon,ilat,1]
      end
  end
end

function getLandSeaMask!(mask::Array{UInt8,4},cube::Cube,grid_x1,grid_x2,grid_y1,grid_y2)
  filename=joinpath(cube.base_dir,"mask","mask.nc")
  if isfile(filename)
      ncread!(filename,"mask",sub(mask,:,:,1,1),start=[grid_x1,grid_y1],count=[grid_x2-grid_x1+1,grid_y2-grid_y1+1])
      nT=size(mask,3)
      for ivar=1:size(mask,4),itime=2:nT,ilat=1:size(mask,2),ilon=1:size(mask,1)
          mask[ilon,ilat,itime,ivar]=mask[ilon,ilat,1,1]
      end
  end
end

function getCubeData(cube::Cube,
                variable::AbstractString,
                time::Tuple{TimeType,TimeType},
                latitude::Tuple{Real,Real},
                longitude::Tuple{Real,Real})
    # This function is doing the actual reading
    config=cube.config

    grid_y1,grid_y2,grid_x1,grid_x2 = getLonLatsToRead(config,longitude,latitude)
    y1,i1,y2,i2,ntime,NpY = getTimesToRead(time[1],time[2],config)

    datafiles=sort!(readdir(joinpath(cube.base_dir,"data",variable)))
    #yfirst=parse(Int,datafiles[1][1:4])

    t=vartype(NetCDF.open(joinpath(cube.base_dir,"data",variable,datafiles[1]),variable))

    return SubCube{t}(cube,variable,
      (grid_y1,grid_y2,grid_x1,grid_x2),
      (y1,i1,y2,i2,ntime,NpY),
      LonAxis(longitude[1]:0.25:(longitude[2]-0.25)),
      LatAxis(latitude[1]:0.25:(latitude[2]-0.25)),
      TimeAxis(getTimeRanges(cube,y1,y2,i1,i2)))
end

"Construct a subcube with many variables"
function getCubeData{T<:AbstractString}(cube::Cube,
                variable::Vector{T},
                time::Tuple{TimeType,TimeType},
                latitude::Tuple{Real,Real},
                longitude::Tuple{Real,Real})

config=cube.config

grid_y1,grid_y2,grid_x1,grid_x2 = getLonLatsToRead(config,longitude,latitude)
y1,i1,y2,i2,ntime,NpY = getTimesToRead(time[1],time[2],config)
  variableNew=UTF8String[]
  varTypes=DataType[]
  for i=1:length(variable)
    if haskey(cube.var_name_to_var_index,variable[i])
        datafiles=sort!(readdir(joinpath(cube.base_dir,"data",variable[i])))
        #yfirst=parse(Int,datafiles[1][1:4])
        t=vartype(NetCDF.open(joinpath(cube.base_dir,"data",variable[i],datafiles[1]),variable[i]))
        push!(variableNew,variable[i])
        push!(varTypes,t)
    else
      warn("Skipping variable $(variable[i]), not found in Datacube")
    end
  end
  tnew=reduce(promote_type,varTypes[1],varTypes)
  return SubCubeV{tnew}(cube,variable,
    (grid_y1,grid_y2,grid_x1,grid_x2),
    (y1,i1,y2,i2,ntime,NpY),
    LonAxis(longitude[1]:0.25:(longitude[2]-0.25)),
    LatAxis(latitude[1]:0.25:(latitude[2]-0.25)),
    TimeAxis(getTimeRanges(cube,y1,y2,i1,i2)),
    VariableAxis(variableNew))
end

function read{T}(s::SubCube{T})
    grid_y1,grid_y2,grid_x1,grid_x2 = s.sub_grid
    y1,i1,y2,i2,ntime,NpY           = s.sub_times
    outar=Array(T,grid_x2-grid_x1+1,grid_y2-grid_y1+1,ntime)
    mask=zeros(UInt8,grid_x2-grid_x1+1,grid_y2-grid_y1+1,ntime)
    _read(s,outar,mask)
    return CubeMem(CubeAxis[s.lonAxis,s.latAxis,s.timeAxis],outar,mask)
end

function _read{T}(s::AbstractCubeData{T},outar,mask;xoffs::Int=0,yoffs::Int=0,toffs::Int=0,voffs::Int=0,nx::Int=size(outar,1),ny::Int=size(outar,2),nt::Int=size(outar,3),nv::Int=length(s.variable))

    grid_y1,grid_y2,grid_x1,grid_x2 = s.sub_grid
    y1,i1,y2,i2,ntime,NpY           = s.sub_times

    grid_x1 = grid_x1 + xoffs
    grid_x2 = grid_x1 + nx - 1
    grid_y1 = grid_y1 + yoffs
    grid_y2 = grid_y1 + ny - 1
    if toffs > 0
        i1 = i1 + toffs
        if i1 > NpY
            y1 = y1 + div(i1-1,NpY)
            i1 = mod(i1-1,NpY)+1
        end
    end

    #println("Year 1=",y1)
    #println("i1    =",i1)
    #println("grid_x=",grid_x1:grid_x2)
    #println("grid_y=",grid_y1:grid_y2)

    fill!(mask,zero(UInt8))
    getLandSeaMask!(mask,s.cube,grid_x1,grid_x2,grid_y1,grid_y2)

    readAllyears(s,outar,mask,y1,i1,grid_x1,nx,grid_y1,ny,nt,voffs,nv,NpY)
    ncclose()
end

function readAllyears(s::SubCube,outar,mask,y1,i1,grid_x1,nx,grid_y1,ny,nt,voffs,nv,NpY)
  ycur=y1   #Current year to read
  i1cur=i1  #Current time step in year
  itcur=1   #Current time step in output file
  fin = false
  while !fin
    fin,ycur,i1cur,itcur = readFromDataYear(s.cube,outar,mask,s.variable,ycur,grid_x1,nx,grid_y1,ny,itcur,i1cur,nt,NpY)
  end
  ncclose()
end

function readAllyears(s::SubCubeV,outar,mask,y1,i1,grid_x1,nx,grid_y1,ny,nt,voffs,nv,NpY)
    for iv in (voffs+1):(nv+voffs)
        outar2=sub(outar,:,:,:,iv-voffs)
        mask2=sub(mask,:,:,:,iv-voffs)
        ycur=y1   #Current year to read
        i1cur=i1  #Current time step in year
        itcur=1   #Current time step in output file
        fin = false
        while !fin
            fin,ycur,i1cur,itcur = readFromDataYear(s.cube,outar2,mask2,s.variable[iv],ycur,grid_x1,nx,grid_y1,ny,itcur,i1cur,nt,NpY)
        end
        ncclose()
  end
end

function readFromDataYear{T}(cube::Cube,outar::AbstractArray{T,3},mask::AbstractArray{UInt8,3},variable,y,grid_x1,nx,grid_y1,ny,itcur,i1cur,ntime,NpY)
  filename=joinpath(cube.base_dir,"data",variable,string(y,"_",variable,".nc"))
  ntleft = ntime - itcur + 1
  nt = min(NpY-i1cur+1,ntleft)
  xr = grid_x1:(grid_x1+nx-1)
  yr = grid_y1:(grid_y1+ny-1)
  if isfile(filename)
    v=NetCDF.open(filename,variable);
    outar[1:nx,1:ny,itcur:(itcur+nt-1)]=v[xr,yr,i1cur:(i1cur+nt-1)]
    missval=ncgetatt(filename,variable,"_FillValue")
    for i=eachindex(outar)
      if outar[i] == missval
        mask[i]=mask[i] | MISSING
        outar[i]=oftype(outar[i],NaN)
      end
    end
  else
    for i=eachindex(mask)
      mask[i]=(mask[i] | OUTOFPERIOD)
      outar[i]=oftype(outar[i],NaN)
    end
  end
  itcur+=nt
  y+=1
  i1cur=1
  fin=nt==ntleft
  return fin,y,i1cur,itcur
end



end