# clotran-mode

Emacs for [clotran](../clotran) -- Clojure hosted on Fortran -- with the
stock CIDER, unmodified:

- `.cljf` files (and scripts run by `clotran`) open in `clojure-mode`, so
  CIDER's commands work in them;
- `M-x clotran-jack-in`, in any buffer of a project, starts clotran there
  with the nREPL server from [clotran-nrepl](../clotran-nrepl) -- the
  project's own `deps.edn` resolved by `clotran-deps` -- and connects
  CIDER to it.

Not a fork of CIDER: CIDER's Emacs side speaks nREPL and runs as it is;
`clotran-nrepl` is the server it talks to, as babashka's own server is for
babashka. A `.cljf` file loaded from its buffer (`C-c C-k`) runs at once,
interpreted, and is compiled to native code in the background.

## Setup

    (load "/Users/james/jborden/clotran-mode/clotran-mode.el")

with `clotran` and `clotran-deps` on PATH (`make install` in each), and
`clotran-nrepl-dir` pointing at the clotran-nrepl checkout (default
`~/jborden/clotran-nrepl`).

## Tests

    test/run.sh    # the real Emacs and CIDER, headless: jack-in, eval,
                   # a .cljf file loaded interpreted and then compiled

## History

This repository first held a comint mode for clotran-bin, written before
clotran had an nREPL server (the first commit); CIDER does that job now.
