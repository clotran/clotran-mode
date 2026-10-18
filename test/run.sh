#!/bin/sh
# test/run.sh -- clotran-mode in the real Emacs and CIDER, headless:
# test/jack-in-test.el. Needs an Emacs with CIDER (EMACS, else the macOS
# application, else emacs on PATH) and a clotran checkout (CLOTRAN, default
# beside this one) with clotran-deps and clotran-nrepl beside it.
here=$(cd "$(dirname "$0")/.." && pwd)
emacs=${EMACS:-}
[ -z "$emacs" ] && [ -x /Applications/Emacs.app/Contents/MacOS/Emacs ] && emacs=/Applications/Emacs.app/Contents/MacOS/Emacs
[ -z "$emacs" ] && emacs=$(command -v emacs)
[ -n "$emacs" ] || { echo "no Emacs found"; exit 1; }
out=$(mktemp) || exit 1
trap 'rm -f "$out"' EXIT
# PATH as an Emacs started from the macOS Dock has it: none of the user's
# directories, so clotran-program is the command by its full path, as a user
# there sets it, and `clotran nrepl` finds clotran-deps and clotran-nrepl beside it
echo "--- clotran-mode's own REPL and eglot, no CIDER ---"
PATH=/usr/bin:/bin CLOTRAN_MODE_DIR="$here" "$emacs" --batch \
  --eval "(setq clotran-program \"${CLOTRAN:-$here/../clotran}/clotran\")" \
  -l "$here/test/repl-test.el" >"$out" 2>&1
st=$?
grep '^ok\|^FAIL\|^  \|^note' "$out"
[ $st -eq 0 ] || { echo "CLOTRAN-MODE TESTS FAILED"; exit 1; }
if "$emacs" --batch --eval "(progn (package-initialize) (require (quote cider)))" >/dev/null 2>&1; then
  echo "--- CIDER, as it is, in a clotran buffer ---"
  PATH=/usr/bin:/bin CLOTRAN_MODE_DIR="$here" "$emacs" --batch \
    --eval "(setq clotran-program \"${CLOTRAN:-$here/../clotran}/clotran\")" \
    -l "$here/test/jack-in-test.el" >"$out" 2>&1
  st=$?
  grep '^ok\|^FAIL\|^  ' "$out"
  [ $st -eq 0 ] || { echo "CLOTRAN-MODE TESTS FAILED"; exit 1; }
else
  echo "(no CIDER in this Emacs: its check is skipped)"
fi
echo "CLOTRAN-MODE TESTS PASSED"
