;;; dape-test.el --- the debugger's configuration  -*- lexical-binding: t; -*-
;; Run by test/run.sh: clotran-mode loaded, dape (which it requires) gets
;; the `clotran' configuration and keeps its own, and the command resolves
;; to clotran when the session starts.
(require 'package)
(package-initialize)
(add-to-list 'load-path (getenv "CLOTRAN_MODE_DIR"))
(defvar failures 0)
(defun check (label got want)
  (if (equal got want)
      (princ (format "ok   - %s\n" label))
    (setq failures (1+ failures))
    (princ (format "FAIL - %s\n  got:  %S\n  want: %S\n" label got want))))

(require 'clotran-mode)
(with-current-buffer (find-file-noselect (make-temp-file "dape-test" nil ".cljf" "(ns t)\n"))
  (check "a .cljf buffer is a clotran buffer" major-mode 'clotran-mode)
  (let ((c (assq 'clotran dape-configs)))
    (check "dape-configs has clotran" (car c) 'clotran)
    (check "and dape's own still" (and (assq 'debugpy dape-configs) t) t)
    (check "the command is clotran, found when the session starts"
           (dape--config-eval-value (plist-get (cdr c) 'command))
           (clotran--command))
    (check "and its arguments" (plist-get (cdr c) 'command-args) '("dap")))
  (load "clotran-mode" nil t)
  (check "loaded again, still once" (length (seq-filter (lambda (e) (eq (car e) 'clotran)) dape-configs)) 1))
(princ (if (zerop failures) "DAPE TEST PASSED\n" (format "DAPE TEST FAILED: %d\n" failures)))
(kill-emacs (if (zerop failures) 0 1))
