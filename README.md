# vox

An experimental voxel engine written in OCaml, using [Vulkan](https://www.vulkan.org/)
for rendering and [SDL2](https://www.libsdl.org/) for windowing and input.

> ⚠️ Early work in progress — currently smoke tests for the Vulkan bindings and
> SDL rendering, not yet a game.

## Dependencies

### OCaml packages

Managed through opam / dune (`5.2.0+ox` switch, `dune >= 3.23`):

| Package           | Purpose                                                        |
| ----------------- | ------------------------------------------------------------- |
| `ocaml`           | Compiler / runtime                                            |
| `dune`            | Build system                                                  |
| `tsdl`            | OCaml bindings to SDL2 (windowing, input, 2D rendering)       |
| `ctypes`          | C interop                                                     |
| `ctypes-foreign`  | Foreign function interface for `ctypes`                       |
| `vulkan`          | Vulkan bindings — see note below                              |

The `vulkan` package is a custom bindings library, pinned to a git repo rather
than pulled from the public opam repository:

```
opam pin vulkan git+ssh://git@github.com/lloyd-g-w/ocaml-vulkan.git
```

(Access is over SSH, so a GitHub SSH key is required. To refresh to the latest
commit later: `opam update vulkan && opam upgrade vulkan`.)

### System / native libraries

Provided by the Nix dev shell (see `flake.nix`):

- **SDL2** — windowing and input
- **vulkan-loader**, **vulkan-headers**, **vulkan-tools**, **vulkan-validation-layers** — Vulkan runtime, dev headers, and `vulkaninfo`
- **shaderc**, **glslang** — GLSL → SPIR-V shader compilation
- Build tooling: `opam`, `gmp`, `autoconf`, `which`, `libffi`, `pkg-config`

## Getting started

With [Nix](https://nixos.org/) (flakes enabled), the dev shell provides every
native dependency and sets `LD_LIBRARY_PATH` for the Vulkan loader and SDL2:

```sh
nix develop
```

Then set up the OCaml side (first time only):

```sh
opam install . --deps-only
opam pin vulkan git+ssh://git@github.com/lloyd-g-w/ocaml-vulkan.git
```

Build:

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
dune exec test/vk_smoke.exe    # enumerate Vulkan physical devices via the bindings
dune exec test/sdl_draw.exe    # open an SDL2 window and draw a rectangle
dune test                      # run the test suite
```

## Project layout

```
bin/    # main executable entry point (main.ml)
lib/    # vox library (engine code)
test/   # smoke tests and experiments
        #   vk_smoke.ml  — Vulkan bindings check
        #   sdl_draw.ml  — SDL2 rendering check
        #   test_vox.ml  — library tests
flake.nix  # Nix dev shell with native deps
```

## License

See [LICENSE](LICENSE).
