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

bash BUILD_DIR/fix-x11-conda.sh $PREFIX


configure_args=(
    --prefix=$PREFIX/$HEA_SUBDIR
    --enable-collapse=all
    --x-includes=$PREFIX/include
    --x-libraries=$PREFIX/lib
    --with-components=Xspec
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
# Sometimes issues like: -DPACKAGE_STRING=tcl 8.6; 2 steps so it works on mac
find .. -name 'hmakerc' -exec sed -i.bak 's/tcl\\ 8.6/tcl_8.6/g' {} +
find .. -name 'hmakerc.bak' -delete

make 2>&1 | tee build.txt || false
tar -zcvf logs.tgz config.txt build.txt
rm -rf config.txt build.txt hd_install.o
make install 2>&1 | tee install.txt || false

# for xspec local models
cp ../Xspec/BUILD_DIR/hmakerc $PREFIX/$HEA_SUBDIR/bin/
cp ../Xspec/BUILD_DIR/Makefile-std $PREFIX/$HEA_SUBDIR/bin/

# Copy fix-x11-conda.sh; we are inside BUILD_DIR
cp fix-x11-conda.sh $PREFIX/$HEA_SUBDIR/BUILD_DIR/

if [ "$ostype" = "Darwin" ]; then
    for file in $mask_files; do
        mv $PREFIX/lib/${file}.off $PREFIX/lib/${file}
    done
fi

# we need all libraries to be writable so conda-build can
# modify the rpath, etc. (e.g. libxpa.so.1.0)
find $PREFIX/$HEA_SUBDIR/lib -type f ! -type l -name "*$SHLIB_EXT*" -exec chmod 755 {} \;


# write initialization scripts
# 1. write them to bin/heainit.[c]sh
# 2. Write a script bin/.xspe-post-link.sh that copies bin/heainit.[c]sh
#    to $PREFIX/etc/conda/activate.d so they are executed after installation
#    and when the conda environment is activavted.
cat <<EOF >$PREFIX/bin/heainit.sh
#!/bin/bash
export HEADAS=\$CONDA_PREFIX/$HEA_SUBDIR
echo "activating heasoft in \$HEADAS"
source \$HEADAS/BUILD_DIR/headas-init.sh
EOF
chmod +x $PREFIX/bin/heainit.sh
cat <<EOF >$PREFIX/bin/heainit.csh
#!/bin/bash
setenv HEADAS \$CONDA_PREFIX/$HEA_SUBDIR
echo "activating heasoft in \$HEADAS"
source \$HEADAS/BUILD_DIR/headas-init.csh
EOF
chmod +x $PREFIX/bin/heainit.csh

cat <<EOF >$PREFIX/bin/.xspec-post-link.sh
mkdir -p \$CONDA_PREFIX/etc/conda/activate.d
cp \$CONDA_PREFIX/bin/heainit.*sh \$CONDA_PREFIX/etc/conda/activate.d/

mkdir -p \$CONDA_PREFIX/etc/conda/deactivate.d
cp \$CONDA_PREFIX/$HEA_SUBDIR/BUILD_DIR/headas-uninit.*sh \$CONDA_PREFIX/etc/conda/deactivate.d/
EOF
cat <<EOF >$PREFIX/bin/.xspec-pre-unlink.sh
rm \$CONDA_PREFIX/etc/conda/activate.d/heainit.*sh > /dev/null 2>&1
rm \$CONDA_PREFIX/etc/conda/deactivate.d/headas-uninit.*sh > /dev/null 2>&1
EOF
