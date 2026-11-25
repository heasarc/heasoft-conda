# AGENTS.md

## Repository Purpose

This repository builds conda packages for HEASoft and related software with
`rattler-build`. It also contains tooling for creating the upstream source
archives consumed by the recipes.

The tracked package directories are `heasoft`, `heasoft-tests`, `xspec`,
`xspec-compilers`, `xspec-data`, `xstar-data`, `fv`, and `fviewer`. Each package
is defined primarily by `recipe.yaml`; compiled packages may also have a
`build.sh` and local patch files.

## Source Of Truth

- Prefer the current recipes and build scripts over package lists or version
  examples in `README.md`, which may lag behind active recipes.
- Keep package versions, source URLs, SHA-256 hashes, dependency constraints,
  and build numbers consistent when changing a release.
- Treat `variants.yaml` as the single source of truth for shared HEASoft and
  XSPEC release numbers and compiler versions. Keep compiler helpers
  unversioned in recipes so related packages resolve the same toolchain.
- Patches in `heasoft/` may also describe behavior used by the related HEASoft
  source builds. Preserve patch paths and ordering unless the upstream source
  change requires otherwise.

## Build Workflow

Install the build tool in a conda or micromamba environment:

```sh
mamba install rattler-build
```

Run a package build from its package directory:

```sh
cd <package>
../scripts/run_build.sh
```

Resolve dependencies without running a build or creating a package:

```sh
../scripts/run_build.sh --resolve-only
```

Select a target platform for either mode:

```sh
../scripts/run_build.sh --target-platform <platform>
../scripts/run_build.sh --resolve-only --target-platform <platform>
```

From the repository root, update `variants.yaml` to the latest compiler versions
common to all supported architectures (`micromamba`, `jq`, and network access
are required):

```sh
./scripts/update_compiler_versions.sh
```

The equivalent command is:

```sh
rattler-build build --variant-config ../variants.yaml \
  --no-include-recipe --output-dir ../output
```

Supported CI targets are `linux-64`, `linux-aarch64`, `osx-64`, and
`osx-arm64`.

```sh
rattler-build build --variant-config ../variants.yaml --no-include-recipe \
  --target-platform <platform> --output-dir ../output
```

When building `heasoft`, build `fviewer` first so that it is available in the
local output channel. The CI workflow also builds `heasoft-tests` from the same
cached HEASoft source archive after a HEASoft build.

For source-archive work, begin with a dry run from the repository root:

```sh
python3 scripts/generate_src_tar.py \
  --package <package> --version <version> --dryrun
```

The non-dry-run command creates a tarball and appends its hash to
`shasums.txt` in the invocation directory. Do not commit these generated files
unless the task explicitly requires them.

## Recipe And Script Conventions

- Use the rattler-build recipe schema and `${{ ... }}` expressions already
  present in the recipes.
- Pin remote sources with SHA-256. Do not replace a hash without verifying the
  exact source archive.
- Keep build-only dependencies under `requirements.host` and installed-package
  dependencies under `requirements.run`.
- Preserve selectors such as `if: linux`, `if: osx`, `aarch64`, and `arm64`.
  Do not assume Linux x86-64 behavior applies to every CI target.
- Change shared release and compiler versions only in `variants.yaml`; do not
  duplicate numeric pins in individual recipes.
- Compiled recipes use Bash build scripts. Follow the existing `$PREFIX`,
  `$CONDA_PREFIX`, `$OSX_ARCH`, and `$SHLIB_EXT` conventions, and avoid tools or
  libraries leaking from the host environment.
- Keep upstream source changes in focused unified-diff patch files rather than
  editing extracted source trees under `output/`.
- Increment `build.number` for packaging-only changes to an already published
  package version.

## Validation

The primary validation is a focused build of the changed package. For noarch
recipes, one platform build is normally sufficient; for selector, compiler,
linker, or shell changes, validate the affected platforms when available.

Do not rely only on the process exit code for HEASoft-family builds. Some
configure, build, install, and test commands deliberately end with `|| false`.
Inspect the emitted logs and package contents for the stage you changed.

Recipe tests are package-specific. For example, `fviewer` verifies its Python
import and runs `pip check`. Preserve or extend focused recipe tests when a
change introduces behavior that can be checked cheaply.

Before finishing:

1. Confirm recipe YAML remains valid and selectors are correctly indented.
2. Build the smallest affected package or explain why the build was not run.
3. Inspect relevant build logs when failures can be suppressed.
4. Check `git diff` for accidental version, hash, build-number, or generated
   artifact changes.

## Generated And External Content

Do not edit or commit generated build content under `output/`, including
`output/bld`, `output/src_cache`, platform package directories, build logs, or
extracted upstream source trees. The ignored `tests/` and `1st_attempt/`
directories are also scratch content, not maintained source.

Do not modify unrelated local artifacts or clean the user's output directory
unless the task explicitly calls for it. Avoid destructive Git operations and
preserve existing worktree changes.