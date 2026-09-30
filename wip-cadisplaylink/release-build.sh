#!/bin/zsh
# Release Qt with the PR, installed to $PREFIX, in two steps:
#   release-build.sh base   qtbase, qtshadertools, qtdeclarative, qttools (macdeployqt, linguist
#                           tools), qtsvg, qtimageformats: a top-level build in $BUILD
#   release-build.sh mm     qtmultimedia (FFmpeg from Homebrew), against the installed $PREFIX,
#                           in $BUILD-qtmultimedia, once the qtmultimedia series is final
# Release with debug info in separate dSYMs, frameworks, macOS 14.4 minimum, no tests/examples.
# With Ninja (Xcode's, found with xcrun): with Unix Makefiles, qt_copy_framework_headers() copies the
# #include_next forwarders of .syncqt_staging over the frameworks' real headers on every build
# (a custom target instead of a command), and the real headers aren't copied back, as they're
# then newer than their sources: a second build leaves frameworks without their headers.
B=/Users/anthony.liot/Desktop/bitbucket
PREFIX=/Users/anthony.liot/Qt/6.13.0-cadisplaylink
BUILD=$B/qt5-build-release-ninja
L=$B/qt5-build-release-logs
NINJA=$(xcrun -f ninja) || { print "no ninja"; exit 1; }
export PATH=${NINJA:h}:$PATH
mkdir -p $L
step() { local name=$1; shift; local s=$(date +%s)
         "$@" > $L/$name.log 2>&1; local rc=$?
         print "$name: rc=$rc $(( $(date +%s) - s ))s warnings=$(grep -c 'warning:' $L/$name.log) errors=$(grep -c 'error:' $L/$name.log)"
         (( rc == 0 )) || { grep -m15 -E 'error|Error' $L/$name.log; exit $rc; }; }
# -separate-debug-info strips some binaries after the linker signed them (qmltestrunner: "changes
# being made to the file will invalidate the code signature"), and the kernel then kills them.
# Re-sign those ad hoc. Frameworks and apps that only lack a resource seal ("code has no
# resources") load fine and are left alone: macdeployqt signs the application's copies.
resign() { local f out n=0
           while IFS= read -r f; do
             file -b "$f" | grep -q Mach-O || continue
             out=$(codesign -v "$f" 2>&1) && continue
             [[ $out == *'no resources'* ]] && continue
             codesign --force --sign - "$f" && print "re-signed $f" && n=$((n + 1))
           done < <(find $1 \( -path '*.dSYM' -prune \) -o -type f \( -perm +111 -o -name '*.dylib' \) -print)
           print "resign: $n binaries in $1"; }
# Every public framework header must be a real header, not a forwarder (see the top)
headers() { local bad=$(grep -l '^#include_next <' $1/lib/*.framework/Versions/A/Headers/*.h 2>/dev/null | wc -l | tr -d ' ')
            print "framework headers that are forwarders: $bad"; (( bad == 0 )) || exit 1; }
case $1 in
base)
  [[ -e $BUILD ]] && { print "$BUILD exists, not reconfiguring"; } || {
    mkdir -p $BUILD && cd $BUILD || exit 1
    step configure $B/qt5/configure -release -force-debug-info -separate-debug-info -prefix $PREFIX \
        -submodules qtbase,qtshadertools,qtdeclarative,qttools,qtsvg,qtimageformats \
        -nomake tests -nomake examples -- -G Ninja -DCMAKE_MAKE_PROGRAM=$NINJA \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.4 -DQT_BUILD_MANUAL_TESTS=OFF
  }
  cd $BUILD || exit 1
  step build cmake --build . --parallel 16
  step install cmake --install .
  resign $PREFIX
  headers $PREFIX
  ;;
mm)
  mkdir -p $BUILD-qtmultimedia && cd $BUILD-qtmultimedia || exit 1
  [[ -f CMakeCache.txt ]] || step mm-configure $PREFIX/bin/qt-configure-module $B/qt5/qtmultimedia \
      -- -G Ninja -DCMAKE_MAKE_PROGRAM=$NINJA -DFFMPEG_DIR=/opt/homebrew -DFEATURE_ffmpeg=ON
  step mm-build cmake --build . --parallel 16
  step mm-install cmake --install .
  resign $PREFIX
  headers $PREFIX
  ;;
*) print "usage: $0 base|mm"; exit 2 ;;
esac
print "DONE $1"
