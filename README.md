# Content

This repo contains the code to generate conda packages for heasoft and related
packages.

It also contains code to create source tar files for the different packages.

Our public website advertising our conda packages:  
https://heasarc.gsfc.nasa.gov/docs/software/conda.html

## Current Recipes


The following packages are currently included in this repository:

The trivial packages that are basic or already included in conda-forge:
- `healib` is a basic hello world example of creating a conda package.
- `cfitsio`, linking to a test tarball of the CFITSIO package
- `ccfits`, linking to a test tarball of the CCfits package
- `heacore`, peant to package heacore as one package (NOT TESTED YET).

The main packages are:
- `heasoft` the full heasoft distribution (without xspec or xstar data files)
- `heasoft-tests`: Build the test files only (`make test`). It has `heasoft` as a dependency
and that is where it gets the binaries and libraries from. This package is for internal
use only and is not meant to be distributed to users.
- `xspec-data`: Data files for xspec (`spectral/modelData/*`). See `scripts/pacakge_config.json`. This is a dependency of `heasoft`
- `xspec-compilers` for users who need the compilers to install local models

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

The full life cycle for conda packages, from source code to installation

1. Developer - Creating: Create the source code path or tarball
1. Developer - Building: Build the conda package
1. Developer - Hosting: Copy the conda package to the desired distribution location
1. User - Installing: Install the conda package 

## Creating Source

The developer must first create the source code which conda uses to create the package. The source can be a directory or a tarball.

For example, if using a local directory for temporary testing of the develop branch of HEASoft (grabbing a shallow clone, as the history is not important):

```sh
git clone git@sed-gitlab.gsfc.nasa.gov:heasarc/heasoft/heasoft.git --depth 1 heasoft-develop
```

You could also create a source code tarball, such as to upload to the website for testing, assuming you have permissions to write to the needed web dir.  You could upload to your own testing dir `/www.prod/htdocs/yourdir/conda/` or `/www/htdocs/docs/yourdir/conda` (note that the heasarcdev web server necessitates the `-k` option when installing the package later).

```sh
git clone git@sed-gitlab.gsfc.nasa.gov:heasarc/heasoft/heasoft.git --depth 1 heasoft-6.36
tar -zcf heasoft-6.36.tar.gz heasoft-6.36
sha256sum heasoft-6.36.tar.gz # for use in the recipe
scp heasoft-6.36 gs66-hdev:/www/htdocs/yourdir/conda/
```

The [scripts/generate_src_tar.py](scripts/generate_src_tar.py) script creates the tarball in an automated fashion.


## Building Packages

To build a package, the recipe must be able to find the source code. Edit the `recipe.yaml` file for that package. Be sure the `context:version` matches the version you added to the filename.

For building the heasoft package, if using a local path, change the `source` :

```
context:
  name: heasoft
  version: develop

source:
  path: /path/to/heasoft-develop
```

If using a tarball from to the website, this is where you copy in the sha256sum of the tarball:

```
context:
  name: heasoft
  version: 6.36

source:
  url: https://heasarc.gsfc.nasa.gov/yourdir/conda/${{ name }}-${{ version }}.tar.gz
  sha256: c92a03e0ee63a8bc10884e76aab43710621e49afb21b3054445bfc475b4e20fe

```

Call the `run_build.sh` script from inside the relevant folder. For `cfitsio`, this will be:

```sh
cd cfitsio
../scripts/run_build.sh
```

The `run_build.sh` script merely calls this line, which you could also call on your own:

```
rattler-build build --no-include-recipe --output-dir ../output
```

This will write the conda package in the `output` folder. For example, after creating the healib and cfitsio packages on a Mac, the `output` dir has the following contents:

```sh
ls -l ./output
bld:
drwxr-xr-x 2 klrutkow staff 64 Oct 15 00:44 rattler-build_cfitsio_1728967256/
drwxr-xr-x 2 klrutkow staff 64 Oct 14 21:36 rattler-build_healib_1728956112/

noarch:
-rw-r--r-- 1 klrutkow staff 109 Oct 14 21:35 repodata.json

osx-64:
-rw-r--r-- 1 klrutkow staff 974K Oct 15 00:43 cfitsio-4.5.0-h0dc7051_0.conda
-rw-r--r-- 1 klrutkow staff 2.1K Oct 14 21:36 healib-0.1-h0dc7051_0.conda
-rw-r--r-- 1 klrutkow staff 1.2K Oct 15 00:43 repodata.json

src_cache:
drwxr-xr-x 126 klrutkow staff 4.0K Oct 15 00:40 cfitsio-4_5_0_81db33b9/
-rw-r--r--   1 klrutkow staff  14M Oct 15 00:40 cfitsio-4_5_0_81db33b9.tar
```

The contents of the `output` folder should not be kept under version control.

## Hosting Packages

The package folders of `noarch` (contains os-independent packages e.g. `xspec-data`), `linux64`, `osx-arm` and `osx-64` should be put in the webserver. The release packages are in `https://heasarcdev.gsfc.nasa.gov/FTP/software/conda/`.

For testing in your own dir:

```sh
cd output
scp -r noarch linux64 osx-arm osx-64 gs66-hdev:/www/htdocs/yourdir/conda/
```

For local testing, you can also leave them on your local machine, and just point the mamba command to the appropriate directory.

## Installing the Packages 

To use the packages that were built in the output dir, you can install the package with:

```sh
mamba install cfitsio -c ./output
```

To use them after hosting on the website, install with the following command:

```sh
conda install healib -k -c https://heasarcdev.gsfc.nasa.gov/klrutkow/conda/
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
At this point, you see you prompt change to something like: `(base)[...]`

2. Install heasoft into a new conda environment (called hea)
```sh
mamba create -n hea python=3.12 heasoft -k -c https://heasarcdev.gsfc.nasa.gov/azoghbi/conda-full/ -c conda-forge -y
```
and wait for the install to finish.

3. Activate the newly create conda environment (that has heasoft):
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

6. If you are testing `xspec`, note that the xspec data files are distributed in a separate package
`xspec-data`. In the future, the [model data files](https://heasarcdev.gsfc.nasa.gov/docs/wiki/heasoft/xspec/spectral-model-files/) (see also [this page](https://heasarc.gsfc.nasa.gov/docs/software/xspec/modeldata.html)) will be installed using `ftgetmodeldata` instead of using conda packages.

## Notes about rattler-build




