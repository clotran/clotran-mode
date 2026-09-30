;;; clotran-mode.el --- REPL interaction for clotran  -*- lexical-binding: t; -*-

;; Syntax highlighting: nothing to do here, `clojure-mode' already
;; covers it -- clotran's reader is close enough to Clojure's that
;; reinventing a major mode would just be duplicating clojure-mode.
;; This file adds the one thing it doesn't have: a REPL process and
;; ways to push buffer code into it.
;;
;; Why not inf-clojure/CIDER: both assume a REPL close enough to real
;; Clojure to run its introspection (doc/complete/nrepl) or its own
;; startup forms; clotran-bin has none of that. More importantly,
;; clotran-bin's REPL reads one *line* == one form at a time (see
;; src/f/readline.f90 + main.f90's interactive_repl) -- a multi-line
;; form sent as raw text over stdin would break mid-read. `load-file`,
;; by contrast, slurps its whole argument file in a single read_str
;; call and handles multi-line forms and comments fine
;; (src/f/Eval.f90's eval_load_file_head). So every "send this code"
;; command below funnels through a temp file + (load-file "...")
;; rather than sending text directly -- one mechanism, and it's the
;; same one that already handles the load/reload-a-file case.
;;
;; Not wired into `clojure-mode-hook' globally -- that would turn this
;; on (and shadow cider's bindings) in every other Clojure project too.
;; Turn it on per-project instead, e.g. via this repo's .dir-locals.el.

(require 'comint)

(defgroup clotran nil
  "Run and interact with a clotran REPL."
  :group 'languages)

(defcustom clotran-program nil
  "Path to the clotran-bin executable.
When nil, `run-clotran' looks for a `clotran-bin' file at or above
`default-directory'.

Talks to clotran-bin directly, not the rlwrap-wrapping `clotran`
launcher: comint provides its own line editing/history, and rlwrap
would just fight it for the tty (the project's own regression suite
runs against clotran-bin for the same reason; see README.md)."
  :type '(choice (const nil) file)
  :group 'clotran)

(defcustom clotran-prompt-regexp "^user> "
  "Regexp matching clotran-bin's prompt."
  :type 'regexp
  :group 'clotran)

(defvar clotran-buffer-name "*clotran*")

(define-derived-mode clotran-repl-mode comint-mode "Clotran REPL"
  "Major mode for an inferior clotran process."
  (setq comint-prompt-regexp clotran-prompt-regexp))

(defun clotran--find-program ()
  (or clotran-program
      (let ((dir (locate-dominating-file default-directory "clotran-bin")))
        (and dir (expand-file-name "clotran-bin" dir)))
      (read-file-name "Path to clotran-bin: ")))

;;;###autoload
(defun run-clotran ()
  "Start (or switch to) the clotran REPL."
  (interactive)
  (let ((buf (get-buffer-create clotran-buffer-name)))
    (unless (comint-check-proc buf)
      (with-current-buffer buf
        (make-comint-in-buffer "clotran" buf (clotran--find-program))
        (clotran-repl-mode)))
    (pop-to-buffer buf)))

(defun clotran--repl-buffer ()
  (or (get-buffer clotran-buffer-name)
      (user-error "No clotran REPL running; M-x run-clotran first")))

(defun clotran-switch-to-repl ()
  "Switch to the clotran REPL buffer."
  (interactive)
  (pop-to-buffer (clotran--repl-buffer)))

(defun clotran--send (line)
  "Send LINE (one already-complete line of text) to the REPL."
  (let ((buf (clotran--repl-buffer)))
    (comint-send-string (get-buffer-process buf) (concat line "\n"))
    (display-buffer buf)))

(defun clotran--send-via-load-file (code)
  "Write CODE to a temp file and have the REPL `load-file' it.
Sidesteps clotran-bin's one-line-per-form stdin reader for anything
spanning more than one line -- see the commentary at the top of this
file."
  (let ((file (make-temp-file "clotran-eval" nil ".clj")))
    (with-temp-file file (insert code))
    (clotran--send (format "(load-file %S)" file))))

(defun clotran-eval-region (start end)
  "Evaluate the region in the clotran REPL."
  (interactive "r")
  (clotran--send-via-load-file (buffer-substring-no-properties start end)))

(defun clotran-eval-buffer ()
  "Evaluate the whole current buffer in the clotran REPL."
  (interactive)
  (clotran-eval-region (point-min) (point-max)))

(defun clotran-eval-defun ()
  "Evaluate the top-level form at point in the clotran REPL."
  (interactive)
  (save-excursion
    (end-of-defun)
    (let ((end (point)))
      (beginning-of-defun)
      (clotran-eval-region (point) end))))

(defun clotran-eval-last-sexp ()
  "Evaluate the sexp before point in the clotran REPL."
  (interactive)
  (clotran-eval-region (save-excursion (backward-sexp) (point)) (point)))

(defun clotran-load-file (file)
  "Load FILE into the running clotran REPL.
Reloading is just calling this again: if FILE opens with its own
\(in-ns \\='some.ns) form, load-file naturally (re)switches to that
namespace when it runs, same as real Clojure's `load'/`ns' interplay
-- there's no separate namespace bookkeeping to do here."
  (interactive (list (or buffer-file-name (read-file-name "Load file: "))))
  (clotran--send (format "(load-file %S)" (expand-file-name file))))

(defvar clotran-minor-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-z") #'clotran-switch-to-repl)
    (define-key map (kbd "C-x C-e") #'clotran-eval-last-sexp)
    (define-key map (kbd "C-M-x")   #'clotran-eval-defun)
    (define-key map (kbd "C-c C-r") #'clotran-eval-region)
    (define-key map (kbd "C-c C-b") #'clotran-eval-buffer)
    (define-key map (kbd "C-c C-l") #'clotran-load-file)
    map)
  "Keymap for `clotran-minor-mode' (bindings mirror cider/inf-clojure).")

;;;###autoload
(define-minor-mode clotran-minor-mode
  "Minor mode adding clotran REPL interaction to a `clojure-mode' buffer."
  :lighter " Clotran"
  :keymap clotran-minor-mode-map)

(provide 'clotran-mode)
;;; clotran-mode.el ends here
