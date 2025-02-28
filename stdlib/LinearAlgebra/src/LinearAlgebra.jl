# This file is a part of Julia. License is MIT: https://julialang.org/license

"""
Linear algebra module. Provides array arithmetic,
matrix factorizations and other linear algebra related
functionality.
"""
module LinearAlgebra

import Base: \, /, *, ^, +, -, ==
import Base: USE_BLAS64, abs, acos, acosh, acot, acoth, acsc, acsch, adjoint, asec, asech,
    asin, asinh, atan, atanh, axes, big, broadcast, ceil, cis, collect, conj, convert, copy,
    copyto!, copymutable, cos, cosh, cot, coth, csc, csch, eltype, exp, fill!, floor,
    getindex, hcat, getproperty, imag, inv, isapprox, isequal, isone, iszero, IndexStyle,
    kron, kron!, length, log, map, ndims, one, oneunit, parent, permutedims,
    power_by_squaring, promote_rule, real, sec, sech, setindex!, show, similar, sin,
    sincos, sinh, size, sqrt, strides, stride, tan, tanh, transpose, trunc, typed_hcat,
    vec, view, zero
using Base: IndexLinear, promote_eltype, promote_op, promote_typeof, print_matrix,
    @propagate_inbounds, reduce, typed_hvcat, typed_vcat, require_one_based_indexing,
    splat
using Base.Broadcast: Broadcasted, broadcasted
using Base.PermutedDimsArrays: CommutativeOps
using OpenBLAS_jll
using libblastrampoline_jll
import Libdl

export
# Modules
    LAPACK,
    BLAS,

# Types
    Adjoint,
    Transpose,
    SymTridiagonal,
    Tridiagonal,
    Bidiagonal,
    Factorization,
    BunchKaufman,
    Cholesky,
    CholeskyPivoted,
    ColumnNorm,
    Eigen,
    GeneralizedEigen,
    GeneralizedSVD,
    GeneralizedSchur,
    Hessenberg,
    LU,
    LDLt,
    NoPivot,
    RowNonZero,
    QR,
    QRPivoted,
    LQ,
    Schur,
    SVD,
    Hermitian,
    RowMaximum,
    Symmetric,
    LowerTriangular,
    UpperTriangular,
    UnitLowerTriangular,
    UnitUpperTriangular,
    UpperHessenberg,
    Diagonal,
    UniformScaling,

# Functions
    axpy!,
    axpby!,
    bunchkaufman,
    bunchkaufman!,
    cholesky,
    cholesky!,
    cond,
    condskeel,
    copyto!,
    copy_transpose!,
    cross,
    adjoint,
    adjoint!,
    det,
    diag,
    diagind,
    diagm,
    dot,
    eigen,
    eigen!,
    eigmax,
    eigmin,
    eigvals,
    eigvals!,
    eigvecs,
    factorize,
    givens,
    hermitianpart,
    hermitianpart!,
    hessenberg,
    hessenberg!,
    isdiag,
    ishermitian,
    isposdef,
    isposdef!,
    issuccess,
    issymmetric,
    istril,
    istriu,
    kron,
    kron!,
    ldiv!,
    ldlt!,
    ldlt,
    logabsdet,
    logdet,
    lowrankdowndate,
    lowrankdowndate!,
    lowrankupdate,
    lowrankupdate!,
    lu,
    lu!,
    lyap,
    mul!,
    lmul!,
    rmul!,
    norm,
    normalize,
    normalize!,
    nullspace,
    ordschur!,
    ordschur,
    pinv,
    qr,
    qr!,
    lq,
    lq!,
    opnorm,
    rank,
    rdiv!,
    reflect!,
    rotate!,
    schur,
    schur!,
    svd,
    svd!,
    svdvals!,
    svdvals,
    sylvester,
    tr,
    transpose,
    transpose!,
    tril,
    triu,
    tril!,
    triu!,

# Operators
    \,
    /,

# Constants
    I

const BlasFloat = Union{Float64,Float32,ComplexF64,ComplexF32}
const BlasReal = Union{Float64,Float32}
const BlasComplex = Union{ComplexF64,ComplexF32}

if USE_BLAS64
    const BlasInt = Int64
else
    const BlasInt = Int32
end


abstract type Algorithm end
struct DivideAndConquer <: Algorithm end
struct QRIteration <: Algorithm end

abstract type PivotingStrategy end
struct NoPivot <: PivotingStrategy end
struct RowNonZero <: PivotingStrategy end
struct RowMaximum <: PivotingStrategy end
struct ColumnNorm <: PivotingStrategy end

# Check that stride of matrix/vector is 1
# Writing like this to avoid splatting penalty when called with multiple arguments,
# see PR 16416
"""
    stride1(A) -> Int

Return the distance between successive array elements
in dimension 1 in units of element size.

# Examples
```jldoctest
julia> A = [1,2,3,4]
4-element Vector{Int64}:
 1
 2
 3
 4

julia> LinearAlgebra.stride1(A)
1

julia> B = view(A, 2:2:4)
2-element view(::Vector{Int64}, 2:2:4) with eltype Int64:
 2
 4

julia> LinearAlgebra.stride1(B)
2
```
"""
stride1(x) = stride(x,1)
stride1(x::Array) = 1
stride1(x::DenseArray) = stride(x, 1)::Int

@inline chkstride1(A...) = _chkstride1(true, A...)
@noinline _chkstride1(ok::Bool) = ok || error("matrix does not have contiguous columns")
@inline _chkstride1(ok::Bool, A, B...) = _chkstride1(ok & (stride1(A) == 1), B...)

"""
    LinearAlgebra.checksquare(A)

Check that a matrix is square, then return its common dimension.
For multiple arguments, return a vector.

# Examples
```jldoctest
julia> A = fill(1, (4,4)); B = fill(1, (5,5));

julia> LinearAlgebra.checksquare(A, B)
2-element Vector{Int64}:
 4
 5
```
"""
function checksquare(A)
    m,n = size(A)
    m == n || throw(DimensionMismatch("matrix is not square: dimensions are $(size(A))"))
    m
end

function checksquare(A...)
    sizes = Int[]
    for a in A
        size(a,1)==size(a,2) || throw(DimensionMismatch("matrix is not square: dimensions are $(size(a))"))
        push!(sizes, size(a,1))
    end
    return sizes
end

function char_uplo(uplo::Symbol)
    if uplo === :U
        return 'U'
    elseif uplo === :L
        return 'L'
    else
        throw_uplo()
    end
end

function sym_uplo(uplo::Char)
    if uplo == 'U'
        return :U
    elseif uplo == 'L'
        return :L
    else
        throw_uplo()
    end
end

@noinline throw_uplo() = throw(ArgumentError("uplo argument must be either :U (upper) or :L (lower)"))

"""
    ldiv!(Y, A, B) -> Y

Compute `A \\ B` in-place and store the result in `Y`, returning the result.

The argument `A` should *not* be a matrix.  Rather, instead of matrices it should be a
factorization object (e.g. produced by [`factorize`](@ref) or [`cholesky`](@ref)).
The reason for this is that factorization itself is both expensive and typically allocates memory
(although it can also be done in-place via, e.g., [`lu!`](@ref)),
and performance-critical situations requiring `ldiv!` usually also require fine-grained
control over the factorization of `A`.

!!! note
    Certain structured matrix types, such as `Diagonal` and `UpperTriangular`, are permitted, as
    these are already in a factorized form

# Examples
```jldoctest
julia> A = [1 2.2 4; 3.1 0.2 3; 4 1 2];

julia> X = [1; 2.5; 3];

julia> Y = zero(X);

julia> ldiv!(Y, qr(A), X);

julia> Y
3-element Vector{Float64}:
  0.7128099173553719
 -0.051652892561983674
  0.10020661157024757

julia> A\\X
3-element Vector{Float64}:
  0.7128099173553719
 -0.05165289256198333
  0.10020661157024785
```
"""
ldiv!(Y, A, B)

"""
    ldiv!(A, B)

Compute `A \\ B` in-place and overwriting `B` to store the result.

The argument `A` should *not* be a matrix.  Rather, instead of matrices it should be a
factorization object (e.g. produced by [`factorize`](@ref) or [`cholesky`](@ref)).
The reason for this is that factorization itself is both expensive and typically allocates memory
(although it can also be done in-place via, e.g., [`lu!`](@ref)),
and performance-critical situations requiring `ldiv!` usually also require fine-grained
control over the factorization of `A`.

!!! note
    Certain structured matrix types, such as `Diagonal` and `UpperTriangular`, are permitted, as
    these are already in a factorized form

# Examples
```jldoctest
julia> A = [1 2.2 4; 3.1 0.2 3; 4 1 2];

julia> X = [1; 2.5; 3];

julia> Y = copy(X);

julia> ldiv!(qr(A), X);

julia> X
3-element Vector{Float64}:
  0.7128099173553719
 -0.051652892561983674
  0.10020661157024757

julia> A\\Y
3-element Vector{Float64}:
  0.7128099173553719
 -0.05165289256198333
  0.10020661157024785
```
"""
ldiv!(A, B)


"""
    rdiv!(A, B)

Compute `A / B` in-place and overwriting `A` to store the result.

The argument `B` should *not* be a matrix.  Rather, instead of matrices it should be a
factorization object (e.g. produced by [`factorize`](@ref) or [`cholesky`](@ref)).
The reason for this is that factorization itself is both expensive and typically allocates memory
(although it can also be done in-place via, e.g., [`lu!`](@ref)),
and performance-critical situations requiring `rdiv!` usually also require fine-grained
control over the factorization of `B`.

!!! note
    Certain structured matrix types, such as `Diagonal` and `UpperTriangular`, are permitted, as
    these are already in a factorized form
"""
rdiv!(A, B)

"""
    copy_oftype(A, T)

Creates a copy of `A` with eltype `T`. No assertions about mutability of the result are
made. When `eltype(A) == T`, then this calls `copy(A)` which may be overloaded for custom
array types. Otherwise, this calls `convert(AbstractArray{T}, A)`.
"""
copy_oftype(A::AbstractArray{T}, ::Type{T}) where {T} = copy(A)
copy_oftype(A::AbstractArray{T,N}, ::Type{S}) where {T,N,S} = convert(AbstractArray{S,N}, A)

"""
    copymutable_oftype(A, T)

Copy `A` to a mutable array with eltype `T` based on `similar(A, T)`.

The resulting matrix typically has similar algebraic structure as `A`. For
example, supplying a tridiagonal matrix results in another tridiagonal matrix.
In general, the type of the output corresponds to that of `similar(A, T)`.

In LinearAlgebra, mutable copies (of some desired eltype) are created to be passed
to in-place algorithms (such as `ldiv!`, `rdiv!`, `lu!` and so on). If the specific
algorithm is known to preserve the algebraic structure, use `copymutable_oftype`.
If the algorithm is known to return a dense matrix (or some wrapper backed by a dense
matrix), then use `copy_similar`.

See also: `Base.copymutable`, `copy_similar`.
"""
copymutable_oftype(A::AbstractArray, ::Type{S}) where {S} = copyto!(similar(A, S), A)

"""
    copy_similar(A, T)

Copy `A` to a mutable array with eltype `T` based on `similar(A, T, size(A))`.

Compared to `copymutable_oftype`, the result can be more flexible. In general, the type
of the output corresponds to that of the three-argument method `similar(A, T, size(A))`.

See also: `copymutable_oftype`.
"""
copy_similar(A::AbstractArray, ::Type{T}) where {T} = copyto!(similar(A, T, size(A)), A)


include("adjtrans.jl")
include("transpose.jl")

include("exceptions.jl")
include("generic.jl")

include("blas.jl")
include("matmul.jl")
include("lapack.jl")

include("dense.jl")
include("tridiag.jl")
include("triangular.jl")

include("factorization.jl")
include("eigen.jl")
include("svd.jl")
include("symmetric.jl")
include("cholesky.jl")
include("lu.jl")
include("bunchkaufman.jl")
include("diagonal.jl")
include("symmetriceigen.jl")
include("bidiag.jl")
include("uniformscaling.jl")
include("qr.jl")
include("lq.jl")
include("hessenberg.jl")
include("abstractq.jl")
include("givens.jl")
include("special.jl")
include("bitarray.jl")
include("ldlt.jl")
include("schur.jl")
include("structuredbroadcast.jl")
include("deprecated.jl")

const ⋅ = dot
const × = cross
export ⋅, ×

wrapper_char(::AbstractArray) = 'N'
wrapper_char(::Adjoint) = 'C'
wrapper_char(::Adjoint{<:Real}) = 'T'
wrapper_char(::Transpose) = 'T'
wrapper_char(A::Hermitian) = A.uplo == 'U' ? 'H' : 'h'
wrapper_char(A::Hermitian{<:Real}) = A.uplo == 'U' ? 'S' : 's'
wrapper_char(A::Symmetric) = A.uplo == 'U' ? 'S' : 's'

Base.@constprop :aggressive function wrap(A::AbstractVecOrMat, tA::AbstractChar)
    if tA == 'N'
        return A
    elseif tA == 'T'
        return transpose(A)
    elseif tA == 'C'
        return adjoint(A)
    elseif tA == 'H'
        return Hermitian(A, :U)
    elseif tA == 'h'
        return Hermitian(A, :L)
    elseif tA == 'S'
        return Symmetric(A, :U)
    else # tA == 's'
        return Symmetric(A, :L)
    end
end

_unwrap(A::AbstractVecOrMat) = A

## convenience methods
## return only the solution of a least squares problem while avoiding promoting
## vectors to matrices.
_cut_B(x::AbstractVector, r::UnitRange) = length(x)  > length(r) ? x[r]   : x
_cut_B(X::AbstractMatrix, r::UnitRange) = size(X, 1) > length(r) ? X[r,:] : X

# SymTridiagonal ev can be the same length as dv, but the last element is
# ignored. However, some methods can fail if they read the entire ev
# rather than just the meaningful elements. This is a helper function
# for getting only the meaningful elements of ev. See #41089
_evview(S::SymTridiagonal) = @view S.ev[begin:begin + length(S.dv) - 2]

## append right hand side with zeros if necessary
_zeros(::Type{T}, b::AbstractVector, n::Integer) where {T} = zeros(T, max(length(b), n))
_zeros(::Type{T}, B::AbstractMatrix, n::Integer) where {T} = zeros(T, max(size(B, 1), n), size(B, 2))

# convert to Vector, if necessary
_makevector(x::Vector) = x
_makevector(x::AbstractVector) = Vector(x)

# append a zero element / drop the last element
_pushzero(A) = (B = similar(A, length(A)+1); @inbounds B[begin:end-1] .= A; @inbounds B[end] = zero(eltype(B)); B)
_droplast!(A) = deleteat!(A, lastindex(A))

# some trait like this would be cool
# onedefined(::Type{T}) where {T} = hasmethod(one, (T,))
# but we are actually asking for oneunit(T), that is, however, defined for generic T as
# `T(one(T))`, so the question is equivalent for whether one(T) is defined
onedefined(::Type) = false
onedefined(::Type{<:Number}) = true

# initialize return array for op(A, B)
_init_eltype(::typeof(*), ::Type{TA}, ::Type{TB}) where {TA,TB} =
    (onedefined(TA) && onedefined(TB)) ?
        typeof(matprod(oneunit(TA), oneunit(TB))) :
        promote_op(matprod, TA, TB)
_init_eltype(op, ::Type{TA}, ::Type{TB}) where {TA,TB} =
    (onedefined(TA) && onedefined(TB)) ?
        typeof(op(oneunit(TA), oneunit(TB))) :
        promote_op(op, TA, TB)
_initarray(op, ::Type{TA}, ::Type{TB}, C) where {TA,TB} =
    similar(C, _init_eltype(op, TA, TB), size(C))

# General fallback definition for handling under- and overdetermined system as well as square problems
# While this definition is pretty general, it does e.g. promote to common element type of lhs and rhs
# which is required by LAPACK but not SuiteSparse which allows real-complex solves in some cases. Hence,
# we restrict this method to only the LAPACK factorizations in LinearAlgebra.
# The definition is put here since it explicitly references all the Factorization structs so it has
# to be located after all the files that define the structs.
const LAPACKFactorizations{T,S} = Union{
    BunchKaufman{T,S},
    Cholesky{T,S},
    LQ{T,S},
    LU{T,S},
    QR{T,S},
    QRCompactWY{T,S},
    QRPivoted{T,S},
    SVD{T,<:Real,S}}

(\)(F::LAPACKFactorizations, B::AbstractVecOrMat) = ldiv(F, B)
(\)(F::AdjointFactorization{<:Any,<:LAPACKFactorizations}, B::AbstractVecOrMat) = ldiv(F, B)
(\)(F::TransposeFactorization{<:Any,<:LU}, B::AbstractVecOrMat) = ldiv(F, B)

function ldiv(F::Factorization, B::AbstractVecOrMat)
    require_one_based_indexing(B)
    m, n = size(F)
    if m != size(B, 1)
        throw(DimensionMismatch("arguments must have the same number of rows"))
    end

    TFB = typeof(oneunit(eltype(B)) / oneunit(eltype(F)))
    FF = Factorization{TFB}(F)

    # For wide problem we (often) compute a minimum norm solution. The solution
    # is larger than the right hand side so we use size(F, 2).
    BB = _zeros(TFB, B, n)

    if n > size(B, 1)
        # Underdetermined
        copyto!(view(BB, 1:m, :), B)
    else
        copyto!(BB, B)
    end

    ldiv!(FF, BB)

    # For tall problems, we compute a least squares solution so only part
    # of the rhs should be returned from \ while ldiv! uses (and returns)
    # the complete rhs
    return _cut_B(BB, 1:n)
end
# disambiguate
(\)(F::LAPACKFactorizations{T}, B::VecOrMat{Complex{T}}) where {T<:BlasReal} =
    @invoke \(F::Factorization{T}, B::VecOrMat{Complex{T}})
(\)(F::AdjointFactorization{T,<:LAPACKFactorizations}, B::VecOrMat{Complex{T}}) where {T<:BlasReal} =
    ldiv(F, B)
(\)(F::TransposeFactorization{T,<:LU}, B::VecOrMat{Complex{T}}) where {T<:BlasReal} =
    ldiv(F, B)

"""
    LinearAlgebra.peakflops(n::Integer=4096; eltype::DataType=Float64, ntrials::Integer=3, parallel::Bool=false)

`peakflops` computes the peak flop rate of the computer by using double precision
[`gemm!`](@ref LinearAlgebra.BLAS.gemm!). By default, if no arguments are specified, it
multiplies two `Float64` matrices of size `n x n`, where `n = 4096`. If the underlying BLAS is using
multiple threads, higher flop rates are realized. The number of BLAS threads can be set with
[`BLAS.set_num_threads(n)`](@ref).

If the keyword argument `eltype` is provided, `peakflops` will construct matrices with elements
of type `eltype` for calculating the peak flop rate.

By default, `peakflops` will use the best timing from 3 trials. If the `ntrials` keyword argument
is provided, `peakflops` will use those many trials for picking the best timing.

If the keyword argument `parallel` is set to `true`, `peakflops` is run in parallel on all
the worker processors. The flop rate of the entire parallel computer is returned. When
running in parallel, only 1 BLAS thread is used. The argument `n` still refers to the size
of the problem that is solved on each processor.

!!! compat "Julia 1.1"
    This function requires at least Julia 1.1. In Julia 1.0 it is available from
    the standard library `InteractiveUtils`.
"""
function peakflops(n::Integer=4096; eltype::DataType=Float64, ntrials::Integer=3, parallel::Bool=false)
    t = zeros(Float64, ntrials)
    for i=1:ntrials
        a = ones(eltype,n,n)
        t[i] = @elapsed a2 = a*a
        @assert a2[1,1] == n
    end

    if parallel
        let Distributed = Base.require(Base.PkgId(
                Base.UUID((0x8ba89e20_285c_5b6f, 0x9357_94700520ee1b)), "Distributed"))
            nworkers = @invokelatest Distributed.nworkers()
            results = @invokelatest Distributed.pmap(peakflops, fill(n, nworkers))
            return sum(results)
        end
    else
        return 2*Float64(n)^3 / minimum(t)
    end
end


function versioninfo(io::IO=stdout)
    indent = "  "
    config = BLAS.get_config()
    build_flags = join(string.(config.build_flags), ", ")
    println(io, "BLAS: ", BLAS.libblastrampoline, " (", build_flags, ")")
    for lib in config.loaded_libs
        interface = uppercase(string(lib.interface))
        println(io, indent, "--> ", lib.libname, " (", interface, ")")
    end
    println(io, "Threading:")
    println(io, indent, "Threads.threadpoolsize() = ", Threads.threadpoolsize())
    println(io, indent, "Threads.maxthreadid() = ", Base.Threads.maxthreadid())
    println(io, indent, "LinearAlgebra.BLAS.get_num_threads() = ", BLAS.get_num_threads())
    println(io, "Relevant environment variables:")
    env_var_names = [
        "JULIA_NUM_THREADS",
        "MKL_DYNAMIC",
        "MKL_NUM_THREADS",
         # OpenBLAS has a hierarchy of environment variables for setting the
         # number of threads, see
         # https://github.com/xianyi/OpenBLAS/blob/c43ec53bdd00d9423fc609d7b7ecb35e7bf41b85/README.md#setting-the-number-of-threads-using-environment-variables
        ("OPENBLAS_NUM_THREADS", "GOTO_NUM_THREADS", "OMP_NUM_THREADS"),
    ]
    printed_at_least_one_env_var = false
    print_var(io, indent, name) = println(io, indent, name, " = ", ENV[name])
    for name in env_var_names
        if name isa Tuple
            # If `name` is a Tuple, then find the first environment which is
            # defined, and disregard the following ones.
            for nm in name
                if haskey(ENV, nm)
                    print_var(io, indent, nm)
                    printed_at_least_one_env_var = true
                    break
                end
            end
        else
            if haskey(ENV, name)
                print_var(io, indent, name)
                printed_at_least_one_env_var = true
            end
        end
    end
    if !printed_at_least_one_env_var
        println(io, indent, "[none]")
    end
    return nothing
end

function __init__()
    try
        verbose = parse(Bool, get(ENV, "LBT_VERBOSE", "false"))
        BLAS.lbt_forward(OpenBLAS_jll.libopenblas_path; clear=true, verbose)
        BLAS.check()
    catch ex
        Base.showerror_nostdio(ex, "WARNING: Error during initialization of module LinearAlgebra")
    end
    # register a hook to disable BLAS threading
    Base.at_disable_library_threading(() -> BLAS.set_num_threads(1))

    # https://github.com/xianyi/OpenBLAS/blob/c43ec53bdd00d9423fc609d7b7ecb35e7bf41b85/README.md#setting-the-number-of-threads-using-environment-variables
    if !haskey(ENV, "OPENBLAS_NUM_THREADS") && !haskey(ENV, "GOTO_NUM_THREADS") && !haskey(ENV, "OMP_NUM_THREADS")
        @static if Sys.isapple() && Base.BinaryPlatforms.arch(Base.BinaryPlatforms.HostPlatform()) == "aarch64"
            BLAS.set_num_threads(max(1, Sys.CPU_THREADS))
        else
            BLAS.set_num_threads(max(1, Sys.CPU_THREADS ÷ 2))
        end
    end
end

end # module LinearAlgebra
