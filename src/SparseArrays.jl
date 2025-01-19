# This file is a part of Julia. License is MIT: https://julialang.org/license

"""
Support for sparse arrays. Provides `AbstractSparseArray` and subtypes.
"""
module SparseArrays

using Base: ReshapedArray, promote_op, setindex_shape_check, to_shape, tail,
    require_one_based_indexing, promote_eltype, @propagate_inbounds, &, |
using Base.Order: Forward
using LinearAlgebra
using LinearAlgebra: AdjOrTrans, AdjointFactorization, TransposeFactorization, matprod,
    AbstractQ, AdjointQ, HessenbergQ, QRCompactWYQ, QRPackedQ, LQPackedQ, MulAddMul,
    UpperOrLowerTriangular, @stable_muladdmul


import Base: +, -, *, \, /, ==, zero
import LinearAlgebra: mul!, ldiv!, rdiv!, cholesky, adjoint!, diag, eigen, dot,
    issymmetric, istril, istriu, lu, tr, transpose!, tril!, triu!, isbanded,
    cond, diagm, factorize, ishermitian, norm, opnorm, lmul!, rmul!, tril, triu,
    matprod_dest, generic_matvecmul!, generic_matmatmul!, copytrito!

import Base: adjoint, argmin, argmax, Array, broadcast, circshift!, complex, Complex,
    conj, conj!, convert, copy, copy!, copyto!, count, diff, findall, findmax, findmin,
    float, getindex, imag, inv, keytype, kron, kron!, length, map, maximum, minimum, permute!, real,
    rot180, rotl90, rotr90, setindex!, show, similar, size, sum, transpose,
    vcat, hcat, hvcat, cat, vec, reverse, reverse!

using Random: default_rng, AbstractRNG, randsubseq, randsubseq!

export AbstractSparseArray, AbstractSparseMatrix, AbstractSparseVector,
    SparseMatrixCSC, SparseVector, blockdiag, droptol!, dropzeros!, dropzeros,
    issparse, nonzeros, nzrange, rowvals, sparse, sparsevec, spdiagm,
    sprand, sprandn, spzeros, nnz, permute, findnz,  fkeep!, ftranspose!,
    sparse_hcat, sparse_vcat, sparse_hvcat

const LinAlgLeftQs = Union{HessenbergQ,QRCompactWYQ,QRPackedQ}

# helper function needed in sparsematrix, sparsevector and higherorderfns
# `iszero` and `!iszero` don't guarantee to return a boolean but we need one that does
# to remove the handle the structure of the array.
@inline _iszero(x) = iszero(x) === true
@inline _iszero(x::Number) = iszero(x)
@inline _iszero(x::AbstractArray) = iszero(x)
@inline _isnotzero(x) = iszero(x) !== true # like `!iszero(x)`, but handles `x::Missing`
@inline _isnotzero(x::Number) = !iszero(x)
@inline _isnotzero(x::AbstractArray) = !iszero(x)

## Functions to switch to 0-based indexing to call external sparse solvers

# Convert from 1-based to 0-based indices
function decrement!(A::AbstractArray{T}) where T<:Integer
    for i in eachindex(A); A[i] -= oneunit(T) end
    A
end
decrement(A::AbstractArray) = let y = Array(A)
    y .= y .- oneunit(eltype(A))
end

include("readonly.jl")
include("abstractsparse.jl")
include("sparsematrix.jl")
include("sparseconvert.jl")
include("sparsevector.jl")
include("higherorderfns.jl")
include("linalg.jl")
include("deprecated.jl")



# Convert from 0-based to 1-based indices
function increment!(A::AbstractArray{T}) where T<:Integer
    for i in eachindex(A); A[i] += oneunit(T) end
    A
end
increment(A::AbstractArray{<:Integer}) = increment!(copy(A))

include("solvers/LibSuiteSparse.jl")
using .LibSuiteSparse

if Base.USE_GPL_LIBS
    include("solvers/umfpack.jl")
    include("solvers/cholmod.jl")
    include("solvers/spqr.jl")
end

keytype(::Type{A}) where {Tv, Ti, A<:AbstractSparseArray{Tv,Ti}} = Ti
zero(a::AbstractSparseArray) = spzeros(eltype(a), keytype(a), size(a)...)

LinearAlgebra.diagzero(D::Diagonal{<:AbstractSparseMatrix{T}},i,j) where {T} =
    spzeros(T, size(D.diag[i], 1), size(D.diag[j], 2))

end
