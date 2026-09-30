#!/bin/sh
# test/run.sh -- clotran-mode in the real Emacs and CIDER, headless:
# test/jack-in-test.el. Needs an Emacs with CIDER (EMACS, else the macOS
# application, else emacs on PATH), clotran and clotran-deps on PATH, and
# clotran-nrepl (CLOTRAN_NREPL_DIR, default beside this checkout).
here=$(cd "$(dirname "$0")/.." && pwd)
emacs=${EMACS:-}
[ -z "$emacs" ] && [ -x /Applications/Emacs.app/Contents/MacOS/Emacs ] && emacs=/Applications/Emacs.app/Contents/MacOS/Emacs
[ -z "$emacs" ] && emacs=$(command -v emacs)
[ -n "$emacs" ] || { echo "no Emacs found"; exit 1; }
out=$(mktemp) || exit 1
trap 'rm -f "$out"' EXIT
CLOTRAN_MODE_DIR="$here" "$emacs" --batch \
  --eval "(setq clotran-nrepl-dir \"${CLOTRAN_NREPL_DIR:-$here/../clotran-nrepl}\")" \
  -l "$here/test/jack-in-test.el" >"$out" 2>&1
st=$?
grep '^ok\|^FAIL\|^  ' "$out"
[ $st -eq 0 ] && echo "CLOTRAN-MODE TESTS PASSED" || { echo "CLOTRAN-MODE TESTS FAILED"; exit 1; }
