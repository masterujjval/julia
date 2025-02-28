Julia v1.11 Release Notes
========================

New language features
---------------------
* `public` is a new keyword. Symbols marked with `public` are considered public
  API. Symbols marked with `export` are now also treated as public API. The
  difference between `public` and `export` is that `public` names do not become
  available when `using` a package/module ([#50105]).
* `ScopedValue` implement dynamic scope with inheritance across tasks ([#50958]).
* The new macro `Base.Cartesian.@ncallkw` is analogous to `Base.Cartesian.@ncall`,
  but allows to add keyword arguments to the function call ([#51501]).
* Support for Unicode 15.1 ([#51799]).
* A new `AbstractString` type, `AnnotatedString`, is introduced that allows for
  regional annotations to be attached to an underlying string. This type is
  particularly useful for holding styling information, and is used extensively
  in the new `StyledStrings` standard library. There is also a new `AnnotatedChar`
  type, that is the equivalent new `AbstractChar` type.

Language changes
----------------

Compiler/Runtime improvements
-----------------------------
* Updated GC heuristics to count allocated pages instead of individual objects ([#50144]).
* A new `LazyLibrary` type is exported from `Libdl` for use in building chained lazy library
  loads, primarily to be used within JLLs ([#50074]).

Command-line option changes
---------------------------

* The entry point for Julia has been standardized to `Main.main(ARGS)`. This must be explicitly opted into using the `@main` macro
(see the docstring for further details). When opted-in, and julia is invoked to run a script or expression
(i.e. using `julia script.jl` or `julia -e expr`), julia will subsequently run the `Main.main` function automatically.
This is intended to unify script and compilation workflows, where code loading may happen
in the compiler and execution of `Main.main` may happen in the resulting executable. For interactive use, there is no semantic
difference between defining a `main` function and executing the code directly at the end of the script ([50974]).

Multi-threading changes
-----------------------

Build system changes
--------------------

New library functions
---------------------

* The new `Libc.mkfifo` function wraps the `mkfifo` C function on Unix platforms ([#34587]).
* `hardlink(src, dst)` can be used to create hard links ([#41639]).
* `diskstat(path=pwd())` can be used to return statistics about the disk ([#42248]).
* `copyuntil(out, io, delim)` and `copyline(out, io)` copy data into an `out::IO` stream ([#48273]).
* `eachrsplit(string, pattern)` iterates split substrings right to left.
* `Sys.username()` can be used to return the current user's username ([#51897]).

New library features
--------------------
* `replace(string, pattern...)` now supports an optional `IO` argument to
  write the output to a stream rather than returning a string ([#48625]).
* `sizehint!(s, n)` now supports an optional `shrink` argument to disable shrinking ([#51929]).

Standard library changes
------------------------

#### StyledStrings

* A new standard library for handling styling in a more comprehensive and structured way ([#49586]).
* The new `Faces` struct serves as a container for text styling information
  (think typeface, as well as color and decoration), and comes with a framework
  to provide a convenient, extensible (via `addface!`), and customisable (with a
  user's `Faces.toml` and `loadfaces!`) approach to
  styled content ([#49586]).
* The new `@styled_str` string macro provides a convenient way of creating a
  `AnnotatedString` with various faces or other attributes applied ([#49586]).

#### Package Manager

#### LinearAlgebra

#### Printf

#### Profile

#### Random
* `rand` now supports sampling over `Tuple` types ([#35856], [#50251]).
* `rand` now supports sampling over `Pair` types ([#28705]).
* When seeding RNGs provided by `Random`, negative integer seeds can now be used ([#51416]).
* Seedable random number generators from `Random` can now be seeded by a string, e.g.
  `seed!(rng, "a random seed")` ([#51527]).

#### REPL

* Tab complete hints now show in lighter text while typing in the repl. To disable
  set `Base.active_repl.options.hint_tab_completes = false` ([#51229]).
* Meta-M with an empty prompt now returns the contextual module of the REPL to `Main`.

#### SuiteSparse


#### SparseArrays

#### Test

#### Dates

#### Statistics

* Statistics is now an upgradeable standard library ([#46501]).

#### Distributed

* `pmap` now defaults to using a `CachingPool` ([#33892]).

#### Unicode


#### DelimitedFiles


#### InteractiveUtils

Deprecated or removed
---------------------


External dependencies
---------------------
* `tput` is no longer called to check terminal capabilities, it has been replaced with a pure-Julia terminfo parser ([#50797]).

Tooling Improvements
--------------------

* CI now performs limited automatic typo detection on all PRs. If you merge a PR with a
  failing typo CI check, then the reported typos will be automatically ignored in future CI
  runs on PRs that edit those same files ([#51704]).

<!--- generated by NEWS-update.jl: -->
