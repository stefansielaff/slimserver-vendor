#!/usr/bin/env bash
#
# $Id$
#
# This script builds all binary Perl modules required by Squeezebox Server.
# Stripped down Arch Linux fork for the AUR
#

# Require modules to pass tests
RUN_TESTS=1
USE_HINTS=0
CLEAN=1
FLAGS="-fPIC"

function usage {
    cat <<EOF
$0 [args] [target]
-h this help
-c do not run make clean
-t do not run tests

target: make target - if not specified all will be built

EOF
}

while getopts hct opt; do
  case $opt in
  c)
      CLEAN=0
      ;;
  t)
      RUN_TESTS=0
      ;;
  h)
      usage
      exit
      ;;
  *)
      echo "invalid argument"
      usage
      exit 1
      ;;
  esac
done

shift $((OPTIND - 1))

echo "RUN_TESTS:$RUN_TESTS CLEAN:$CLEAN USE_HINTS:$USE_HINTS target ${1-all}"

OS=`uname`
MACHINE=`uname -m`

# get system arch, stripping out extra -gnu on Linux
ARCH=`/usr/bin/perl -MConfig -le 'print $Config{archname}' | sed 's/gnu-//' | sed 's/^i[3456]86-/i386-/' | sed 's/armv.*?-/arm-/' `

# Build dir
BUILD=$PWD/build
PERL_BASE=$BUILD/perl5x
PERL_ARCH=$BUILD/arch/perl5x

# try to use default perl version
if [ "$PERL_BIN" = "" ]; then
    PERL_BIN=`which perl`
    PERL_VERSION=`perl -MConfig -le '$Config{version} =~ /(\d+.\d+)\./; print $1'`
    echo "Building with Perl $PERL_VERSION at $PERL_BIN"
    PERL_BASE=$BUILD/$PERL_VERSION
    PERL_ARCH=$BUILD/arch/$PERL_VERSION
fi

export MAKE=/usr/bin/make                        

# Clean up
if [ $CLEAN -eq 1 ]; then
    rm -rf $BUILD/arch
fi

mkdir -p $PERL_ARCH

# $1 = args
# $2 = file
function tar_wrapper {
    echo "tar $1 $2"
    tar $1 "$2" > /dev/null
    echo "tar done"
}

# $1 = module to build
# $2 = Makefile.PL arg(s)
# $3 = run tests if 1 - default to $RUN_TESTS
# $4 = make clean if 1 - default to $CLEAN
# $5 = use hints if 1 - default to $USE_HINTS
function build_module {
    module=$1
    makefile_args=$2
    local_run_tests=${3-$RUN_TESTS}
    local_clean=${4-$CLEAN}
    local_use_hints=${5-$USE_HINTS}

    echo "build_module run tests:$local_run_tests clean:$local_clean hints $local_use_hints $module $makefile_args"

    if [ ! -d $module ]; then

        if [ ! -f "${module}.tar.gz" ]; then
            echo "ERROR: cannot find source code archive ${module}.tar.gz"
            echo "Please download all source files from http://github.com/Logitech/slimserver-vendor"
            exit
        fi

        tar_wrapper zxvf "${module}.tar.gz"
    fi

    cd "${module}"
    
    if [ $PERL_BIN ]; then
        export PERL5LIB=$PERL_BASE/lib/perl5
        
        $PERL_BIN Makefile.PL INSTALL_BASE=$PERL_BASE $makefile_args
        if [ $local_run_tests -eq 1 ]; then
            make test
        else
            make
        fi
        if [ $? != 0 ]; then
            if [ $local_run_tests -eq 1 ]; then
                echo "make test failed, aborting"
            else
                echo "make failed, aborting"
            fi
            exit $?
        fi
        make install

        if [ $local_clean -eq 1 ]; then
            make clean
        fi
    fi

    cd ..
    rm -rf $module
}

function build_all {
    build Audio::Scan
    build Class::XSAccessor
    build Encode::Detect
    build Image::Scale
    build IO::AIO
    build IO::Interface
    build Linux::Inotify2
    build Media::Scan
    build MP3::Cut::Gapless
}

function build {
    case "$1" in
        Class::XSAccessor)
	    build_module Class-XSAccessor-1.18
	    cp -pR $PERL_BASE/lib/perl5/$ARCH/Class $PERL_ARCH/
            ;;
        
        Encode::Detect)
            build_module Encode-Detect-1.00
            ;;

        Image::Scale)
            tar_wrapper zxvf Image-Scale-0.11.tar.gz
            cd Image-Scale-0.11
            cd ..
            build_module Image-Scale-0.11 "INSTALL_BASE=$PERL_BASE"
            ;;
        
        IO::AIO)
            build_module IO-AIO-3.71 "" 0 $CLEAN 0
            ;;
        
        IO::Interface)
            build_module IO-Interface-1.06
            ;;
        
        Linux::Inotify2)
            build_module Linux-Inotify2-1.21
            ;;
        
        Audio::Scan)
            build_module Audio-Scan-0.95
            ;;

        MP3::Cut::Gapless)
            build_module Audio-Cuefile-Parser-0.02
            build_module MP3-Cut-Gapless-0.03
            ;;  
        
        Media::Scan)            
            tar_wrapper zxvf libmediascan-0.1.tar.gz
            cd libmediascan-0.1

	    patch -p2 < ../libmediascan-0.1-arch.patch

            CFLAGS="-I$BUILD/include $FLAGS $OSX_ARCH $OSX_FLAGS -O3" \
            LDFLAGS="-L$BUILD/lib $FLAGS $OSX_ARCH $OSX_FLAGS -O3" \
            OBJCFLAGS="-L$BUILD/lib $FLAGS $OSX_ARCH $OSX_FLAGS -O3" \
                ./configure --prefix=$BUILD --disable-shared --disable-dependency-tracking
            make
            if [ $? != 0 ]; then
                echo "make failed"
                exit $?
            fi            
            make install
            cd ..

            # build Media::Scan
            cd libmediascan-0.1/bindings/perl

            MSOPTS="--with-lms-includes=$BUILD/include"

            if [ $PERL_BIN ]; then
                $PERL_BIN Makefile.PL $MSOPTS INSTALL_BASE=$PERL_BASE
                make
                if [ $? != 0 ]; then
                    echo "make failed, aborting"
                    exit $?
                fi
                # XXX hack until regular test works
                $PERL_BIN -Iblib/lib -Iblib/arch t/01use.t
                if [ $? != 0 ]; then
                    echo "make test failed, aborting"
                    exit $?
                fi
                make install
                if [ $CLEAN -eq 1 ]; then
                    make clean
                fi
            fi
            
            cd ../../..
            rm -rf libmediascan-0.1
            ;;
    esac
}

# Build a single module if requested, or all
if [ $1 ]; then
    echo "building only $1"
    build $1
else
    build_all
fi

# Reset PERL5LIB
export PERL5LIB=

# strip all so files
find $BUILD -name '*.so' -exec chmod u+w {} \;
find $BUILD -name '*.so' -exec strip {} \;

# clean out useless .bs/.packlist files, etc
find $BUILD -name '*.bs' -exec rm -f {} \;
find $BUILD -name '*.packlist' -exec rm -f {} \;

# create our directory structure
# rsync is used to avoid copying non-binary modules or other extra stuff
mkdir -p $PERL_ARCH/$ARCH
rsync -amv --include='*/' --include='*.so' --include='*.bundle' --include='autosplit.ix' --exclude='*' $PERL_BASE/lib/perl5/*/auto $PERL_ARCH/$ARCH/

# could remove rest of build data, but let's leave it around in case
#rm -rf $PERL_BASE
#rm -rf $PERL_ARCH
#rm -rf $BUILD/bin $BUILD/etc $BUILD/include $BUILD/lib $BUILD/man $BUILD/share $BUILD/var
