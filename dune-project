(lang dune 3.3)

(name ocaml_runtime_stats)

(generate_opam_files true)

(source
 (github kayceesrk/ocaml_runtime_stats))

(authors "KC Sivaramakrishnan")

(maintainers "KC Sivaramakrishnan")

(license MIT)

(documentation https://url/to/documentation)

(package
 (name ocaml_runtime_stats)
 (synopsis "Runtime stats of OCaml programs")
 (description "Runtime stats of OCaml programs")
 (depends ocaml dune hdr_histogram)
 (tags
  ("profiling" "tail latency")))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/dune-files.html#dune-project
