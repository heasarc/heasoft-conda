#!/bin/bash

set -e
set -o pipefail

HEA_SUBDIR=heasoft

ostype=$(uname)
if [ "$ostype" = "Darwin" ]; then

    # remove extra @rpath // needed for perl pipelines; e.g. xrtpipeline
    for conf in `find . -type f -name "configure" -path "*BUILD_DIR*"`; do
        sed -i '' 's|-Wl,-rpath,\\$HD_TOP_EXEC_PFX/lib||g' $conf
    done

    # fix python library in mac x86_64
    if [ "$OSX_ARCH" = "x86_64" ]; then
        for conf in `find . -type f -name "configure" -path "*BUILD_DIR*"`; do
            sed -i '' 's/^.*PYTHON_LIBRARY=.*$/PYTHON_LIBRARY=-Wl,-undefined,dynamic_lookup/' $conf
        done
        export CXXFLAGS="${CXXFLAGS} -D_LIBCPP_DISABLE_AVAILABILITY"
    fi
fi
# Export PERL & MAKE settings to avoid relying on leakage from hosts:
export MAKE="$PREFIX/bin/make"
export PERL="$PREFIX/bin/perl"

bash BUILD_DIR/fix-x11-conda.sh $PREFIX


configure_args=(
    --prefix=$PREFIX/$HEA_SUBDIR
    --enable-collapse=all
    --x-includes=$PREFIX/include
    --x-libraries=$PREFIX/lib
    --with-tcl=$PREFIX/lib
    --with-fgsl=$PREFIX
    --with-gsl=$PREFIX
    --with-fftw=$PREFIX
)

mask_files="libtk8.6.dylib" # libtcl8.6.dylib"
if [ "$ostype" = "Darwin" ]; then
   for file in $mask_files; do
       mv $PREFIX/lib/$file $PREFIX/lib/${file}.off
   done
fi


cd BUILD_DIR
./configure "${configure_args[@]}" 2>&1 | tee config.txt || false
#make 2>&1 | tee build.txt || false
#make install 2>&1 | tee install.txt || false
source $HEADAS/headas-init.sh
make test || false 
make install-test || false
rm -rf $PREFIX/$HEA_SUBDIR/BUILD_DIR/hd_install.o

if [ "$ostype" = "Darwin" ]; then
    for file in $mask_files; do
        mv $PREFIX/lib/${file}.off $PREFIX/lib/${file}
    done
fi
