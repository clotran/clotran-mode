# clotran-mode

Emacs for [clotran](../clotran) -- Clojure hosted on Fortran -- with the
stock CIDER, unmodified:

- `.cljf` files (and scripts run by `clotran`) open in `clojure-mode`, so
  CIDER's commands work in them;
- CIDER's own `M-x cider-jack-in` works in a `.cljf` buffer: clotran-mode
  sets the buffer's `cider-jack-in-cmd` to `clotran nrepl`, which resolves
  the project's `deps.edn`, starts the server
  ([clotran-nrepl](../clotran-nrepl), pinned by clotran's own `tools.edn`
  or a checkout beside it) and writes `.nrepl-port`; CIDER connects and
  owns the process. `M-x clotran-jack-in` does the same from any buffer.

- `C-c C-K` (`clotran-compile-buffer`) saves the file, loads it into
  clotran and compiles it to native code, waiting for the build, and says
  in the minibuffer how it went: compiled, nothing in it compiles, or the
  build log to read. `C-c C-k` alone compiles too, in the background.
  A `.cljf` buffer turns on the `clotran-mode` minor mode (` clotran` in
  the mode line), which holds the key.

Not a fork of CIDER: CIDER's Emacs side speaks nREPL and runs as it is;
`clotran-nrepl` is the server it talks to, as babashka's own server is for
babashka. A `.cljf` file loaded from its buffer (`C-c C-k`) runs at once,
interpreted, and is compiled to native code in the background.

## A project, quickly

    clotran new hello

then open `hello/src/hello/core.cljf` in Emacs and `M-x cider-jack-in`.

## Setup

    (load "/Users/james/clotran/clotran-mode/clotran-mode.el")

with `clotran` installed (`make install`, which brings `clotran-deps` and
the `tools.edn` that pins clotran-nrepl). `clotran-program` names the
command, `"clotran"` by default; give it a full path when Emacs's PATH
has none, as an Emacs started from the macOS Dock.

## Tests

    test/run.sh    # the real Emacs and CIDER, headless: jack-in, eval,
                   # a .cljf file loaded interpreted and then compiled

## History

This repository first held a comint mode for clotran-bin, written before
clotran had an nREPL server (the first commit); CIDER does that job now.
