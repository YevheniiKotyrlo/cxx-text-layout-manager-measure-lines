#!/usr/bin/env bash
# runs outside Git Bash: Linux, with curl, git, clang and the Boost, glog and double-conversion headers
# Compiles repro.cpp against react-native's ReactCommon with its cxx platform folders, the ones Fantom's tester builds,
# and the folly, fast_float and fmt versions its Android build pins. Exits 1 while clang reports that
# TextLayoutManagerExtended::supportsLineMeasurement() is false for the cxx TextLayoutManager, 0 once repro.cpp
# compiles, 2 on anything else.
#   bash repro.sh                                 downloads react/react-native's main
#   REACT_NATIVE_DIR=<checkout> bash repro.sh     compiles against a checkout instead
#   Ubuntu 24.04: apt-get install clang curl git libboost-dev libgoogle-glog-dev libdouble-conversion-dev
set -euo pipefail

stop() {
  echo "summary: $1"
  exit 2
}

compiler=${CXX:-clang++}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || stop "cannot find the folder repro.sh is in"
work=$(mktemp -d) || stop "mktemp -d failed"
trap 'rm -rf "$work"' EXIT

if [[ -n ${REACT_NATIVE_DIR:-} ]]; then
  react_native=$REACT_NATIVE_DIR
  [[ -d $react_native ]] || stop "no folder $react_native"
  commit=$(cat "$react_native/COMMIT" 2> /dev/null || git -C "$react_native" rev-parse --short HEAD 2> /dev/null) ||
    stop "$react_native holds neither a COMMIT file nor a git checkout"
else
  main=$(git ls-remote https://github.com/react/react-native.git refs/heads/main) ||
    stop "git ls-remote of react/react-native failed"
  commit=${main:0:10}
  [[ -n $commit ]] || stop "react/react-native has no main branch"
  react_native=$work/react-native
  mkdir "$react_native"
  curl -fsSL "https://codeload.github.com/react/react-native/tar.gz/${main%%[[:space:]]*}" |
    tar -xz -C "$react_native" --strip-components=1 --wildcards \
      '*/packages/react-native/ReactCommon/*' '*/packages/react-native/gradle/*' ||
    stop "the download of react/react-native $commit failed"
fi
compiler_version=$("$compiler" --version | sed -n 1p) || stop "$compiler does not run"
system=$(uname -sm)
echo "react/react-native $commit, $compiler_version, $system"

versions=$react_native/packages/react-native/gradle/libs.versions.toml
[[ -f $versions ]] || stop "no $versions"
version_of() {
  sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$versions"
}
folly=$(version_of folly)
fast_float=$(version_of fastFloat)
fmt=$(version_of fmt)
[[ -n $folly && -n $fast_float && -n $fmt ]] || stop "$versions names no folly, fastFloat or fmt version"
clone_tag() {
  git clone --quiet --depth 1 --branch "$2" "$1" "$work/$3" 2> /dev/null || stop "git clone of $1 at $2 failed"
}
clone_tag https://github.com/facebook/folly.git "v$folly" folly
clone_tag https://github.com/fastfloat/fast_float.git "v$fast_float" fast_float
clone_tag https://github.com/fmtlib/fmt.git "$fmt" fmt
echo "folly $folly, fast_float $fast_float and fmt $fmt, as libs.versions.toml pins them"

react_common=$react_native/packages/react-native/ReactCommon
cxx_platform=react/renderer/textlayoutmanager/platform/cxx
cxx_header=$cxx_platform/react/renderer/textlayoutmanager/TextLayoutManager.h
[[ -f $react_common/$cxx_header ]] || stop "no $cxx_header below $react_common"
includes=(
  -I "$react_common"
  -I "$react_common/jsi"
  -I "$react_common/callinvoker"
  -I "$react_common/runtimeexecutor"
  -I "$react_common/yoga"
  -I "$work/folly"
  -I "$work/fast_float/include"
  -I "$work/fmt/include"
)
cxx_platform_folders=$(find "$react_common" -type d -path '*/platform/cxx') ||
  stop "cannot list the platform/cxx folders below $react_common"
while IFS= read -r cxx_platform_folder; do
  [[ -z $cxx_platform_folder ]] || includes+=(-I "$cxx_platform_folder")
done <<< "$cxx_platform_folders"
react_folders=$(find "$react_common" -type d -name React -not -path '*/platform/android/*' -not -path '*/platform/ios/*') ||
  stop "cannot list the React/ header folders below $react_common"
while IFS= read -r react_folder; do
  [[ -z $react_folder ]] || includes+=(-I "${react_folder%/React}")
done <<< "$react_folders"
flags=(-std=c++20 -DFOLLY_NO_CONFIG=1 -DFOLLY_CFG_NO_COROUTINES=1 -DFOLLY_MOBILE=1 "${includes[@]}")

set +e
dependencies=$("$compiler" "${flags[@]}" -MM -MT repro.o "$script_dir/repro.cpp" 2>&1)
dependencies_status=$?
set -e
[[ $dependencies_status -eq 0 ]] ||
  stop "the preprocessor fails on repro.cpp: $(grep -E -m 1 'error:' <<< "$dependencies" || true)"
included=$(grep -o -E '[^ ]*/textlayoutmanager/TextLayoutManager\.h' <<< "$dependencies" || true)
[[ $included == "$react_common/$cxx_header" ]] ||
  stop "repro.cpp includes ${included:-no TextLayoutManager.h} rather than $cxx_header"
echo "repro.cpp includes ReactCommon/$cxx_header, whose TextLayoutManager declares these members:"
grep -E '^ +(explicit |virtual )?[A-Za-z].*\(' "$react_common/$cxx_header" | sed 's/^ */  /' || true

echo "compiling repro.cpp: static_assert(facebook::react::TextLayoutManagerExtended::supportsLineMeasurement());"
set +e
diagnostics=$("$compiler" "${flags[@]}" -fsyntax-only "$script_dir/repro.cpp" 2>&1)
compile_status=$?
set -e
if [[ $compile_status -eq 0 ]]; then
  echo "summary: react/react-native $commit: TextLayoutManagerExtended::supportsLineMeasurement() is true for the cxx platform's TextLayoutManager"
  exit 0
fi
errors=$(grep -E 'error:' <<< "$diagnostics" || true)
failed_assertion=$(grep -E 'repro\.cpp:[0-9]+:[0-9]+: error: static assertion failed due to requirement .*supportsLineMeasurement\(\)' <<< "$errors" || true)
error_count=$(grep -c . <<< "$errors") || error_count=0
if [[ -n $failed_assertion && $error_count -eq 1 ]]; then
  echo "${failed_assertion//$script_dir\//}"
  echo "summary: react/react-native $commit: TextLayoutManagerExtended::supportsLineMeasurement() is false for the cxx platform's TextLayoutManager"
  exit 1
fi
head -n 5 <<< "${errors:-$diagnostics}"
stop "repro.cpp does not compile against react/react-native $commit"
