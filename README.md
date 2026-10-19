# clotran-mode

Emacs for [clotran](https://github.com/clotran/clotran) -- Clojure hosted
on Fortran -- installing clojure-mode and dape with it:

- `.cljf` files open in `clotran-mode`, a `clojure-mode`, so everything
  that reads Clojure reads them;
- the language server, `clotran lsp`
  ([clotran-ide](https://github.com/clotran/clotran-ide)), through eglot,
  which Emacs 29 ships: `M-.` goes to a definition, in Clojure or in the
  Fortran of a package; `C-h .` shows the documentation; symbols,
  completion and errors as you type, with no REPL running. eglot starts
  in every clotran buffer (`clotran-eglot-auto`);
- a REPL of clotran's own: `C-c C-z` (`clotran-jack-in`) starts
  `clotran nrepl` for the project and connects to it through the small
  nREPL client in this file -- base operations only, so nothing on the
  server has to match this file's version. Then `C-x C-e` evaluates the
  form before point, `C-M-x` the top-level form around it, `C-c C-k`
  loads the file, and `C-c C-K` (`clotran-compile-buffer`) loads it and
  compiles it to native code, waiting for the build and saying how it
  went. What is printed goes to `*clotran*`; `C-c C-q` disconnects.

- in a package's `.f90` (a `package.edn` beside it or above),
  `clotran-fortran-mode` binds `C-c C-k` too: the package is built
  again from its sources, its routines replaced, its module state fresh,
  and the REPL says so;
- the debugger, through `dape` (installed with clotran-mode):
  `M-x dape` offers `clotran`,
  which debugs the buffer's file under `clotran dap` (lldb-dap
  underneath); a breakpoint in a package's Fortran stops with its line.

CIDER, when it is installed, works in a clotran buffer as it is: its
`M-x cider-jack-in` runs `clotran nrepl` too, and its keys bind over
clotran-mode's. Not a fork of CIDER, and not needed.

## Install

Emacs 29.1 or newer. Today, straight from this repository -- Emacs's
own `package-vc-install`, which installs clojure-mode and dape with it
from Emacs's default package archives; it needs git (on Windows, Git for
Windows, on PATH):

    M-x package-vc-install RET https://github.com/clotran/clotran-mode RET

or, in an init file (Emacs 30):

    (use-package clotran-mode
      :vc (:url "https://github.com/clotran/clotran-mode" :rev :newest))

Without git: it is one file. Save
https://raw.githubusercontent.com/clotran/clotran-mode/main/clotran-mode.el
and, after `M-x package-refresh-contents`, `M-x package-install-file` it,
which installs clojure-mode and dape the same way.

Then clotran itself, if the machine has none:

    M-x clotran-install

runs clotran's install script -- the release for this machine, checked
against its SHA256SUMS, into `~/.local` (on Windows
`%LOCALAPPDATA%\Programs\clotran`) -- and starts eglot in the clotran
buffers already open. clotran-mode finds the command on `exec-path` or
where that script puts it, so an Emacs started from the macOS Dock needs
no PATH set; `clotran-program` names another.

**MELPA:** clotran-mode is ready for MELPA (the recipe builds, and the
package installs and loads), which takes a package once its repository
has been public for a month: from 2026-11-17. Then it is

    M-x package-install RET clotran-mode RET

A directory holding a `deps.edn` is a project to project.el
(`project-vc-extra-root-markers`), so eglot starts the server there, as
clotran does.

## A project, quickly

    clotran new hello

then open `hello/src/hello/core.cljf` in Emacs: eglot connects, and
`C-c C-z` starts the REPL.

## Tests

    test/run.sh    # the real Emacs, headless: test/repl-test.el -- jack-in,
                   # evaluate, load, compile through clotran-mode's own
                   # client, and eglot's M-. through clotran lsp -- then
                   # test/jack-in-test.el, CIDER as it is, when there is one

## History

This repository first held a comint mode for clotran-bin, written before
clotran had an nREPL server; then CIDER's jack-in over clotran-nrepl;
now its own client and eglot (clotran's PLAN step 36).

## License

MIT (LICENSE).
