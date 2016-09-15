"""
The functions provided by CABLAB are supposed to work on different types of cubes. This module defines the interface for all
Data types that
"""
module Cubes
export Axes, AbstractCubeData, getSubRange, readCubeData, AbstractCubeMem, axesCubeMem,CubeAxis, TimeAxis, VariableAxis, LonAxis, LatAxis, CountryAxis, SpatialPointAxis, axes,
       AbstractSubCube, CubeMem, openTempCube, EmptyCube, YearStepRange, _read, saveCube, loadCube, RangeAxis, CategoricalAxis, axVal2Index, MSCAxis,
       getSingVal, FitAxis, TimeScaleAxis, QuantileAxis, MethodAxis

"""
Supertype of all cubes. All map and plot functions are supposed to work on subtypes of these. This is done by implementing the following functions
"""
abstract AbstractCubeData{T,N}

"""
getSubRange reads some Cube data and writes it to a pre-allocated memory.
"""
getSubRange(c::AbstractCubeData,a...)=error("getSubrange called in the wrong way with argument types $(typeof(c)), $(map(typeof,a))")

"""
getSingVal reads a single point from the cube's data
"""
getSingVal(c::AbstractCubeData,a...)=error("getSingVal called in the wrong way with argument types $(typeof(c)), $(map(typeof,a))")


"""
This function reads a Cube's data and returns it to memory
"""
function readCubeData end

"""
This function calculates a subset of a cube's data
"""
function subsetCubeData end

"""
Internal function to read a range from a datacube
"""
_read(c::AbstractCubeData,d,r::CartesianRange)=error("_read not implemented for $(typeof(c))")

"Returns the axes of a Cube"
axes(c::AbstractCubeData)=error("Axes function not implemented for $(typeof(c))")


"Supertype of all subtypes of the original data cube"
abstract AbstractSubCube{T,N} <: AbstractCubeData{T,N}


"Supertype of all in-memory representations of a data cube"
abstract AbstractCubeMem{T,N} <: AbstractCubeData{T,N}

include("Axes.jl")
importall .Axes

immutable EmptyCube{T}<:AbstractCubeData{T,0} end

type CubeMem{T,N} <: AbstractCubeMem{T,N}
  axes::Vector{CubeAxis}
  data::Array{T,N}
  mask::Array{UInt8,N}
end


Base.permutedims(c::CubeMem,p)=CubeMem(c.axes[collect(p)],permutedims(c.data,p),permutedims(c.mask,p))
axes(c::CubeMem)=c.axes

Base.linearindexing(::CubeMem)=Base.LinearFast()
Base.getindex(c::CubeMem,i::Integer)=getindex(c.data,i)
Base.setindex!(c::CubeMem,i::Integer,v)=setindex!(c.data,i,v)
Base.size(c::CubeMem)=size(c.data)
Base.similar(c::CubeMem)=cubeMem(c.axes,similar(c.data),copy(c.mask))
Base.ndims{T,N}(c::CubeMem{T,N})=N

function getSubRange{T,N}(c::CubeMem{T,N},i...;write::Bool=true)
  length(i)==N || error("Wring number of slice arguments to getSubRange")
  return (slice(c.data,i...),slice(c.mask,i...))
end

getSingVal{T,N}(c::CubeMem{T,N},i...;write::Bool=true)=(c.data[i...],c.mask[i...])
getSingVal{T}(c::CubeMem{T,0};write::Bool=true)=(c.data[1],c.mask[1])
getSingVal{T}(c::CubeAxis{T},i;write::Bool=true)=(c.values[i],nothing)


getSubRange{T}(c::CubeMem{T,0};write::Bool=true)=(c.data,c.mask)

function getSubRange{T}(c::CubeAxis{T},i;write::Bool=true)
  r=c.values[i]
  return (r,nothing)
end

import ..CABLABTools.toRange
function _read(c::CubeMem,thedata::NTuple{2},r::CartesianRange)
  outar,outmask=thedata
  data=slice(c.data,toRange(r)...)
  mask=slice(c.data,toRange(r)...)
  copy!(outar,data)
  copy!(outmask,mask)
end

"This function creates a new view of the cube, joining longitude and latitude axes to a single spatial axis"
function mergeLonLat!(c::CubeMem)
ilon=findAxis(LonAxis,c.axes)
ilat=findAxis(LatAxis,c.axes)
ilat==ilon+1 || error("Lon and Lat axes must be consecutive to merge")
lonAx=c.axes[ilon]
latAx=c.axes[ilat]
newVals=Tuple{Float64,Float64}[(lonAx.values[i],latAx.values[j]) for i=1:length(lonAx), j=1:length(latAx)]
newAx=SpatialPointAxis(reshape(newVals,length(lonAx)*length(latAx)));
allNewAx=[c.axes[1:ilon-1];newAx;c.axes[ilat+1:end]];
s  = size(c.data)
s1 = s[1:ilon-1]
s2 = s[ilat+1:end]
newShape=(s1...,length(lonAx)*length(latAx),s2...)
CubeMem(allNewAx,reshape(c.data,newShape),reshape(c.mask,newShape))
end

include("TempCubes.jl")
importall .TempCubes
getCubeDes(c::AbstractSubCube)="Data Cube view"
getCubeDes(c::TempCube)="Temporary Data Cube"
getCubeDes(c::CubeMem)="In-Memory data cube"
function Base.show(io::IO,c::AbstractCubeData)
    println(io,getCubeDes(c), " with the following dimensions")
    for a in axes(c)
        println(io,a)
    end
end


Base.show(io::IO,a::RangeAxis)=print(io,rpad(Axes.axname(a),20," "),"Axis with ",length(a)," Elements from ",first(a.values)," to ",last(a.values))
function Base.show(io::IO,a::CategoricalAxis)
    print(io,rpad(Axes.axname(a),20," "), "Axis with elements: ")
    for v in a.values
        print(io,v," ")
    end
end
Base.show(io::IO,a::SpatialPointAxis)=print(io,"Spatial points axis with ",length(a.values)," points")




end
