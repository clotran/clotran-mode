;;; clotran-mode.el --- Emacs for clotran: .cljf files and CIDER jack-in  -*- lexical-binding: t; -*-

;; clotran is Clojure hosted on Fortran (~/jborden/clotran). Its source
;; files are .cljf: Clojure's syntax, so they open in clojure-mode, and
;; CIDER works in them. CIDER talks to clotran through the nREPL server
;; in ~/jborden/clotran-nrepl, which is what `clotran-jack-in' starts.
;;
;;   (load "/path/to/clotran-mode/clotran-mode.el")
;;
;; then, in a .cljf buffer of a project, M-x cider-jack-in -- or, from any
;; buffer, M-x clotran-jack-in.
;;
;; This replaces the comint mode that lived here before clotran had an
;; nREPL server (see this repository's history).

(require 'clojure-mode)
(require 'cider)

(defgroup clotran nil
  "clotran: Clojure hosted on Fortran."
  :group 'languages)

(defcustom clotran-nrepl-dir (expand-file-name "~/jborden/clotran-nrepl")
  "The clotran-nrepl checkout whose bin/clotran-nrepl CIDER's jack-in runs."
  :type 'directory)

;;; .cljf files are Clojure

(add-to-list 'auto-mode-alist '("\\.cljf\\'" . clojure-mode))
(add-to-list 'interpreter-mode-alist '("clotran" . clojure-mode))

;;; jack-in: CIDER's own

;; CIDER's jack-in runs a project's `cider-jack-in-cmd' when one is set, and
;; connects when it prints "nREPL server started on port N" -- which
;; clotran-nrepl's bin/clotran-nrepl does, after resolving the project's
;; deps.edn with clotran-deps. So in a .cljf buffer plain M-x cider-jack-in
;; starts clotran, and CIDER owns the process as it would a JVM's.

(defun clotran--nrepl-command ()
  (expand-file-name "bin/clotran-nrepl" clotran-nrepl-dir))

(defun clotran--setup-buffer ()
  "In a .cljf buffer, CIDER's jack-in starts clotran."
  (when (and buffer-file-name (string-suffix-p ".cljf" buffer-file-name))
    (setq-local cider-jack-in-cmd (clotran--nrepl-command))))

(add-hook 'clojure-mode-hook #'clotran--setup-buffer)

(defun clotran-jack-in ()
  "CIDER's jack-in with clotran, from any buffer of a project."
  (interactive)
  (let ((cider-jack-in-cmd (clotran--nrepl-command)))
    (cider-jack-in-clj nil)))

(provide 'clotran-mode)
;;; clotran-mode.el ends here
