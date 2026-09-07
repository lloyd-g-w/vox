(lang dune 3.23)

(name vox)

(generate_opam_files true)

(source
 (github lloyd-g-w/vox))

(authors "Lloyd <hello@lloydgw.com>")

(maintainers "Lloyd <hello@lloydgw.com>")

(license GPL-3.0-only)

(documentation https://github.com/lloyd-g-w/vox)

(package
 (name vox)
 (synopsis "A voxel engine in OCaml, rendering with WebGPU (wgpu-native) and SDL2")
 (description
  "An experimental voxel engine written in OCaml. Windowing and input come from SDL2 (tsdl); rendering goes through WebGPU via the wgpu-ocaml bindings to wgpu-native.")
 (depends
  (ocaml
   (>= 5.2.0))
  (dune
   (>= 3.23))
  tsdl
  ctypes
  ctypes-foreign
  wgpu)
 (tags
  ("webgpu" "wgpu" "graphics" "voxel")))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
