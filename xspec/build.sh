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

# Create initialization scripts heainit.[sh|csh] in $PWD/activate.d/
# These will initialize HEASoft and check + apply the macOS X11 fix
# (if needed) on first activation
mkdir activate.d deactivate.d
cat <<'EOF' >activate.d/heainit.sh
#!/bin/bash
export HEADAS=$CONDA_PREFIX/heasoft
echo "Activating heasoft in $HEADAS"

# Check if X11 fix is needed (only on macOS)
if [[ "$OSTYPE" == "darwin"* ]] && [ -f "$HEADAS/BUILD_DIR/fix-x11-conda.sh" ]; then
    # Check if clobbered files exist
    if ls $CONDA_PREFIX/include/X11/*.h__clobber-from-xorg-* >/dev/null 2>&1 || \
       [ -d "$CONDA_PREFIX/__clobbers__/xorg-libx11" ] || \
       [ -d "$CONDA_PREFIX/__clobbers__/xorg-xorgproto" ]; then
        echo "Applying X11 header fix for macOS (one-time setup)..."
        bash "$HEADAS/BUILD_DIR/fix-x11-conda.sh" "$CONDA_PREFIX" 2>/dev/null || \
            echo "Note: Could not apply X11 fix automatically. You may need to run: conda install xorg-libx11 --clobber"
    fi
fi

source $HEADAS/BUILD_DIR/headas-init.sh
EOF
cat <<'EOF' >activate.d/heainit.csh
#!/bin/csh
setenv HEADAS $CONDA_PREFIX/heasoft
echo "Activating heasoft in $HEADAS"

# Check if X11 fix is needed (only on macOS)
if ( `uname` == "Darwin" && -f "$HEADAS/BUILD_DIR/fix-x11-conda.sh" ) then
    # Simple check for clobbered files
    set clobber_check = `ls $CONDA_PREFIX/include/X11/*.h__clobber-from-xorg-* >& /dev/null; echo $status`
    if ( $clobber_check == 0 || -d "$CONDA_PREFIX/__clobbers__/xorg-libx11" ) then
        echo "Applying X11 header fix for macOS (one-time setup)..."
        bash "$HEADAS/BUILD_DIR/fix-x11-conda.sh" "$CONDA_PREFIX" >& /dev/null
        if ( $status != 0 ) then
            echo "Note: Could not apply X11 fix automatically. You may need to run: conda install xorg-libx11 --clobber"
        endif
    endif
endif

source $HEADAS/BUILD_DIR/headas-init.csh
EOF
chmod +x activate.d/heainit.sh activate.d/heainit.csh

# Copy headas-uninit.[sh|csh] to ./deactivate.d:
cp headas-uninit.*sh deactivate.d/

# Copy de|activate.d folders to $PREFIX/etc/conda so they are available
# for execution after installation / environment activation:
cp -r activate.d $PREFIX/etc/conda/.
cp -r deactivate.d $PREFIX/etc/conda/.

# Copy init scripts to $PREFIX/bin:
cp activate.d/heainit.* $PREFIX/bin/.

# Create a pre-unlink script to clean up $PREFIX bin & etc folders upon
# deactivation:
cat <<EOF >$PREFIX/bin/.xspec-pre-unlink.sh
rm \$CONDA_PREFIX/etc/conda/activate.d/heainit.*sh > /dev/null 2>&1
rm \$CONDA_PREFIX/etc/conda/deactivate.d/headas-uninit.*sh > /dev/null 2>&1
EOF
