export ConcatCube, concatenateCubes
export mergeAxes
import ..ESDLTools.getiperm
import ..Cubes: ESDLArray, caxes, iscompressed, cubechunks, chunkoffset
using DiskArrayTools: diskstack

function Base.permutedims(x::AbstractCubeData{T,N},perm) where {T,N}
  ESDLArray(x.axes[perm],permutedims(x.data,perm),x.properties,x.cleaner)
end

function Base.map(op, incubes::AbstractCubeData...)
  axlist=copy(caxes(incubes[1]))
  all(i->caxes(i)==axlist,incubes) || error("All axes must match")
  props=merge(cubeproperties.(incubes)...)
  ESDLArray(axlist,broadcast(op,map(c->c.data,incubes)...),props,map(i->i.cleaner,incubes))
end



"""
    function concatenateCubes(cubelist, cataxis::CategoricalAxis)

Concatenates a vector of datacubes that have identical axes to a new single cube along the new
axis `cataxis`
"""
function concatenateCubes(cl,cataxis::CubeAxis)
  length(cataxis.values)==length(cl) || error("cataxis must have same length as cube list")
  axlist=copy(caxes(cl[1]))
  T=eltype(cl[1])
  N=ndims(cl[1])
  for i=2:length(cl)
    all(caxes(cl[i]).==axlist) || error("All cubes must have the same axes, cube number $i does not match")
    eltype(cl[i])==T || error("All cubes must have the same element type, cube number $i does not match")
    ndims(cl[i])==N || error("All cubes must have the same dimension")
  end
  props=mapreduce(cubeproperties,merge,cl,init=cubeproperties(cl[1]))
  ESDLArray([axlist...,cataxis],diskstack([c.data for c in cl]),props)
end
function concatenateCubes(;kwargs...)
  cubenames = String[]
  for (n,c) in kwargs
    push!(cubenames,string(n))
  end
  cubes = map(i->i[2],collect(kwargs))
  findAxis("Variable",cubes[1]) === nothing || error("Input cubes must not contain a variable kwarg concatenation")
  concatenateCubes(cubes, CategoricalAxis("Variable",cubenames))
end
