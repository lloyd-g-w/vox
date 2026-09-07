# vox

An experimental voxel engine written in OCaml, rendering through
[WebGPU](https://www.w3.org/TR/webgpu/) via
[wgpu-native](https://github.com/gfx-rs/wgpu-native) and using
[SDL2](https://www.libsdl.org/) for windowing and input.

> ⚠️ Early work in progress — an SDL2 window and the `wgpu` dependency are
> wired up; the renderer itself has not been written yet. Not a game.

## Dependencies

### OCaml packages

Managed through opam / dune (OCaml `>= 5.2.0`, `dune >= 3.23`):

| Package           | Purpose                                                        |
| ----------------- | ------------------------------------------------------------- |
| `ocaml`           | Compiler / runtime                                            |
| `dune`            | Build system                                                  |
| `tsdl`            | OCaml bindings to SDL2 (windowing, input, 2D rendering)       |
| `ctypes`          | C interop                                                     |
| `ctypes-foreign`  | Foreign function interface for `ctypes`                       |
| `wgpu`            | WebGPU bindings — see note below                              |

The `wgpu` package is [wgpu-ocaml](https://github.com/lloyd-g-w/wgpu-ocaml):
raw OCaml bindings to `webgpu.h` / `wgpu.h`, plus a tiny `wgpu.utils`
helper library. It is not on the public opam repository, so the exact commit
this tree builds against is pinned in `vox.opam.template` (`pin-depends`),
and `opam install . --deps-only` picks it up automatically:

```sh
opam install . --deps-only --with-test
```

To move to a newer bindings commit, change the hash in `vox.opam.template`,
run `dune build` (then `dune promote` if it reports an opam-file diff), and
re-run `opam install . --deps-only`.

### The wgpu-native shared library

The bindings contain no C stubs: `libwgpu_native.so` is `dlopen`ed at run
time, and the bindings refuse to load a version other than the one they were
generated for (currently **wgpu-native v29.0.1.1**). The easiest way to get
the right build is the bindings' own pinned, checksummed downloader:

```sh
git clone https://github.com/lloyd-g-w/wgpu-ocaml /tmp/wgpu-ocaml
cd /tmp/wgpu-ocaml && dune build && dune exec scripts/fetch_wgpu_native.exe
```

That installs into `~/.cache/wgpu-ocaml/wgpu-native-<version>/lib/`, which
is where the loader looks by default. To point at a library somewhere else,
set `WGPU_NATIVE_LIB=/path/to/libwgpu_native.so` (or `WGPU_NATIVE_LIB_DIR`).

On Linux, wgpu-native renders through Vulkan, so a Vulkan loader and driver
must be present. On a machine with no GPU, Mesa's `lavapipe` software
rasteriser works:

```sh
export VK_ICD_FILENAMES="$(find /usr/share/vulkan/icd.d -name 'lvp_icd*.json' -print -quit)"
```

### System / native libraries

Provided by the Nix dev shell (see `flake.nix`):

- **SDL2** — windowing and input
- **vulkan-loader**, **vulkan-tools** — the Vulkan backend wgpu-native uses on
  Linux, and `vulkaninfo` (the hardware driver / ICD comes from the host)
- **curl**, **unzip** — used by wgpu-ocaml's `fetch_wgpu_native` script
- Build tooling: `opam`, `gmp`, `autoconf`, `which`, `libffi`, `pkg-config`

On Debian/Ubuntu without Nix:

```sh
sudo apt install build-essential pkg-config libffi-dev libsdl2-dev \
  libvulkan1 mesa-vulkan-drivers vulkan-tools curl unzip
```

Shaders are written in WGSL and compiled by wgpu-native at run time, so no
shader compiler (`glslang`, `shaderc`) is needed.

## Getting started

With [Nix](https://nixos.org/) (flakes enabled), the dev shell provides every
native dependency and sets `LD_LIBRARY_PATH` for the Vulkan loader and SDL2:

```sh
nix develop
```

Then set up the OCaml side (first time only):

```sh
opam switch create . 5.2.0        # or reuse an existing >= 5.2.0 switch
eval "$(opam env)"
opam install . --deps-only --with-test
```

and fetch `libwgpu_native` as described above. Build:

```sh
dune build
```

## Running

Main executable:

```sh
dune exec vox
```

Test / smoke executables (under `test/`):

```sh
dune exec test/sdl_draw.exe    # open an SDL2 window and draw a rectangle
dune test                      # run the test suite
```

## Project layout

```
bin/    # main executable entry point (main.ml)
lib/    # vox library (engine code)
        #   error.ml            — shared error type
        #   engine.ml           — entry point used by bin/main.ml
        #   platform/window.ml  — SDL2 window lifecycle
test/   # smoke tests and experiments
        #   sdl_draw.ml  — SDL2 rendering check
        #   test_vox.ml  — library tests
flake.nix  # Nix dev shell with native deps
```

## License

See [LICENSE](LICENSE).
