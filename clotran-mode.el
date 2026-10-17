;;; clotran-mode.el --- Emacs for clotran: .cljf files and CIDER jack-in  -*- lexical-binding: t; -*-

;; clotran is Clojure hosted on Fortran (~/clotran/clotran). Its source
;; files are .cljf: Clojure's syntax, so they open in clojure-mode, and
;; CIDER works in them. CIDER talks to clotran through the nREPL server
;; in ~/clotran/clotran-nrepl, which is what `clotran-jack-in' starts.
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

(defcustom clotran-nrepl-dir (expand-file-name "~/clotran/clotran-nrepl")
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
;; starts clotran, and CIDER owns the process as it would clj's.

(defun clotran--nrepl-command ()
  (expand-file-name "bin/clotran-nrepl" clotran-nrepl-dir))

(defun clotran-jack-in ()
  "CIDER's jack-in with clotran, from any buffer of a project."
  (interactive)
  (let ((cider-jack-in-cmd (clotran--nrepl-command)))
    (cider-jack-in-clj nil)))

;;; compiling a buffer to native code

(defun clotran-compile-buffer ()
  "Save this file, load it into clotran, and compile it to native code,
waiting for the build: the compiled functions replace the interpreted
ones. Says in the minibuffer what came of it, and answers the build's
state (`installed', `none', `failed', ...). `cider-load-buffer' alone
compiles too, in the background."
  (interactive)
  (unless buffer-file-name (user-error "clotran: this buffer has no file to compile"))
  (unless (cider-connected-p) (user-error "clotran: not connected -- M-x cider-jack-in first"))
  (save-buffer)
  (let* ((file (expand-file-name buffer-file-name))
         (name (file-name-nondirectory file))
         (form (format (concat "(do (clojure.core/load-file %S)"
                               " (let [st (clotran.loader/compile-now %S)]"
                               "   [st (:log (get @@(resolve (quote clotran.loader/builds)) %S))]))")
                       file file file))
         (response (progn (message "clotran: compiling %s..." name)
                          (cider-nrepl-sync-request:eval form)))
         (err (nrepl-dict-get response "err"))
         (value (nrepl-dict-get response "value")))
    (cond
     (err (message "clotran: %s did not load: %s" name (string-trim err)) 'error)
     ((and value (string-match "\\`\\[:\\([a-z]+\\) \\(.*\\)\\]\\'" value))
      (let ((state (match-string 1 value))
            (log (match-string 2 value)))
        (pcase state
          ("installed" (message "clotran: %s is compiled" name))
          ("none" (message "clotran: nothing in %s compiles; it runs interpreted" name))
          (_ (message "clotran: %s did not compile (%s); see %s" name state log)))
        (intern state)))
     (t (message "clotran: no answer from compiling %s" name) nil))))

(defvar clotran-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "C-c C-S-k") #'clotran-compile-buffer)
    m)
  "C-c C-K: load and compile this file -- C-c C-k, harder.")

(define-minor-mode clotran-mode
  "clotran in a .cljf buffer: CIDER's jack-in starts clotran, and
\\[clotran-compile-buffer] compiles the file to native code."
  :lighter " clotran"
  :keymap clotran-mode-map
  (when clotran-mode
    (setq-local cider-jack-in-cmd (clotran--nrepl-command))))

(defun clotran--setup-buffer ()
  "A .cljf buffer is a clotran buffer."
  (when (and buffer-file-name (string-suffix-p ".cljf" buffer-file-name))
    (clotran-mode 1)))

(add-hook 'clojure-mode-hook #'clotran--setup-buffer)

(provide 'clotran-mode)
;;; clotran-mode.el ends here
