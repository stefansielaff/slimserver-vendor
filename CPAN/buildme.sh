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

if [ "$OS" = "Linux" -o "$OS" = "FreeBSD" ]; then
    echo "Building for $OS / $ARCH"
else
    echo "Unsupported platform: $OS, please submit a patch or provide us with access to a development system."
    exit
fi

for i in gcc cpp rsync make ; do
    which $i > /dev/null
    if [ $? -ne 0 ] ; then
        echo "$i not found - please install it"
        exit 1
    fi
done

which yasm > /dev/null
if [ $? -ne 0 ] ; then
    which nasm > /dev/null
    if [ $? -ne 0 ] ; then
        echo "please install either yasm or nasm."
        exit 1
    fi
fi

if [ "$OS" = "Linux" ]; then
	#for i in libgif libz libgd ; do
	for i in libz libgd ; do
	    ldconfig -p | grep "${i}.so" > /dev/null
	    if [ $? -ne 0 ] ; then
	        echo "$i not found - please install it"
	        exit 1
	    fi
	done
fi

find /usr/lib/ -maxdepth 1 | grep libungif
if [ $? -eq 0 ] ; then
    echo "ON SOME PLATFORMS (Ubuntu/Debian at least) THE ABOVE LIBRARIES MAY NEED TO BE TEMPORARILY REMOVED TO ALLOW THE BUILD TO WORK"
fi

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
    
    if [ $local_use_hints -eq 1 ]; then
        # Always copy in our custom hints for OSX
        cp -Rv ../hints .
    fi
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
            build_module Data-Dump-1.19
            build_module ExtUtils-CBuilder-0.260301
            build_module Module-Build-0.35 "" 0
            build_module Encode-Detect-1.00
            ;;

        Image::Scale)
            build_libjpeg
            build_libpng
            build_giflib
            
            # build Image::Scale
            build_module Test-NoWarnings-1.02 "" 0

            tar_wrapper zxvf Image-Scale-0.11.tar.gz
            cd Image-Scale-0.11
            cp -Rv ../hints .
            cd ..
            
            build_module Image-Scale-0.11 "--with-jpeg-includes="$BUILD/include" --with-jpeg-static \
                    --with-png-includes="$BUILD/include" --with-png-static \
                    --with-gif-includes="$BUILD/include" --with-gif-static \
                    INSTALL_BASE=$PERL_BASE"
            
            ;;
        
        IO::AIO)
            if [ "$OS" != "FreeBSD" ]; then
                build_module common-sense-2.0
            
                # Don't use the darwin hints file, it breaks if compiled on Snow Leopard with 10.5 (!?)
                build_module IO-AIO-3.71 "" 0 $CLEAN 0
            fi
            ;;
        
        IO::Interface)
            build_module IO-Interface-1.06
            ;;
        
        Linux::Inotify2)
            if [ "$OS" = "Linux" ]; then
                build_module common-sense-2.0
                build_module Linux-Inotify2-1.21
            fi
            ;;
        
        Audio::Scan)
            build_module Sub-Uplevel-0.22 "" 0
            build_module Tree-DAG_Node-1.06 "" 0
            build_module Test-Warn-0.23 "" 0
            build_module Audio-Scan-0.95
            ;;

        MP3::Cut::Gapless)
            build_module Audio-Cuefile-Parser-0.02
            build_module MP3-Cut-Gapless-0.03
            ;;  
        
        Media::Scan)            
            build_ffmpeg
            build_libexif
            build_libjpeg
            build_libpng
            build_giflib
            build_bdb
            
            # build libmediascan
            # XXX library does not link correctly on Darwin with libjpeg due to missing x86_64
            # in libjpeg.dylib, Perl still links OK because it uses libjpeg.a
            tar_wrapper zxvf libmediascan-0.1.tar.gz

            if [ "$OSX_VER" = "10.9" -o "$OSX_VER" = "10.10" ]; then
                patch -p0 libmediascan-0.1/bindings/perl/hints/darwin.pl < libmediascan-hints-darwin.pl.patch
            fi

            cd libmediascan-0.1

			if [ "$OS" = "FreeBSD" ]; then
            	patch -p1 < ../libmediascan-freebsd.patch
            fi

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
            # LMS's hints file is OK and also has custom frameworks added
            
            MSOPTS="--with-static \
                --with-ffmpeg-includes=$BUILD/include \
                --with-lms-includes=$BUILD/include \
                --with-exif-includes=$BUILD/include \
                --with-jpeg-includes=$BUILD/include \
                --with-png-includes=$BUILD/include \
                --with-gif-includes=$BUILD/include \
                --with-bdb-includes=$BUILD/include"
                
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

function build_libexif {
    if [ -f $BUILD/include/libexif/exif-data.h ]; then
        return
    fi
    
    # build libexif
    tar_wrapper jxvf libexif-0.6.20.tar.bz2
    cd libexif-0.6.20
    
    CFLAGS="$FLAGS $OSX_ARCH $OSX_FLAGS -O3" \
    LDFLAGS="$FLAGS $OSX_ARCH $OSX_FLAGS -O3" \
        ./configure --prefix=$BUILD \
        --disable-dependency-tracking
    $MAKE
    if [ $? != 0 ]; then
        echo "make failed"
        exit $?
    fi
    $MAKE install
    cd ..
    
    rm -rf libexif-0.6.20
}    

function build_libjpeg {
    if [ -f $BUILD/include/jpeglib.h ]; then
        return
    fi
    
    # build libjpeg-turbo on x86 platforms
    # skip on 10.9 until we've been able to build nasm from macports
    if [ "$OS" = "Darwin" -a "$OSX_VER" != "10.5" ]; then
        # Build i386/x86_64 versions of turbo
        tar_wrapper zxvf libjpeg-turbo-1.1.1.tar.gz
        cd libjpeg-turbo-1.1.1
        
        # Disable features we don't need
        cp -fv ../libjpeg-turbo-jmorecfg.h jmorecfg.h
        
        # Build 64-bit fork
        CFLAGS="-O3 $OSX_FLAGS" \
        CXXFLAGS="-O3 $OSX_FLAGS" \
        LDFLAGS="$OSX_FLAGS" \
            ./configure --prefix=$BUILD --host x86_64-apple-darwin NASM=/usr/local/bin/nasm \
            --disable-dependency-tracking
        make
        if [ $? != 0 ]; then
            echo "make failed"
            exit $?
        fi
        cp -fv .libs/libjpeg.a libjpeg-x86_64.a
        
        # Build 32-bit fork
        if [ $CLEAN -eq 1 ]; then
            make clean
        fi
        CFLAGS="-O3 -m32 $OSX_FLAGS" \
        CXXFLAGS="-O3 -m32 $OSX_FLAGS" \
        LDFLAGS="-m32 $OSX_FLAGS" \
            ./configure --prefix=$BUILD NASM=/usr/local/bin/nasm \
            --disable-dependency-tracking
        make
        if [ $? != 0 ]; then
            echo "make failed"
            exit $?
        fi
        cp -fv .libs/libjpeg.a libjpeg-i386.a
        
        # Combine the forks
        lipo -create libjpeg-x86_64.a libjpeg-i386.a -output libjpeg.a
        
        # Install and replace libjpeg.a with universal version
        make install
        cp -f libjpeg.a $BUILD/lib/libjpeg.a
        cd ..
    
    elif [ "$OS" = "Darwin" -a "$OSX_VER" = "10.5" ]; then
        # combine i386 turbo with ppc libjpeg
        
        # build i386 turbo
        tar_wrapper zxvf libjpeg-turbo-1.1.1.tar.gz
        cd libjpeg-turbo-1.1.1
        
        # Disable features we don't need
        cp -fv ../libjpeg-turbo-jmorecfg.h jmorecfg.h
        
        CFLAGS="-O3 -m32 $OSX_FLAGS" \
        CXXFLAGS="-O3 -m32 $OSX_FLAGS" \
        LDFLAGS="-m32 $OSX_FLAGS" \
            ./configure --prefix=$BUILD NASM=/usr/local/bin/nasm \
            --disable-dependency-tracking
        make
        if [ $? != 0 ]; then
            echo "make failed"
            exit $?
        fi
        make install
        cp -fv .libs/libjpeg.a ../libjpeg-i386.a
        cd ..
        
        # build ppc libjpeg 6b
        tar_wrapper zxvf jpegsrc.v6b.tar.gz
        cd jpeg-6b
        
        # Disable features we don't need
        cp -fv ../libjpeg62-jmorecfg.h jmorecfg.h
        
        CFLAGS="-arch ppc -O3 $OSX_FLAGS" \
        LDFLAGS="-arch ppc -O3 $OSX_FLAGS" \
            ./configure --prefix=$BUILD \
            --disable-dependency-tracking
        make
        if [ $? != 0 ]; then
            echo "make failed"
            exit $?
        fi
        cp -fv libjpeg.a ../libjpeg-ppc.a
        cd ..
        
        # Combine the forks
        lipo -create libjpeg-i386.a libjpeg-ppc.a -output libjpeg.a
        
        # Replace libjpeg library
        mv -fv libjpeg.a $BUILD/lib/libjpeg.a
        rm -fv libjpeg-i386.a libjpeg-ppc.a
        
    elif [ "$ARCH" = "i386-linux-thread-multi" -o "$ARCH" = "x86_64-linux-thread-multi" -o "$OS" = "FreeBSD" ]; then
        # build libjpeg-turbo
        tar_wrapper zxvf libjpeg-turbo-1.1.1.tar.gz
        cd libjpeg-turbo-1.1.1
        
        # Disable features we don't need
        cp -fv ../libjpeg-turbo-jmorecfg.h jmorecfg.h
        
        CFLAGS="$FLAGS $OSX_ARCH $OSX_FLAGS" CXXFLAGS="$FLAGS $OSX_ARCH $OSX_FLAGS" LDFLAGS="$FLAGS $OSX_ARCH $OSX_FLAGS" \
            ./configure --prefix=$BUILD --disable-dependency-tracking
        make
        if [ $? != 0 ]; then
            echo "make failed"
            exit $?
        fi
        
        make install
        cd ..
        
    # build libjpeg v8 on other platforms
    else
        tar_wrapper zxvf jpegsrc.v8b.tar.gz
        cd jpeg-8b
        
        # Disable features we don't need
        cp -fv ../libjpeg-jmorecfg.h jmorecfg.h
        
        CFLAGS="$FLAGS $OSX_ARCH $OSX_FLAGS -O3" \
        LDFLAGS="$FLAGS $OSX_ARCH $OSX_FLAGS -O3" \
            ./configure --prefix=$BUILD \
            --disable-dependency-tracking
        make
        if [ $? != 0 ]; then
            echo "make failed"
            exit $?
        fi
        make install
        cd ..
    fi
    
    rm -rf jpeg-8b
    rm -rf jpeg-6b
    rm -rf libjpeg-turbo-1.1.1
}

function build_libpng {
    if [ -f $BUILD/include/png.h ]; then
        return
    fi
    
    # build libpng
    tar_wrapper zxvf libpng-1.4.3.tar.gz
    cd libpng-1.4.3
    
    # Disable features we don't need
    cp -fv ../libpng-pngconf.h pngconf.h
    
    CFLAGS="$FLAGS $OSX_ARCH $OSX_FLAGS -O3" \
    LDFLAGS="$FLAGS $OSX_ARCH $OSX_FLAGS -O3" \
        ./configure --prefix=$BUILD \
        --disable-dependency-tracking
    make && make check
    if [ $? != 0 ]; then
        echo "make failed"
        exit $?
    fi
    make install
    cd ..
    
    rm -rf libpng-1.4.3
}

function build_giflib {
    if [ -f $BUILD/include/gif_lib.h ]; then
        return
    fi
    
    # build giflib
    tar_wrapper zxvf giflib-4.1.6.tar.gz
    cd giflib-4.1.6
    CFLAGS="$FLAGS $OSX_ARCH $OSX_FLAGS -O3" \
    LDFLAGS="$FLAGS $OSX_ARCH $OSX_FLAGS -O3" \
        ./configure --prefix=$BUILD \
        --disable-dependency-tracking
    make
    if [ $? != 0 ]; then
        echo "make failed"
        exit $?
    fi
    make install
    cd ..
    
    rm -rf giflib-4.1.6
}

function build_ffmpeg {
    echo "build ffmpeg"
    if [ -f $BUILD/include/libavformat/avformat.h ]; then
        echo "found avformat.h - returning"
        return
    fi
    
    # build ffmpeg, enabling only the things libmediascan uses
    tar_wrapper jxvf ffmpeg-0.8.4.tar.bz2
    cd ffmpeg-0.8.4
    
    if [ "$MACHINE" = "padre" ]; then
        patch -p0 < ../ffmpeg-padre-configure.patch
    fi
    
    echo "Configuring FFmpeg..."
    
    # x86: Disable all but the lowend MMX ASM
    # ARM: Disable all
    # PPC: Disable AltiVec
    FFOPTS="--prefix=$BUILD --disable-ffmpeg --disable-ffplay --disable-ffprobe --disable-ffserver \
        --disable-avdevice --enable-pic \
        --disable-amd3dnow --disable-amd3dnowext --disable-mmx2 --disable-sse --disable-ssse3 --disable-avx \
        --disable-armv5te --disable-armv6 --disable-armv6t2 --disable-armvfp --disable-iwmmxt --disable-mmi --disable-neon \
        --disable-altivec \
        --disable-vis \
        --enable-zlib --disable-bzlib \
        --disable-everything --enable-swscale \
        --enable-decoder=h264 --enable-decoder=mpeg1video --enable-decoder=mpeg2video \
        --enable-decoder=mpeg4 --enable-decoder=msmpeg4v1 --enable-decoder=msmpeg4v2 \
        --enable-decoder=msmpeg4v3 --enable-decoder=vp6f --enable-decoder=vp8 \
        --enable-decoder=wmv1 --enable-decoder=wmv2 --enable-decoder=wmv3 --enable-decoder=rawvideo \
        --enable-decoder=mjpeg --enable-decoder=mjpegb --enable-decoder=vc1 \
        --enable-decoder=aac --enable-decoder=ac3 --enable-decoder=dca --enable-decoder=mp3 \
        --enable-decoder=mp2 --enable-decoder=vorbis --enable-decoder=wmapro --enable-decoder=wmav1 --enable-decoder=flv \
        --enable-decoder=wmav2 --enable-decoder=wmavoice \
        --enable-decoder=pcm_dvd --enable-decoder=pcm_s16be --enable-decoder=pcm_s16le \
        --enable-decoder=pcm_s24be --enable-decoder=pcm_s24le \
        --enable-decoder=ass --enable-decoder=dvbsub --enable-decoder=dvdsub --enable-decoder=pgssub --enable-decoder=xsub \
        --enable-parser=aac --enable-parser=ac3 --enable-parser=dca --enable-parser=h264 --enable-parser=mjpeg \
        --enable-parser=mpeg4video --enable-parser=mpegaudio --enable-parser=mpegvideo --enable-parser=vc1 \
        --enable-demuxer=asf --enable-demuxer=avi --enable-demuxer=flv --enable-demuxer=h264 \
        --enable-demuxer=matroska --enable-demuxer=mov --enable-demuxer=mpegps --enable-demuxer=mpegts --enable-demuxer=mpegvideo \
        --enable-protocol=file"
    
    # ASM doesn't work right on x86_64
    # XXX test --arch options on Linux
    if [ "$ARCH" = "x86_64-linux-thread-multi" -o "$ARCH" = "amd64-freebsd-thread-multi" ]; then
        FFOPTS="$FFOPTS --disable-mmx"
    fi
    # FreeBSD amd64 needs arch option
    if [ "$ARCH" = "amd64-freebsd" -o "$ARCH" = "amd64-freebsd-thread-multi" ]; then
        FFOPTS="$FFOPTS --arch=x86"
    fi
    
        
	CFLAGS="$FLAGS -O3" \
	LDFLAGS="$FLAGS -O3" \
		./configure $FFOPTS
	
	$MAKE
	if [ $? != 0 ]; then
		echo "make failed"
		exit $?
	fi
	$MAKE install
	cd ..
    
    rm -rf ffmpeg-0.8.4
}

function build_bdb {
    if [ -f $BUILD/include/db.h ]; then
        return
    fi
    
    # --enable-posixmutexes is needed to build on ReadyNAS Sparc.
    MUTEX=""
    if [ "$MACHINE" = "padre" ]; then
      MUTEX="--enable-posixmutexes"
    fi
    
    # build bdb
    tar_wrapper zxvf db-5.1.25.tar.gz
    cd db-5.1.25/build_unix
    
    if [ "$OS" = "Darwin" -o "$OS" = "FreeBSD" ]; then
       pushd ..
       patch -p0 < ../db51-src_dbinc_atomic.patch
       popd
    fi

    CFLAGS="$FLAGS $OSX_ARCH $OSX_FLAGS -O3" \
    LDFLAGS="$FLAGS $OSX_ARCH $OSX_FLAGS -O3" \
        ../dist/configure --prefix=$BUILD $MUTEX \
        --with-cryptography=no -disable-hash --disable-queue --disable-replication --disable-statistics --disable-verify \
        --disable-dependency-tracking --disable-shared
    make
    if [ $? != 0 ]; then
        echo "make failed"
        exit $?
    fi
    make install
    cd ../..
    
    rm -rf db-5.1.25
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
