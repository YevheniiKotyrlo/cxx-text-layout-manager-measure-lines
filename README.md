# The cxx `TextLayoutManager` declares no `measureLines`

The `TextLayoutManager` in `packages/react-native/ReactCommon/react/renderer/textlayoutmanager/platform/cxx/`, the one Fantom's tester builds and subclasses, declares `measure` alone, so `TextLayoutManagerExtended::supportsLineMeasurement()` is false on that platform.

`repro.cpp` includes `<react/renderer/textlayoutmanager/TextLayoutManagerExtended.h>` and holds one assertion: `static_assert(facebook::react::TextLayoutManagerExtended::supportsLineMeasurement());`. `repro.sh` compiles it with clang against react-native's `main`, every `platform/cxx` folder of ReactCommon, and the folly, fast_float and fmt versions that `packages/react-native/gradle/libs.versions.toml` pins. It exits 1 while the static assertion fails, 0 once `repro.cpp` compiles, and 2 when a step fails.

## Run

On Ubuntu 24.04:

```sh
apt-get install clang curl git libboost-dev libgoogle-glog-dev libdouble-conversion-dev
bash repro.sh
```

In Docker, from this folder:

```sh
docker run --rm -v "$PWD:/repro:ro" ubuntu:24.04 bash -c "apt-get update -qq > /dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq clang curl git libboost-dev libgoogle-glog-dev libdouble-conversion-dev > /dev/null && bash /repro/repro.sh"
```

`REACT_NATIVE_DIR=<checkout> bash repro.sh` compiles against a local checkout instead of downloading `main`.
