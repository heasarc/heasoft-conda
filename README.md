# HEASoft Conda Packages

This repository contains rattler-build recipes for HEASoft and related conda
packages, along with tooling to create the source archives used by those
recipes.

Our public website advertising our conda packages:  
https://heasarc.gsfc.nasa.gov/docs/software/conda.html

## Current Recipes

The tracked package recipes are:

- `heasoft`: the HEASoft distribution, with `fviewer` as a runtime dependency
- `heasoft-tests`: HEASoft unit-test executables for internal testing; depends
  on the matching `heasoft` version
- `xspec`: the standalone XSPEC spectral-fitting package
- `xspec-compilers`: compilers and `make` for building local XSPEC models
- `xspec-data`: XSPEC model data installed under `heasoft/spectral/modelData`
- `xstar-data`: XSTAR reference data installed under `heasoft/refdata`
- `fv`: the legacy HEASoft FITS viewer
- `fviewer`: the modern browser-based FITS viewer

The recipes and build scripts are the source of truth for current versions and
dependencies.

## Required tools

Conda/mamba may be installed via miniforge. If you don't have conda/mamba installed, it is recommended that you install them through [micromamba](https://mamba.readthedocs.io/en/latest/installation/micromamba-installation.html): 

```sh
"${SHELL}" <(curl -L micro.mamba.pm/install.sh)
```

These builds use [rattler-build](https://github.com/prefix-dev/rattler-build/). If it's not already installed, it can be installed with:

```sh
mamba install rattler-build
```

`rattler-build` is similar to `conda-build`. It is written in rust, which appears to be more robust and easy to use than conda-build.

## Full Lifecycle

The full lifecycle for conda packages, from source code to installation, is:

1. Developer - Creating: Create the source path or archive.
1. Developer - Building: Build the conda package.
1. Developer - Hosting: Copy the conda package to the distribution location.
1. User - Installing: Install the conda package.

## Creating Source

The developer must first create the source code which conda uses to create the package. The source can be a directory or a tarball.

For example, if using a local directory for temporary testing of the develop branch of HEASoft (grabbing a shallow clone, as the history is not important):

```sh
git clone git@sed-gitlab.gsfc.nasa.gov:heasarc/heasoft/heasoft.git --depth 1 heasoft-develop
```

You can also create a source archive to upload for testing, assuming you have
permission to write to the required web directory. For example:

```sh
git clone git@sed-gitlab.gsfc.nasa.gov:heasarc/heasoft/heasoft.git --depth 1 heasoft-6.37.1
tar -zcf heasoft-6.37.1.tar.gz heasoft-6.37.1
sha256sum heasoft-6.37.1.tar.gz # for use in the recipe
scp heasoft-6.37.1.tar.gz gs66-hdev:/www/htdocs/yourdir/conda/
```

The [scripts/generate_src_tar.py](scripts/generate_src_tar.py) script automates
this for the packages defined in
[scripts/package_config.json](scripts/package_config.json). Start with a dry
run from the repository root:

```sh
python3 scripts/generate_src_tar.py \
  --package heasoft --version 6.37.1 --dryrun
```

Without `--dryrun`, the script creates the archive and appends its SHA-256 hash
to `shasums.txt` in the directory where it was invoked. These generated files
should not be committed.


## Building Packages

To build a package, the recipe must be able to find the source code. Edit the `recipe.yaml` file for that package. Be sure the `context:version` matches the version you added to the filename.

For a temporary HEASoft build from a local checkout, change the recipe source:

```yaml
context:
  name: heasoft
  version: develop

source:
  path: /path/to/heasoft-develop
```

For a remote archive, set its URL and verified SHA-256 hash:

```yaml
context:
  name: heasoft
  version: 6.37.1

source:
  url: https://heasarc.gsfc.nasa.gov/yourdir/conda/${{ name }}-${{ version }}.tar.gz
  sha256: c92a03e0ee63a8bc10884e76aab43710621e49afb21b3054445bfc475b4e20fe
```

Call `run_build.sh` from inside the package directory:

```sh
cd xspec
../scripts/run_build.sh
```

To resolve and report dependencies without running the build, use:

```sh
../scripts/run_build.sh --resolve-only
```

This mode passes `--render-only --with-solve` to rattler-build and does not
create a package.

Use `--target-platform` to build or resolve for a specific platform:

```sh
../scripts/run_build.sh --target-platform linux-aarch64
../scripts/run_build.sh --resolve-only --target-platform osx-arm64
```

Use the standalone updater to set `variants.yaml` to the latest compatible
compiler versions available on conda-forge:

```sh
./scripts/update_compiler_versions.sh
```

Run it from the repository root. It requires `micromamba`, `jq`, and network
access, updates the file atomically, and does not build a package. For each
compiler family, it selects the latest version available on every platform
governed by the corresponding variant key. Use `--help` for a summary.

The same file defines `heasoft_version` and `xspec_version`. Related recipes
use these shared values for package versions, source archives, and compatibility
constraints, so update each release number there rather than in each recipe.

Build `fviewer` before `heasoft` so the dependency is available in the local
output channel. CI performs this step automatically for HEASoft builds.

The `run_build.sh` script loads the repository's shared release and compiler
variants and then runs the package build. The equivalent command is:

```sh
rattler-build build --variant-config ../variants.yaml \
  --no-include-recipe --output-dir ../output
```

The package is written beneath `output/` in its target-platform directory.
Build caches are written to `output/bld` and `output/src_cache`. The entire
`output` directory is generated content and should not be committed.

## Hosting Packages

Upload the generated platform directories to the web server. Depending on the
builds performed, these can be `noarch`, `linux-64`, `linux-aarch64`, `osx-64`,
and `osx-arm64`. Release packages are hosted at
`https://heasarcdev.gsfc.nasa.gov/FTP/software/conda/`.

For testing in your own dir:

```sh
cd output
scp -r noarch linux-64 linux-aarch64 osx-64 osx-arm64 \
  gs66-hdev:/www/htdocs/yourdir/conda/
```

For local testing, you can also leave them on your local machine, and just point the mamba command to the appropriate directory.

## Installing the Packages 

To install a package built in `output`, include the local channel and
conda-forge:

```sh
mamba create -n hea heasoft -c ./output -c conda-forge
```

For a package hosted in a testing directory, use its channel URL:

```sh
conda install heasoft -k \
  -c https://heasarcdev.gsfc.nasa.gov/yourdir/conda/ -c conda-forge
```

The `-k` option is required when installing packages hosted on our heasarcdev server, to allow insecure connections.

## Testing the Packages

Ideally, each package has a test suite that runs when the package is built. Until then,
the packages will need to be tested after they are built.

The heasoft package does not build the unit test tasks. Those are available in the
`heasoft-tests` package, which is essentially `heasoft` plus the unit tests executables
`ut_*`, but not the test data. To access the test data, ask Bryan.

If you don't have conda setup, these are the steps:

1. Install miniforge (a the free version of conda). See 
[the website for instructions](https://github.com/conda-forge/miniforge).
This involves downloading the install script, running it to install it in some dir `CONDA_DIR`, then initializing it:
```sh
curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
bash Miniforge3-$(uname)-$(uname -m).sh -b -p "${CONDA_DIR}"
source "${CONDA_DIR}/etc/profile.d/conda.sh"
source "${CONDA_DIR}/etc/profile.d/mamba.sh" # for mamba support
conda activate
```
At this point, your prompt changes to something like `(base)[...]`.

2. Install heasoft into a new conda environment (called hea)
```sh
mamba create -n hea python=3.12 heasoft -k -c https://heasarcdev.gsfc.nasa.gov/azoghbi/conda-full/ -c conda-forge -y
```
and wait for the install to finish.

3. Activate the newly created conda environment containing HEASoft:
```sh
conda activate hea
```
The prompt should change to something like `(hea)[...]`.
Heasoft should be initialized and you should see a message like:
```sh
activating heasoft in $CONDA_DIR/envs/py312/heasoft
```
If it is not done automatically, please open an issue so it is fixed.

4. Start testing `heasoft`.

5. If you want the heasoft unit tests, install `heasoft-tests` in the same way:
```sh
mamba install heasoft-tests -k -c https://heasarcdev.gsfc.nasa.gov/azoghbi/conda-full/
```

6. If testing `xspec`, note that its model data are distributed separately in
the `xspec-data` package. The recipes declare compatibility with this package
as a run constraint rather than installing it automatically.
