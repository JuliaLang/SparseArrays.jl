module TestDepsUtils

import Pkg

# Base Julia's Buildkite CI doesn't run stdlib tests
# via `Pkg.test`. Therefore, test deps must be manually
# installed if missing.
#
# The `force_install` kwarg is only used for debugging.
function install_all_test_deps(; force_install::Bool = false)
    project = nothing
    for pkg_name in get_test_deps()
        (; project) = install_single_test_dep(
            pkg_name;
            project,
            force_install,
        )
    end
    return nothing
end

function install_single_test_dep(
    pkg_name::AbstractString;
    project::Union{AbstractString, Nothing},
    force_install::Bool,
)
    pkg_uuid_str = get_uuid_str(pkg_name)
    pkg_compat = get_compat(pkg_name)
    pkg_spec = Pkg.PackageSpec(;
        name = pkg_name,
        version = pkg_compat, # make sure we respect the `[compat]` entry
        uuid = pkg_uuid_str,
    )

    found_package = Base.find_package(pkg_name)

    if (found_package === nothing) || force_install
        if project === nothing
            Pkg.activate(; temp = true)
            project = Base.active_project()
            @debug "Activated a new temp project at $(project)"
        end
        @debug "Installing $(pkg_name).jl"
        iob = IOBuffer()
        try
            # To keep the logs (the Base Julia Buildkite CI logs) clean,
            # we don't print the Pkg output to the log unless the `Pkg.add`
            # fails. Therefore, we pass `io = iob`.
            Pkg.add(pkg_spec; io = iob)
        catch
            println(String(take!(iob)))
            rethrow()
        end
    else
        @debug "Found $(pkg_name).jl" found_package
    end

    return (; project)
end

function get_project_dict()
    root_test = @__DIR__ # ./test/
    root = dirname(root_test) # ./
    project_filename = joinpath(root, "Project.toml") # ./Project.toml
    project_dict = Pkg.TOML.parsefile(project_filename)
    return project_dict
end

function get_testprojecttoml_dict()
    root_test = @__DIR__ # ./test/
    testprojecttoml_filename = joinpath(root_test, "Project.toml") # ./test/Project.toml
    if ispath(testprojecttoml_filename)
        testprojecttoml_dict = Pkg.TOML.parsefile(project_filename)
    else
        # It is totally fine if the `./test/Project.toml` file doesn't exist.
        testprojecttoml_dict = Dict()
    end
    return testprojecttoml_dict
end

function get_test_deps()
    project_dict = get_project_dict()
    targets_section = get(project_dict, "targets", Dict())
    test_target_list = get(targets_section, "test", [])

    testprojecttoml_dict = get_testprojecttoml_dict()
    testprojecttoml_deps_section = get(testprojecttoml_dict, "deps", Dict())

    if isempty(test_target_list) && isempty(testprojecttoml_deps_section)
        # We require that at least one of the following conditions is true:
        # 1. The main `Project.toml` has a non-empty test target.
        # 2. `test/Project.toml` exists and has a non-empty `[deps]` section.
        #
        # After all, we know that this repo has at least one test dependency, namely
        # Test. So that test dependency has to be listed somewhere.
        error("Could not find any test dependencies in either Project.toml or test/Project.toml")
    end

    all_test_deps = vcat(
        test_target_list,
        collect(keys(testprojecttoml_deps_section)),
    )
    return sort(unique(all_test_deps))
end

function get_uuid_str(pkg_name::AbstractString)
    project_dict = get_project_dict()
    deps_section = get(project_dict, "deps", Dict())
    extras_section = get(project_dict, "extras", Dict())

    testprojecttoml_dict = get_testprojecttoml_dict()
    testprojecttoml_deps_section = get(testprojecttoml_dict, "deps", Dict())

    if haskey(deps_section, pkg_name)
        # First, check `[deps]` in Project.toml
        pkg_uuid_str = deps_section[pkg_name]
    elseif haskey(extras_section, pkg_name)
        # Next, check `[extras]` in Project.toml
        pkg_uuid_str = extras_section[pkg_name]
    else
        # Finally, we assume it's in the `[deps]` in test/Project.toml
        pkg_uuid_str = testprojecttoml_deps_section[pkg_name]
    end

    return pkg_uuid_str
end

# Suppose that the compat entry looks like this:
#
# ```
# [compat]
# PkgName = "1.1, 2.2, 3.3"
# ````
#
# In this case, if we pass the string "1.1, 2.2, 3.3" as the value of
# `version` when doing `Pkg.add(; name, uuid, version)`, Pkg will throw an
# error, because it doesn't like the commas. So, we need to parse the
# string "1.1, 2.2, 3.3" into a `Pkg.Types.VersionSpec`, which Pkg will then
# accept as the value of `version`.
function get_compat(pkg_name::AbstractString)
    pkg_compat_str = _get_compat_str(pkg_name)
    pkg_compat_versionspec = parse_compat_entry(pkg_compat_str)

    return pkg_compat_versionspec
end

function _get_compat_str(pkg_name::AbstractString)
    project_dict = get_project_dict()
    compat_section = get(project_dict, "compat", Dict())

    testprojecttoml_dict = get_testprojecttoml_dict()
    testprojecttomlcompat_section = get(testprojecttoml_dict, "compat", Dict())

    if haskey(compat_section, pkg_name)
        # First, check `[compat]` in Project.toml
        pkg_compat_str = compat_section[pkg_name]
    else
        # Finally, we assume it's in the `[compat]` in test/Project.toml
        pkg_compat_str = testprojecttomlcompat_section[pkg_name]
    end

    return pkg_compat_str
end

# The `parse_compat_entry` function uses Pkg internals. Therefore,
# we might need to have different versions of `parse_compat_entry`
# for different minor versions of Julia.
function parse_compat_entry end
@static if VERSION >= v"1.0.0-"
    parse_compat_entry(pkg_compat_str) = Pkg.Types.semver_spec(pkg_compat_str)
else
    error("Unsupported Julia version: $(VERSION)")
end

end # module
