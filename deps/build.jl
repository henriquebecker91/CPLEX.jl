using Libdl

const _DEPS_FILE = joinpath(dirname(@__FILE__), "deps.jl")
if isfile(_DEPS_FILE)
    rm(_DEPS_FILE)
end

function write_depsfile(path)
    open(_DEPS_FILE, "w") do f
        println(f, "const libcplex = \"$(escape_string(path))\"")
    end
end

function library_name(v)
    cpx_prefix = Sys.iswindows() ? "" : "lib"
    return "$(cpx_prefix)cplex$(v).$(Libdl.dlext)"
end

function possible_path(cplex_studio_path::AbstractString)
    if Sys.iswindows()
        return escape_string("C:\\Program Files\\IBM\\ILOG\\$cplex_studio_path\\cplex\\bin\\x64_win64\\")
    elseif Sys.isapple()
        return "/Applications/$cplex_studio_path/cplex/bin/x86-64_osx/"
    else
        return "/opt/$cplex_studio_path/cplex/bin/x86-64_linux/"
    end
end

function get_error_message_if_not_found()
    return """
    Unable to install CPLEX.jl.

    The versions of CPLEX supported by CPLEX.jl are:

    * 12.10
    * 20.1

    You must download and install one of these versions separately.

    You should set the `CPLEX_STUDIO_BINARIES` environment variable to point to
    the install location then try again. For example (updating the path to the
    correct location if needed):
    
    ```
    ENV["CPLEX_STUDIO_BINARIES"] = "$(possible_path("CPLEX_Studio201"))"
    import Pkg
    Pkg.add("CPLEX")
    Pkg.build("CPLEX")
    ```

    See the CPLEX.jl README at https://github.com/jump-dev/CPLEX.jl for further
    instructions.
    """
end

function try_local_installation()
    # Find the path to the CPLEX executable.
    cplex_path = try
        @static if Sys.isapple() || Sys.isunix()
            dirname(strip(read(`which cplex`, String)))
        elseif Sys.iswindows()
            dirname(strip(read(`where cplex`, String)))
        end
    catch
        nothing
    end

    # Iterate through a series of places where CPLEX could be found: either in
    # the path (directly the callable library or the CPLEX executable) or from
    # an environment variable.
    cpxvers = [
        "1210", "12100",
        "201", "2010", "20100",
    ]
    base_env = "CPLEX_STUDIO_BINARIES"

    libnames = String["cplex"]
    for v in reverse(cpxvers)
        name = library_name(v)
        push!(libnames, name)
        if cplex_path !== nothing
            push!(libnames, joinpath(cplex_path, name))
        end
        for env in [base_env, base_env * v]
            if !haskey(ENV, env)
                continue
            end
            for d in split(ENV[env], ';')
                push!(libnames, joinpath(d, name))
            end
        end
        
        for product in ["CPLEX_Studio$v", "CPLEX_Enterprise_Server$v/CPLEX_Studio"]
            guessed_file = joinpath(possible_path(product), name)
            if isfile(guessed_file)
                push!(libnames, guessed_file)
            end
        end
    end

    # Perform the actual search in the potential places.
    for l in libnames
        d = Libdl.dlopen_e(l)
        if d == C_NULL
            continue
        end
        write_depsfile(Libdl.dlpath(d))
        @info("Using CPLEX found in location `$(l)`")
        return
    end
    
    error(get_error_message_if_not_found())
end

function try_ci_installation()
    CPLEX_VERSION = ENV["CPLEX_VERSION"]
    url = ENV["SECRET_CPLEX_URL_" * CPLEX_VERSION]
    local_filename = joinpath(@__DIR__, "libcplex.so")
    download(url, local_filename)
    write_depsfile(local_filename)
end

if get(ENV, "JULIA_REGISTRYCI_AUTOMERGE", "false") == "true"
    # We need to be able to install and load this package without error for
    # Julia's registry AutoMerge to work. Just write a fake libcplex path.
    write_depsfile("julia_registryci_automerge")
elseif get(ENV, "SECRET_CPLEX_URL_12100", "") != ""
    try_ci_installation()
else
    try_local_installation()
end
