module CuArrays

using CUDAdrv, CUDAnative

using GPUArrays

export CuArray, CuVector, CuMatrix, CuVecOrMat, cu

import LinearAlgebra

using Adapt

using Requires

const ext = joinpath(dirname(@__DIR__), "deps", "ext.jl")
isfile(ext) || error("CuArrays.jl has not been built, please run Pkg.build(\"CuArrays\").")
include(ext)
if !configured
    # default (non-functional) values for critical variables,
    # making it possible to _load_ the package at all times.
    const libcublas = nothing
    const libcusparse = nothing
    const libcusolver = nothing
    const libcufft = nothing
    const libcurand = nothing
    const libcudnn = nothing
end

include("memory.jl")
include("array.jl")
include("subarray.jl")
include("permuteddimsarray.jl")
include("utils.jl")
include("indexing.jl")
include("broadcast.jl")
include("matmul.jl")
include("mapreduce.jl")
include("accumulate.jl")

include("gpuarray_interface.jl")

# many libraries need to be initialized per-device (per-context, really, but we assume users
# of CuArrays and/or CUDAnative only use a single context), so keep track of the active one.
const active_context = Ref{CuContext}()

include("blas/CUBLAS.jl")
include("sparse/CUSPARSE.jl")
include("solver/CUSOLVER.jl")
include("fft/CUFFT.jl")
include("rand/CURAND.jl")
libcudnn !== nothing && include("dnn/CUDNN.jl")

include("nnlib.jl")

include("deprecated.jl")

function __init__()
    if !configured
        @warn("CuArrays.jl has not been successfully built, and will not work properly.")
        @warn("Please run Pkg.build(\"CuArrays\") and restart Julia.")
        return
    end

    function check_library(name, path)
        path === nothing && return
        if !ispath(path)
            error("$name library has changed. Please run Pkg.build(\"CuArrays\") and restart Julia.")
        end
    end
    check_library("CUBLAS", libcublas)
    check_library("CUSPARSE", libcusparse)
    check_library("CUSOLVER", libcusolver)
    check_library("CUFFT", libcufft)
    check_library("CURAND", libcurand)
    check_library("CUDNN", libcudnn)

    # package integrations
    @require ForwardDiff="f6369f11-7733-5829-9624-2563aa707210" include("forwarddiff.jl")

    # update the active context when we switch devices
    callback = (::CuDevice, ctx::CuContext) -> begin
        active_context[] = ctx

        # wipe the active handles
        CUBLAS._handle[] = C_NULL
        CUBLAS._xt_handle[] = C_NULL
        CUSOLVER._dense_handle[] = C_NULL
        CUSOLVER._sparse_handle[] = C_NULL
        CUSPARSE._handle[] = C_NULL
        CURAND._generator[] = nothing
        isdefined(CuArrays, :CUDNN) && (CUDNN._handle[] = C_NULL)
    end
    push!(CUDAnative.device!_listeners, callback)

    # a device might be active already
    existing_ctx = CUDAdrv.CuCurrentContext()
    if existing_ctx !== nothing
        active_context[] = existing_ctx
    end

    __init_memory__()
    __init_pool_()
end

end # module
