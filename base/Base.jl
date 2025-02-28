# This file is a part of Julia. License is MIT: https://julialang.org/license

baremodule Base

using Core.Intrinsics, Core.IR

# to start, we're going to use a very simple definition of `include`
# that doesn't require any function (except what we can get from the `Core` top-module)
# start this big so that we don't have to resize before we have defined how to grow an array
const _included_files = Array{Tuple{Module,String},1}(Core.undef, 400)
setfield!(_included_files, :size, (1,))
function include(mod::Module, path::String)
    len = getfield(_included_files.size, 1)
    memlen = _included_files.ref.mem.length
    lenp1 = Core.add_int(len, 1)
    if len === memlen # by the time this is true we hopefully will have defined _growend!
        _growend!(_included_files, UInt(1))
    else
        setfield!(_included_files, :size, (lenp1,))
    end
    Core.memoryrefset!(Core.memoryref(_included_files.ref, lenp1), (mod, ccall(:jl_prepend_cwd, Any, (Any,), path)), :not_atomic, true)
    Core.println(path)
    ccall(:jl_uv_flush, Nothing, (Ptr{Nothing},), Core.io_pointer(Core.stdout))
    Core.include(mod, path)
end
include(path::String) = include(Base, path)

# from now on, this is now a top-module for resolving syntax
const is_primary_base_module = ccall(:jl_module_parent, Ref{Module}, (Any,), Base) === Core.Main
ccall(:jl_set_istopmod, Cvoid, (Any, Bool), Base, is_primary_base_module)

# The @inline/@noinline macros that can be applied to a function declaration are not available
# until after array.jl, and so we will mark them within a function body instead.
macro inline()   Expr(:meta, :inline)   end
macro noinline() Expr(:meta, :noinline) end

macro _boundscheck() Expr(:boundscheck) end

# Try to help prevent users from shooting them-selves in the foot
# with ambiguities by defining a few common and critical operations
# (and these don't need the extra convert code)
getproperty(x::Module, f::Symbol) = (@inline; getglobal(x, f))
getproperty(x::Type, f::Symbol) = (@inline; getfield(x, f))
setproperty!(x::Type, f::Symbol, v) = error("setfield! fields of Types should not be changed")
setproperty!(x::Array, f::Symbol, v) = error("setfield! fields of Array should not be changed")
getproperty(x::Tuple, f::Int) = (@inline; getfield(x, f))
setproperty!(x::Tuple, f::Int, v) = setfield!(x, f, v) # to get a decent error

getproperty(x, f::Symbol) = (@inline; getfield(x, f))
function setproperty!(x, f::Symbol, v)
    ty = fieldtype(typeof(x), f)
    val = v isa ty ? v : convert(ty, v)
    return setfield!(x, f, val)
end

dotgetproperty(x, f) = getproperty(x, f)

getproperty(x::Module, f::Symbol, order::Symbol) = (@inline; getglobal(x, f, order))
function setproperty!(x::Module, f::Symbol, v, order::Symbol=:monotonic)
    @inline
    ty = Core.get_binding_type(x, f)
    val = v isa ty ? v : convert(ty, v)
    return setglobal!(x, f, val, order)
end
getproperty(x::Type, f::Symbol, order::Symbol) = (@inline; getfield(x, f, order))
setproperty!(x::Type, f::Symbol, v, order::Symbol) = error("setfield! fields of Types should not be changed")
getproperty(x::Tuple, f::Int, order::Symbol) = (@inline; getfield(x, f, order))
setproperty!(x::Tuple, f::Int, v, order::Symbol) = setfield!(x, f, v, order) # to get a decent error

getproperty(x, f::Symbol, order::Symbol) = (@inline; getfield(x, f, order))
function setproperty!(x, f::Symbol, v, order::Symbol)
    @inline
    ty = fieldtype(typeof(x), f)
    val = v isa ty ? v : convert(ty, v)
    return setfield!(x, f, val, order)
end

function swapproperty!(x, f::Symbol, v, order::Symbol=:not_atomic)
    @inline
    ty = fieldtype(typeof(x), f)
    val = v isa ty ? v : convert(ty, v)
    return Core.swapfield!(x, f, val, order)
end
function modifyproperty!(x, f::Symbol, op, v, order::Symbol=:not_atomic)
    @inline
    return Core.modifyfield!(x, f, op, v, order)
end
function replaceproperty!(x, f::Symbol, expected, desired, success_order::Symbol=:not_atomic, fail_order::Symbol=success_order)
    @inline
    ty = fieldtype(typeof(x), f)
    val = desired isa ty ? desired : convert(ty, desired)
    return Core.replacefield!(x, f, expected, val, success_order, fail_order)
end

convert(::Type{Any}, Core.@nospecialize x) = x
convert(::Type{T}, x::T) where {T} = x
include("coreio.jl")

eval(x) = Core.eval(Base, x)
eval(m::Module, x) = Core.eval(m, x)

# init core docsystem
import Core: @doc, @__doc__, WrappedException, @int128_str, @uint128_str, @big_str, @cmd
if isdefined(Core, :Compiler)
    import Core.Compiler.CoreDocs
    Core.atdoc!(CoreDocs.docm)
end

include("exports.jl")

if false
    # simple print definitions for debugging. enable these if something
    # goes wrong during bootstrap before printing code is available.
    # otherwise, they just just eventually get (noisily) overwritten later
    global show, print, println
    show(io::IO, x) = Core.show(io, x)
    print(io::IO, a...) = Core.print(io, a...)
    println(io::IO, x...) = Core.println(io, x...)
end

"""
    time_ns() -> UInt64

Get the time in nanoseconds. The time corresponding to 0 is undefined, and wraps every 5.8 years.
"""
time_ns() = ccall(:jl_hrtime, UInt64, ())

start_base_include = time_ns()

# A warning to be interpolated in the docstring of every dangerous mutating function in Base, see PR #50824
const _DOCS_ALIASING_WARNING = """
!!! warning
    Behavior can be unexpected when any mutated argument shares memory with any other argument.
"""

## Load essential files and libraries
include("essentials.jl")
include("ctypes.jl")
include("gcutils.jl")
include("generator.jl")
include("reflection.jl")
include("options.jl")

# define invoke(f, T, args...; kwargs...), without kwargs wrapping
# to forward to invoke
function Core.kwcall(kwargs::NamedTuple, ::typeof(invoke), f, T, args...)
    @inline
    # prepend kwargs and f to the invoked from the user
    T = rewrap_unionall(Tuple{Core.Typeof(kwargs), Core.Typeof(f), (unwrap_unionall(T)::DataType).parameters...}, T)
    return invoke(Core.kwcall, T, kwargs, f, args...)
end
# invoke does not have its own call cache, but kwcall for invoke does
setfield!(typeof(invoke).name.mt, :max_args, 3, :monotonic) # invoke, f, T, args...

# define applicable(f, T, args...; kwargs...), without kwargs wrapping
# to forward to applicable
function Core.kwcall(kwargs::NamedTuple, ::typeof(applicable), @nospecialize(args...))
    @inline
    return applicable(Core.kwcall, kwargs, args...)
end
function Core._hasmethod(@nospecialize(f), @nospecialize(t)) # this function has a special tfunc (TODO: make this a Builtin instead like applicable)
    tt = rewrap_unionall(Tuple{Core.Typeof(f), (unwrap_unionall(t)::DataType).parameters...}, t)
    return Core._hasmethod(tt)
end


# core operations & types
include("promotion.jl")
include("tuple.jl")
include("expr.jl")
include("pair.jl")
include("traits.jl")
include("range.jl")
include("error.jl")

# core numeric operations & types
==(x, y) = x === y
include("bool.jl")
include("number.jl")
include("int.jl")
include("operators.jl")
include("pointer.jl")
include("refvalue.jl")
include("cmem.jl")
include("refpointer.jl")

# now replace the Pair constructor (relevant for NamedTuples) with one that calls our Base.convert
delete_method(which(Pair{Any,Any}, (Any, Any)))
@eval function (P::Type{Pair{A, B}})(@nospecialize(a), @nospecialize(b)) where {A, B}
    @inline
    return $(Expr(:new, :P, :(a isa A ? a : convert(A, a)), :(b isa B ? b : convert(B, b))))
end

# The REPL stdlib hooks into Base using this Ref
const REPL_MODULE_REF = Ref{Module}()

include("checked.jl")
using .Checked
function cld end
function fld end

# Lazy strings
include("strings/lazy.jl")

# array structures
include("indices.jl")
include("genericmemory.jl")
include("array.jl")
include("abstractarray.jl")
include("subarray.jl")
include("views.jl")
include("baseext.jl")

include("c.jl")
include("ntuple.jl")
include("abstractdict.jl")
include("iddict.jl")
include("idset.jl")
include("iterators.jl")
using .Iterators: zip, enumerate, only
using .Iterators: Flatten, Filter, product  # for generators
using .Iterators: Stateful    # compat (was formerly used in reinterpretarray.jl)
include("namedtuple.jl")

# For OS specific stuff
# We need to strcat things here, before strings are really defined
function strcat(x::String, y::String)
    out = ccall(:jl_alloc_string, Ref{String}, (Csize_t,), Core.sizeof(x) + Core.sizeof(y))
    GC.@preserve x y out begin
        out_ptr = unsafe_convert(Ptr{UInt8}, out)
        unsafe_copyto!(out_ptr, unsafe_convert(Ptr{UInt8}, x), Core.sizeof(x))
        unsafe_copyto!(out_ptr + Core.sizeof(x), unsafe_convert(Ptr{UInt8}, y), Core.sizeof(y))
    end
    return out
end
include(strcat((length(Core.ARGS)>=2 ? Core.ARGS[2] : ""), "build_h.jl"))     # include($BUILDROOT/base/build_h.jl)
include(strcat((length(Core.ARGS)>=2 ? Core.ARGS[2] : ""), "version_git.jl")) # include($BUILDROOT/base/version_git.jl)
# Initialize DL_LOAD_PATH as early as possible.  We are defining things here in
# a slightly more verbose fashion than usual, because we're running so early.
const DL_LOAD_PATH = String[]
let os = ccall(:jl_get_UNAME, Any, ())
    if os === :Darwin || os === :Apple
        if Base.DARWIN_FRAMEWORK
            push!(DL_LOAD_PATH, "@loader_path/Frameworks")
        end
        push!(DL_LOAD_PATH, "@loader_path")
    end
end

# numeric operations
include("hashing.jl")
include("rounding.jl")
include("div.jl")
include("rawbigints.jl")
include("float.jl")
include("twiceprecision.jl")
include("complex.jl")
include("rational.jl")
include("multinverses.jl")
using .MultiplicativeInverses
include("abstractarraymath.jl")
include("arraymath.jl")
include("slicearray.jl")

# SIMD loops
sizeof(s::String) = Core.sizeof(s)  # needed by gensym as called from simdloop
include("simdloop.jl")
using .SimdLoop

# map-reduce operators
include("reduce.jl")

## core structures
include("reshapedarray.jl")
include("reinterpretarray.jl")
include("bitarray.jl")
include("bitset.jl")

if !isdefined(Core, :Compiler)
    include("docs/core.jl")
    Core.atdoc!(CoreDocs.docm)
end

include("multimedia.jl")
using .Multimedia

# Some type
include("some.jl")

include("dict.jl")
include("abstractset.jl")
include("set.jl")

# Strings
include("char.jl")
function array_new_memory(mem::Memory{UInt8}, newlen::Int)
    # add an optimization to array_new_memory for StringVector
    if (@assume_effects :total @ccall jl_genericmemory_owner(mem::Any,)::Any) isa String
        # If data is in a String, keep it that way.
        # When implemented, this could use jl_gc_expand_string(oldstr, newlen) as an optimization
        str = _string_n(newlen)
        return (@assume_effects :total !:consistent @ccall jl_string_to_genericmemory(str::Any,)::Memory{UInt8})
    else
        # TODO: when implemented, this should use a memory growing call
        return typeof(mem)(undef, newlen)
    end
end
include("strings/basic.jl")
include("strings/string.jl")
include("strings/substring.jl")
include("strings/cstring.jl")

include("osutils.jl")

# Core I/O
include("io.jl")
include("iobuffer.jl")

# strings & printing
include("intfuncs.jl")
include("strings/strings.jl")
include("regex.jl")
include("parse.jl")
include("shell.jl")
include("show.jl")
include("arrayshow.jl")
include("methodshow.jl")

# multidimensional arrays
include("cartesian.jl")
using .Cartesian
include("multidimensional.jl")

include("broadcast.jl")
using .Broadcast
using .Broadcast: broadcasted, broadcasted_kwsyntax, materialize, materialize!,
                  broadcast_preserving_zero_d, andand, oror

# missing values
include("missing.jl")

# version
include("version.jl")

# Concurrency (part 1)
include("linked_list.jl")
include("condition.jl")
include("threads.jl")
include("lock.jl")

# system & environment
include("sysinfo.jl")
include("libc.jl")
using .Libc: getpid, gethostname, time, memcpy, memset, memmove, memcmp

# These used to be in build_h.jl and are retained for backwards compatibility.
# NOTE: keep in sync with `libblastrampoline_jll.libblastrampoline`.
const libblas_name = "libblastrampoline" * (Sys.iswindows() ? "-5" : "")
const liblapack_name = libblas_name

# Concurrency (part 2)
# Note that `atomics.jl` here should be deprecated
Core.eval(Threads, :(include("atomics.jl")))
include("channels.jl")
include("partr.jl")
include("task.jl")
include("threads_overloads.jl")
include("weakkeydict.jl")

# ScopedValues
include("scopedvalues.jl")
using .ScopedValues

# Logging
include("logging.jl")
using .CoreLogging

include("env.jl")

# functions defined in Random
function rand end
function randn end

# I/O
include("libuv.jl")
include("asyncevent.jl")
include("iostream.jl")
include("stream.jl")
include("filesystem.jl")
using .Filesystem
include("cmd.jl")
include("process.jl")
include("terminfo.jl")
include("secretbuffer.jl")

# core math functions
include("floatfuncs.jl")
include("math.jl")
using .Math
const (√)=sqrt
const (∛)=cbrt
const (∜)=fourthroot

# now switch to a simple, race-y TLS, relative include for the rest of Base
delete_method(which(include, (Module, String)))
let SOURCE_PATH = ""
    global function include(mod::Module, path::String)
        prev = SOURCE_PATH::String
        path = normpath(joinpath(dirname(prev), path))
        Core.println(path)
        ccall(:jl_uv_flush, Nothing, (Ptr{Nothing},), Core.io_pointer(Core.stdout))
        push!(_included_files, (mod, abspath(path)))
        SOURCE_PATH = path
        result = Core.include(mod, path)
        SOURCE_PATH = prev
        return result
    end
end

# reduction along dims
include("reducedim.jl")  # macros in this file rely on string.jl
include("accumulate.jl")

include("permuteddimsarray.jl")
using .PermutedDimsArrays

# basic data structures
include("ordering.jl")
using .Order

# Combinatorics
include("sort.jl")
using .Sort

# BinaryPlatforms, used by Artifacts.  Needs `Sort`.
include("binaryplatforms.jl")

# Fast math
include("fastmath.jl")
using .FastMath

function deepcopy_internal end

# enums
include("Enums.jl")
using .Enums

# BigInts
include("gmp.jl")
using .GMP

# float printing: requires BigInt
include("ryu/Ryu.jl")
using .Ryu

# BigFloats
include("mpfr.jl")
using .MPFR

include("combinatorics.jl")

# irrational mathematical constants
include("irrationals.jl")
include("mathconstants.jl")
using .MathConstants: ℯ, π, pi

# metaprogramming
include("meta.jl")

# Stack frames and traces
include("stacktraces.jl")
using .StackTraces

# experimental API's
include("experimental.jl")

# utilities
include("deepcopy.jl")
include("download.jl")
include("summarysize.jl")
include("errorshow.jl")

include("initdefs.jl")

# worker threads
include("threadcall.jl")

# code loading
include("uuid.jl")
include("pkgid.jl")
include("toml_parser.jl")
include("linking.jl")
include("loading.jl")

# misc useful functions & macros
include("timing.jl")
include("util.jl")
include("client.jl")
include("asyncmap.jl")

# deprecated functions
include("deprecated.jl")
#
# Some additional basic documentation
include("docs/basedocs.jl")

# Documentation -- should always be included last in sysimg.
include("docs/Docs.jl")
using .Docs
if isdefined(Core, :Compiler) && is_primary_base_module
    Docs.loaddocs(Core.Compiler.CoreDocs.DOCS)
end

# finally, now make `include` point to the full version
for m in methods(include)
    delete_method(m)
end

# This method is here only to be overwritten during the test suite to test
# various sysimg related invalidation scenarios.
a_method_to_overwrite_in_test() = inferencebarrier(1)

# These functions are duplicated in client.jl/include(::String) for
# nicer stacktraces. Modifications here have to be backported there
include(mod::Module, _path::AbstractString) = _include(identity, mod, _path)
include(mapexpr::Function, mod::Module, _path::AbstractString) = _include(mapexpr, mod, _path)

# External libraries vendored into Base
Core.println("JuliaSyntax/src/JuliaSyntax.jl")
include(@__MODULE__, string((length(Core.ARGS)>=2 ? Core.ARGS[2] : ""), "JuliaSyntax/src/JuliaSyntax.jl")) # include($BUILDROOT/base/JuliaSyntax/JuliaSyntax.jl)

end_base_include = time_ns()

const _sysimage_modules = PkgId[]
in_sysimage(pkgid::PkgId) = pkgid in _sysimage_modules

# Precompiles for Revise and other packages
# TODO: move these to contrib/generate_precompile.jl
# The problem is they don't work there
for match = _methods(+, (Int, Int), -1, get_world_counter())
    m = match.method
    delete!(push!(Set{Method}(), m), m)
    copy(Core.Compiler.retrieve_code_info(Core.Compiler.specialize_method(match), typemax(UInt)))

    empty!(Set())
    push!(push!(Set{Union{GlobalRef,Symbol}}(), :two), GlobalRef(Base, :two))
    (setindex!(Dict{String,Base.PkgId}(), Base.PkgId(Base), "file.jl"))["file.jl"]
    (setindex!(Dict{Symbol,Vector{Int}}(), [1], :two))[:two]
    (setindex!(Dict{Base.PkgId,String}(), "file.jl", Base.PkgId(Base)))[Base.PkgId(Base)]
    (setindex!(Dict{Union{GlobalRef,Symbol}, Vector{Int}}(), [1], :two))[:two]
    (setindex!(IdDict{Type, Union{Missing, Vector{Tuple{LineNumberNode, Expr}}}}(), missing, Int))[Int]
    Dict{Symbol, Union{Nothing, Bool, Symbol}}(:one => false)[:one]
    Dict(Base => [:(1+1)])[Base]
    Dict(:one => [1])[:one]
    Dict("abc" => Set())["abc"]
    pushfirst!([], sum)
    get(Base.pkgorigins, Base.PkgId(Base), nothing)
    sort!([1,2,3])
    unique!([1,2,3])
    cumsum([1,2,3])
    append!(Int[], BitSet())
    isempty(BitSet())
    delete!(BitSet([1,2]), 3)
    deleteat!(Int32[1,2,3], [1,3])
    deleteat!(Any[1,2,3], [1,3])
    Core.svec(1, 2) == Core.svec(3, 4)
    any(t->t[1].line > 1, [(LineNumberNode(2,:none), :(1+1))])

    # Code loading uses this
    sortperm(mtime.(readdir(".")), rev=true)
    # JLLWrappers uses these
    Dict{UUID,Set{String}}()[UUID("692b3bcd-3c85-4b1f-b108-f13ce0eb3210")] = Set{String}()
    get!(Set{String}, Dict{UUID,Set{String}}(), UUID("692b3bcd-3c85-4b1f-b108-f13ce0eb3210"))
    eachindex(IndexLinear(), Expr[])
    push!(Expr[], Expr(:return, false))
    vcat(String[], String[])
    k, v = (:hello => nothing)
    precompile(indexed_iterate, (Pair{Symbol, Union{Nothing, String}}, Int))
    precompile(indexed_iterate, (Pair{Symbol, Union{Nothing, String}}, Int, Int))
    # Preferences uses these
    precompile(get_preferences, (UUID,))
    precompile(record_compiletime_preference, (UUID, String))
    get(Dict{String,Any}(), "missing", nothing)
    delete!(Dict{String,Any}(), "missing")
    for (k, v) in Dict{String,Any}()
        println(k)
    end

    break   # only actually need to do this once
end

if is_primary_base_module

# Profiling helper
# triggers printing the report and (optionally) saving a heap snapshot after a SIGINFO/SIGUSR1 profile request
# Needs to be in Base because Profile is no longer loaded on boot
const PROFILE_PRINT_COND = Ref{Base.AsyncCondition}()
function profile_printing_listener()
    profile = nothing
    try
        while true
            wait(PROFILE_PRINT_COND[])
            profile = @something(profile, require(PkgId(UUID("9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"), "Profile")))

            invokelatest(profile.peek_report[])
            if Base.get_bool_env("JULIA_PROFILE_PEEK_HEAP_SNAPSHOT", false) === true
                println(stderr, "Saving heap snapshot...")
                fname = invokelatest(profile.take_heap_snapshot)
                println(stderr, "Heap snapshot saved to `$(fname)`")
            end
        end
    catch ex
        if !isa(ex, InterruptException)
            @error "Profile printing listener crashed" exception=ex,catch_backtrace()
        end
    end
end

function __init__()
    # Base library init
    reinit_stdio()
    Multimedia.reinit_displays() # since Multimedia.displays uses stdout as fallback
    # initialize loading
    init_depot_path()
    init_load_path()
    init_active_project()
    append!(empty!(_sysimage_modules), keys(loaded_modules))
    if haskey(ENV, "JULIA_MAX_NUM_PRECOMPILE_FILES")
        MAX_NUM_PRECOMPILE_FILES[] = parse(Int, ENV["JULIA_MAX_NUM_PRECOMPILE_FILES"])
    end
    # Profiling helper
    @static if !Sys.iswindows()
        # triggering a profile via signals is not implemented on windows
        cond = Base.AsyncCondition()
        Base.uv_unref(cond.handle)
        PROFILE_PRINT_COND[] = cond
        ccall(:jl_set_peek_cond, Cvoid, (Ptr{Cvoid},), PROFILE_PRINT_COND[].handle)
        errormonitor(Threads.@spawn(profile_printing_listener()))
    end
    _require_world_age[] = get_world_counter()
    # Prevent spawned Julia process from getting stuck waiting on Tracy to connect.
    delete!(ENV, "JULIA_WAIT_FOR_TRACY")
    if get_bool_env("JULIA_USE_FLISP_PARSER", false) === false
        JuliaSyntax.enable_in_core!()
    end
    nothing
end

# enable threads support
@eval PCRE PCRE_COMPILE_LOCK = Threads.SpinLock()

end

# Ensure this file is also tracked
@assert !isassigned(_included_files, 1)
_included_files[1] = (parentmodule(Base), abspath(@__FILE__))

end # baremodule Base
