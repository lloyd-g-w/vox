(lang dune 3.23)

(name vox)

(generate_opam_files true)

(source
 (github username/reponame))

(authors "Lloyd <hello@lloydgw.com>")

(maintainers "Lloyd <hello@lloydgw.com>")

(license LICENSE)

(documentation https://url/to/documentation)

(package
 (name vox)
 (synopsis "A short synopsis")
 (description "A longer description")
 (depends
  ocaml
  dune
  tsdl
  ctypes
  ctypes-foreign
  vulkan)
 (tags
  ("vulkan" "graphics" "voxel")))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
