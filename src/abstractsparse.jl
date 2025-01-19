# This file is a part of Julia. License is MIT: https://julialang.org/license

"""
    AbstractSparseArray{Tv,Ti,N}

Supertype for `N`-dimensional sparse arrays (or array-like types) with elements
of type `Tv` and index type `Ti`. [`SparseMatrixCSC`](@ref), [`SparseVector`](@ref)
and `SuiteSparse.CHOLMOD.Sparse` are subtypes of this.
"""
abstract type AbstractSparseArray{Tv,Ti,N} <: AbstractArray{Tv,N} end

"""
    AbstractSparseVector{Tv,Ti}

Supertype for one-dimensional sparse arrays (or array-like types) with elements
of type `Tv` and index type `Ti`. Alias for `AbstractSparseArray{Tv,Ti,1}`.
"""
const AbstractSparseVector{Tv,Ti} = AbstractSparseArray{Tv,Ti,1}

"""
    AbstractCompressedVector{Tv,Ti}

Supertype for vectors stored using a compressed map.
"""
abstract type AbstractCompressedVector{Tv,Ti} <: AbstractSparseVector{Tv,Ti} end

"""
    AbstractSparseMatrix{Tv,Ti}

Supertype for two-dimensional sparse arrays (or array-like types) with elements
of type `Tv` and index type `Ti`. Alias for `AbstractSparseArray{Tv,Ti,2}`.
"""
const AbstractSparseMatrix{Tv,Ti} = AbstractSparseArray{Tv,Ti,2}

const AbstractSparseVecOrMat = Union{AbstractSparseVector,AbstractSparseMatrix}

"""
    AbstractSparseMatrixCSC{Tv,Ti<:Integer} <: AbstractSparseMatrix{Tv,Ti}

Supertype for sparse matrix with elements of type `Tv` and index type `Ti` 
in compressed sparse column (CSC) format. Subtypes of this type are expected to implement 
[`nnz`](@ref),  [`rowvals`](@ref),  [`nzrange`](@ref), [`nonzeros`](@ref) and [`getcolptr`](@ref).
"""
abstract type AbstractSparseMatrixCSC{Tv,Ti<:Integer} <: AbstractSparseMatrix{Tv,Ti} end


"""
    issparse(S)

Returns `true` if `S` is sparse, and `false` otherwise.

# Examples
```jldoctest
julia> sv = sparsevec([1, 4], [2.3, 2.2], 10)
10-element SparseVector{Float64, Int64} with 2 stored entries:
  [1]  =  2.3
  [4]  =  2.2

julia> issparse(sv)
true

julia> issparse(Array(sv))
false
```
"""
function issparse(A::AbstractArray)
    # Handle wrapper arrays: sparse if it is wrapping a sparse array.
    # This gets compiled away during specialization.
    p = parent(A)
    if p === A
        # have reached top of wrapping without finding a sparse array, assume it is not.
        return false
    else
        return issparse(p)
    end
end
issparse(A::DenseArray) = false
issparse(S::AbstractSparseArray) = true

indtype(S::AbstractSparseArray{<:Any,Ti}) where {Ti} = Ti
indtype(T::UpperOrLowerTriangular{<:Any,<:AbstractSparseArray}) = indtype(parent(T))

# The following two methods should be overloaded by concrete types to avoid
# allocating the I = findall(...)
_sparse_findnextnz(v::AbstractSparseArray, i) = (I = findall(_isnotzero, v); n = searchsortedfirst(I, i); n<=length(I) ? I[n] : nothing)
_sparse_findprevnz(v::AbstractSparseArray, i) = (I = findall(_isnotzero, v); n = searchsortedlast(I, i);  _isnotzero(n) ? I[n] : nothing)

function findnext(f::Function, v::AbstractSparseArray, i)
    # short-circuit the case f == !iszero because that avoids
    # allocating e.g. zero(BigInt) for the f(zero(...)) test.
    if nnz(v) == length(v) || (f != (!iszero) && f != _isnotzero && f(zero(eltype(v))))
        return invoke(findnext, Tuple{Function,Any,Any}, f, v, i)
    end
    j = _sparse_findnextnz(v, i)
    while j !== nothing && !f(v[j])
        j = _sparse_findnextnz(v, nextind(v, j))
    end
    return j
end

function findprev(f::Function, v::AbstractSparseArray, i)
    # short-circuit the case f == !iszero because that avoids
    # allocating e.g. zero(BigInt) for the f(zero(...)) test.
    if nnz(v) == length(v) || (f != (!iszero) && f != _isnotzero && f(zero(eltype(v))))
        return invoke(findprev, Tuple{Function,Any,Any}, f, v, i)
    end
    j = _sparse_findprevnz(v, i)
    while j !== nothing && !f(v[j])
        j = _sparse_findprevnz(v, prevind(v, j))
    end
    return j
end

"""
    findnz(A::SparseMatrixCSC)

Return a tuple `(I, J, V)` where `I` and `J` are the row and column indices of the stored
("structurally non-zero") values in sparse matrix `A`, and `V` is a vector of the values.

# Examples
```jldoctest
julia> A = sparse([1 2 0; 0 0 3; 0 4 0])
3×3 SparseMatrixCSC{Int64, Int64} with 4 stored entries:
 1  2  ⋅
 ⋅  ⋅  3
 ⋅  4  ⋅

julia> findnz(A)
([1, 1, 3, 2], [1, 2, 2, 3], [1, 2, 4, 3])
```
"""
function findnz end

widelength(x::AbstractSparseArray) = prod(Int64.(size(x)))


const _restore_scalar_indexing = Expr[]
const _destroy_scalar_indexing = Expr[]
"""
    @RCI f

records the function `f` to be overwritten (and restored) with `allowscalar(::Bool)`. This is an
experimental feature.

Note that it will evaluate the function in the top level of the package. The original code for `f`
is stored in `_restore_scalar_indexing` and a function that has the same definition as `f` but
returns an error is stored in `_destroy_scalar_indexing`.
"""
macro RCI(exp)
    # Evaluate to not push any broken code in the arrays when developing this package.
    # Ensures that restore has the exact same effect.
    # Expand macro so we can chain macros. Save the expanded version for speed
    exp = macroexpand(__module__, exp)
    @eval __module__ $exp
    if length(exp.args) == 2 && exp.head ∈ (:function, :(=))
        push!(_restore_scalar_indexing, exp)
        push!(_destroy_scalar_indexing,
            Expr(exp.head,
            exp.args[1],
            :(error("scalar indexing was turned off"))))
    else
        error("can't parse expression")
    end
    return
end

"""
    allowscalar(::Bool)

An experimental function that allows one to disable and re-enable scalar indexing for sparse matrices and vectors.

`allowscalar(false)` will disable scalar indexing for sparse matrices and vectors.
`allowscalar(true)` will restore the original scalar indexing functionality.

Since this function overwrites existing definitions, it will lead to recompilation. It is useful mainly when testing
code for devices such as [GPUs](https://cuda.juliagpu.org/stable/usage/workflow/), where the presence of scalar indexing can lead to substantial slowdowns.
Disabling scalar indexing during such tests can help identify performance bottlenecks quickly.
"""
allowscalar(p::Bool) = if p
    for i in _restore_scalar_indexing
        @eval $i
    end
else
    for i in _destroy_scalar_indexing
        @eval $i
    end
end

macro allowscalar(p)
    quote
        $(allowscalar)($(esc(p)))
        @Core.latestworld
    end
end

@inline _is_fixed(::AbstractArray) = false
@inline _is_fixed(A::AbstractArray, Bs::Vararg{Any,N}) where N = _is_fixed(A) || (N > 0 && _is_fixed(Bs...))
macro if_move_fixed(a...)
    length(a) <= 1 && error("@if_move_fixed needs at least two arguments")
    h, v = esc.(a[1:end - 1]), esc(a[end])
    :(_is_fixed($(h...)) ? move_fixed($v) : $v)
end
