;;; install-test.el --- M-x clotran-install, from nothing  -*- lexical-binding: t; -*-
;; Run by test/run.sh with INSTALL=1, under a scratch HOME and a PATH with
;; no clotran: clotran-mode finds none, `clotran-install' runs clotran's
;; install script (the release, downloaded), and the command is then found
;; where the script puts it, and runs.
;; the packages (clojure-mode) from the real HOME's Emacs, which the scratch one hides
(require 'package)
(setq package-user-dir (expand-file-name ".emacs.d/elpa" (getenv "REAL_HOME")))
(package-initialize)
(add-to-list 'load-path (getenv "CLOTRAN_MODE_DIR"))
(require 'clotran-mode)
(defvar failures 0)
(defun check (label got want)
  (if (equal got want)
      (princ (format "ok   - %s\n" label))
    (setq failures (1+ failures))
    (princ (format "FAIL - %s\n  got:  %S\n  want: %S\n" label got want))))

(check "with no clotran, none is found" (clotran--program) nil)
(let ((p (clotran-install)))
  (while (process-live-p p) (accept-process-output p 1))
  (sleep-for 0.5)
  (check "clotran-install installs it" (process-exit-status p) 0))
(check "found where the install script puts it"
       (clotran--program)
       (expand-file-name (if (eq system-type 'windows-nt)
                             "Programs/clotran/bin/clotran.cmd"
                           ".local/bin/clotran")
                         (if (eq system-type 'windows-nt) (getenv "LOCALAPPDATA") "~")))
(check "and it runs"
       (with-temp-buffer
         (let ((file (make-temp-file "clotran" nil ".cljf" "(println (+ 1 2))\n")))
           (call-process (clotran--program) nil t nil file))
         (string-trim (car (last (split-string (buffer-string) "\n" t)))))
       "3")
(princ (if (zerop failures) "INSTALL TEST PASSED\n" (format "INSTALL TEST FAILED: %d\n" failures)))
(kill-emacs (if (zerop failures) 0 1))
