;;; clotran-mode.el --- Major mode for clotran: .cljf, its LSP and REPL  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 James Borden
;; Author: James Borden
;; SPDX-License-Identifier: MIT
;; URL: https://github.com/clotran/clotran-mode
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (clojure-mode "5.0") (dape "0.14"))
;; Keywords: languages, lisp, tools

;;; Commentary:

;; clotran is Clojure hosted on Fortran (github.com/clotran/clotran).  Its
;; source files are .cljf: Clojure's syntax, so `clotran-mode' is
;; `clojure-mode' derived, and what reads Clojure reads them.  On top of
;; it, two things of clotran's own, neither needing CIDER:
;;
;; - the language server, `clotran lsp' (github.com/clotran/clotran-ide),
;;   through eglot, which Emacs 29 ships: definitions into Clojure and
;;   into a package's Fortran, documentation, symbols, completion, errors
;;   as you type -- with no REPL running;
;; - a REPL: `clotran-jack-in' starts `clotran nrepl' for the project and
;;   connects to it with the small nREPL client below (base operations
;;   only, so nothing on the server has to match this file's version);
;;   then C-x C-e, C-M-x, C-c C-k and C-c C-K evaluate, load and compile.
;;
;;   (load "/path/to/clotran-mode/clotran-mode.el")
;;
;; CIDER, when installed, still works in a clotran buffer as it is: its
;; `M-x cider-jack-in' runs `clotran nrepl' too.

;;; Code:

(require 'clojure-mode)
(require 'eglot)
(require 'project)
(require 'dape)
(require 'cl-lib)
(require 'subr-x)

(defgroup clotran nil
  "Settings for clotran, Clojure hosted on Fortran."
  :group 'languages)

(defcustom clotran-program "clotran"
  "The clotran command.
A full path when Emacs's PATH has none, as an Emacs started from the
macOS Dock."
  :type 'string)

(defcustom clotran-eglot-auto t
  "Non-nil means start eglot, with `clotran lsp', in every clotran buffer.
Only when eglot is available."
  :type 'boolean)

(declare-function cider-connected-p "cider-connection")
(declare-function cider-nrepl-sync-request:eval "cider-client")
(declare-function nrepl-dict-get "nrepl-dict")

;;; finding clotran, and installing it

(defun clotran--program ()
  "Return the clotran command as a full path, or nil when there is none.
`clotran-program' found on variable `exec-path', else where clotran's
install scripts put it (an Emacs started from the Dock or the Start menu
often has no ~/.local/bin on its PATH)."
  (or (executable-find clotran-program)
      (cl-find-if #'file-executable-p
                  (if (eq system-type 'windows-nt)
                      (list (expand-file-name "Programs/clotran/bin/clotran.cmd" (getenv "LOCALAPPDATA")))
                    (list (expand-file-name "~/.local/bin/clotran"))))))

(defun clotran--command ()
  "Return the command to run: found, or `clotran-program' as given."
  (or (clotran--program) clotran-program))

(defconst clotran--install-command
  (if (eq system-type 'windows-nt)
      '("powershell" "-NoProfile" "-ExecutionPolicy" "Bypass" "-Command"
        "irm https://raw.githubusercontent.com/clotran/clotran/main/install.ps1 | iex")
    '("sh" "-c" "curl -fsSL https://raw.githubusercontent.com/clotran/clotran/main/install.sh | sh"))
  "Command that runs clotran's own install script, as its README gives it.")

;;;###autoload
(defun clotran-install ()
  "Install clotran with its install script, then start eglot in clotran buffers.
The script fetches the release for this machine, checks it against its
SHA256SUMS and puts it where a terminal finds it too; its output goes
in *clotran install*."
  (interactive)
  (let ((buf (get-buffer-create "*clotran install*")))
    (with-current-buffer buf (erase-buffer))
    (display-buffer buf)
    (message "clotran: installing...")
    (make-process
     :name "clotran install" :buffer buf :command clotran--install-command :noquery t
     :sentinel (lambda (p _event)
                 (unless (process-live-p p)
                   (if (and (zerop (process-exit-status p)) (clotran--program))
                       (progn
                         (message "clotran: installed, %s" (clotran--program))
                         (when (and clotran-eglot-auto (fboundp 'eglot-ensure))
                           (dolist (b (buffer-list))
                             (with-current-buffer b
                               (when (and (derived-mode-p 'clotran-mode) (buffer-file-name))
                                 (eglot-ensure))))))
                     (message "clotran: the install failed; *clotran install* says why")))))))

;;; .cljf files are clotran buffers

(defun clotran--nrepl-command ()
  "Return the shell command to run `clotran nrepl'."
  (concat (shell-quote-argument (clotran--command)) " nrepl"))

(defvar clotran-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "C-c C-z") #'clotran-jack-in)
    (define-key m (kbd "C-x C-e") #'clotran-eval-last-sexp)
    (define-key m (kbd "C-c C-e") #'clotran-eval-last-sexp)
    (define-key m (kbd "C-M-x") #'clotran-eval-defun)
    (define-key m (kbd "C-c C-c") #'clotran-eval-defun)
    (define-key m (kbd "C-c C-k") #'clotran-load-buffer)
    (define-key m (kbd "C-c C-S-k") #'clotran-compile-buffer)
    (define-key m (kbd "C-c C-q") #'clotran-quit)
    m)
  "Keys of `clotran-mode': the REPL of its own.
CIDER's minor mode, when it is on, binds over them.")

;;;###autoload
(define-derived-mode clotran-mode clojure-mode "clotran"
  "Major mode for clotran's .cljf files.
It is `clojure-mode', with the language server through eglot and a REPL
of clotran's own.

\\{clotran-mode-map}"
  ;; CIDER's jack-in, when CIDER is there, runs clotran nrepl
  (setq-local cider-jack-in-cmd (clotran--nrepl-command))
  (if (not (clotran--program))
      (message "clotran is not installed: M-x clotran-install installs it")
    (when (and clotran-eglot-auto (fboundp 'eglot-ensure) (buffer-file-name))
      (eglot-ensure))))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.cljf\\'" . clotran-mode))
;;;###autoload
(add-to-list 'interpreter-mode-alist '("clotran" . clotran-mode))

;;; a package's Fortran: C-c C-k there rebuilds the package

(defvar clotran-fortran-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "C-c C-z") #'clotran-jack-in)
    (define-key m (kbd "C-c C-k") #'clotran-load-buffer)
    m)
  "Keys of `clotran-fortran-mode'.")

(define-minor-mode clotran-fortran-mode
  "Minor mode for a Fortran buffer of a clotran package.
The package has a package.edn beside the file or above it.
\\<clotran-fortran-mode-map>\\[clotran-load-buffer] saves the file and
loads it -- the package is built again from its sources, its routines
replaced, its module state fresh, and the REPL says so."
  :lighter " clotran"
  :keymap clotran-fortran-mode-map)

(defun clotran--fortran-setup ()
  "Turn on `clotran-fortran-mode' in a clotran package's Fortran."
  (when (and buffer-file-name (locate-dominating-file buffer-file-name "package.edn"))
    (clotran-fortran-mode 1)))

(add-hook 'f90-mode-hook #'clotran--fortran-setup)
(add-hook 'fortran-mode-hook #'clotran--fortran-setup)

;;; the debugger, through dape

;; dape (an Emacs DAP client) gets a configuration: M-x dape, then
;; `clotran' -- the file in the buffer debugged under `clotran dap', which
;; drives lldb-dap underneath; a breakpoint in a package's Fortran stops
;; with its source line.
(add-to-list 'dape-configs
             '(clotran
               modes (clotran-mode f90-mode fortran-mode)
               ;; a function, so dape finds clotran when the session starts
               command clotran--command
               command-args ("dap")
               command-cwd dape-command-cwd
               :type "clotran"
               :request "launch"
               :program dape-buffer-default
               :cwd dape-cwd))

;;; the language server, through eglot

(defun clotran--lsp-contact (_interactive)
  "Return the server command for eglot: `clotran lsp', in the project's directory."
  (list (clotran--command) "lsp"))

(add-to-list 'eglot-server-programs '(clotran-mode . clotran--lsp-contact))

;; a directory with a deps.edn is a project, as it is for clotran: eglot
;; starts the server there, where `clotran lsp' reads the project's path
(add-to-list 'project-vc-extra-root-markers "deps.edn")

;;; an nREPL client, the base operations only
;;
;; bencode, as nREPL carries it: integers i42e, strings by their BYTE
;; length 3:foo, lists l...e, dictionaries d...e with string keys. A
;; message is encoded to a unibyte string and sent whole; what comes
;; back is decoded whole message by whole message, the rest kept for the
;; next chunk.

(defun clotran--bencode (x)
  "Return X as bencode, a unibyte string.
X is a string, an integer, a list, or an alist with string keys."
  (cond
   ((stringp x) (let ((b (encode-coding-string x 'utf-8)))
                  (concat (number-to-string (length b)) ":" b)))
   ((integerp x) (format "i%de" x))
   ((and (consp x) (consp (car x)) (stringp (caar x)))
    (concat "d" (mapconcat (lambda (kv) (concat (clotran--bencode (car kv)) (clotran--bencode (cdr kv))))
                           (sort (copy-sequence x) (lambda (a b) (string< (car a) (car b)))) "")
            "e"))
   ((listp x) (concat "l" (mapconcat #'clotran--bencode x "") "e"))
   (t (error "clotran: no bencode for %S" x))))

(defun clotran--bdecode (s pos)
  "Return the value in unibyte string S at POS as (VALUE . NEXT-POS).
Nil when the value is not all there yet.  Strings come back decoded
from UTF-8, dictionaries as alists, lists as lists."
  (when (< pos (length s))
    (let ((c (aref s pos)))
      (cond
       ((= c ?i) (let ((e (string-search "e" s pos)))
                   (when e (cons (string-to-number (substring s (1+ pos) e)) (1+ e)))))
       ((and (>= c ?0) (<= c ?9))
        (let ((colon (string-search ":" s pos)))
          (when colon
            (let* ((n (string-to-number (substring s pos colon)))
                   (end (+ colon 1 n)))
              (when (<= end (length s))
                (cons (decode-coding-string (substring s (1+ colon) end) 'utf-8) end))))))
       ((memq c '(?l ?d))
        (let ((items nil) (p (1+ pos)) (done nil) (short nil))
          (while (and (not done) (not short))
            (cond ((>= p (length s)) (setq short t))
                  ((= (aref s p) ?e) (setq done t p (1+ p)))
                  (t (let ((r (clotran--bdecode s p)))
                       (if r (progn (push (car r) items) (setq p (cdr r))) (setq short t))))))
          (unless short
            (let ((vals (nreverse items)))
              (cons (if (= c ?l) vals
                      (let (al) (while vals (push (cons (pop vals) (pop vals)) al)) (nreverse al)))
                    p)))))
       (t (error "clotran: bad bencode at %d" pos))))))

(defvar clotran--conn nil "The connection to the nREPL server, a process.")
(defvar clotran--server nil "The `clotran nrepl' process this Emacs started, if it did.")
(defvar clotran--session nil "The nREPL session on `clotran--conn'.")
(defvar clotran--pending (make-hash-table :test 'equal) "Request id -> the function taking each reply.")
(defvar clotran--incoming "" "Bytes received and not yet decoded.")
(defvar clotran--next-id 0 "The last request id used.")

(defun clotran--connected-p ()
  "Return non-nil when connected to an nREPL server."
  (and clotran--conn (process-live-p clotran--conn)))

(defun clotran--filter (_proc chunk)
  "Decode CHUNK's whole messages and hand each to its request's function."
  (setq clotran--incoming (concat clotran--incoming chunk))
  (let (r)
    (while (setq r (and (> (length clotran--incoming) 0) (clotran--bdecode clotran--incoming 0)))
      (setq clotran--incoming (substring clotran--incoming (cdr r)))
      (let* ((msg (car r))
             (id (cdr (assoc "id" msg)))
             (f (gethash id clotran--pending)))
        (when f
          (when (member "done" (cdr (assoc "status" msg))) (remhash id clotran--pending))
          (funcall f msg))))))

(defun clotran--send (msg on-reply)
  "Send MSG, an alist, with an id and the session.
ON-REPLY takes each reply until one carries status done."
  (unless (clotran--connected-p) (user-error "clotran: not connected -- C-c C-z (clotran-jack-in) first"))
  (let ((id (number-to-string (cl-incf clotran--next-id))))
    (puthash id on-reply clotran--pending)
    (process-send-string clotran--conn
                         (clotran--bencode (append `(("id" . ,id))
                                                   (when clotran--session `(("session" . ,clotran--session)))
                                                   msg)))
    id))

(defun clotran--request-sync (msg &optional secs)
  "Send MSG and wait up to SECS (30) for its replies, combined.
The values in order under \"value\", out and err concatenated, every
status."
  (let ((replies nil) (done nil))
    (clotran--send msg (lambda (m) (push m replies) (when (member "done" (cdr (assoc "status" m))) (setq done t))))
    (let ((n 0))
      (while (and (not done) (< n (* 10 (or secs 30))))
        (accept-process-output clotran--conn 0.1)
        (setq n (1+ n))))
    (unless done (error "clotran: no answer from the server in %d s" (or secs 30)))
    (let ((rs (nreverse replies)))
      `(("value" . ,(delq nil (mapcar (lambda (m) (cdr (assoc "value" m))) rs)))
        ("out" . ,(apply #'concat (mapcar (lambda (m) (cdr (assoc "out" m))) rs)))
        ("err" . ,(apply #'concat (mapcar (lambda (m) (cdr (assoc "err" m))) rs)))
        ("ex" . ,(cl-some (lambda (m) (cdr (assoc "ex" m))) rs))
        ("new-session" . ,(cl-some (lambda (m) (cdr (assoc "new-session" m))) rs))
        ("status" . ,(apply #'append (mapcar (lambda (m) (cdr (assoc "status" m))) rs)))))))

(defun clotran-connect (port)
  "Connect to the nREPL server on PORT of this machine and open a session."
  (interactive "nnREPL port: ")
  (when (clotran--connected-p) (delete-process clotran--conn))
  (setq clotran--incoming "" clotran--session nil)
  (clrhash clotran--pending)
  (setq clotran--conn (open-network-stream "clotran-nrepl" nil "127.0.0.1" port :coding 'binary))
  (set-process-query-on-exit-flag clotran--conn nil)
  (set-process-filter clotran--conn #'clotran--filter)
  (let ((session (cdr (assoc "new-session" (clotran--request-sync '(("op" . "clone")) 10)))))
    (unless session (error "clotran: the server gave no session"))
    (setq clotran--session session))
  (message "clotran: connected to nREPL on port %d" port)
  clotran--conn)

(defun clotran--project-root ()
  "Return the directory with the deps.edn above this buffer's file.
Else the file's directory, else `default-directory'."
  (or (and buffer-file-name (locate-dominating-file buffer-file-name "deps.edn"))
      (and buffer-file-name (file-name-directory buffer-file-name))
      default-directory))

(defun clotran-jack-in ()
  "Start `clotran nrepl' for this buffer's project and connect to it.
Connected already: say so."
  (interactive)
  (if (clotran--connected-p)
      (message "clotran: connected (C-c C-q quits)")
    (let* ((default-directory (clotran--project-root))
           (proc (make-process :name "clotran nrepl" :buffer " *clotran nrepl*"
                               :command (list (clotran--command) "nrepl") :connection-type 'pipe
                               :coding 'utf-8 :noquery t)))
      (setq clotran--server proc)
      (message "clotran: starting %s nrepl in %s..." (clotran--command) default-directory)
      (set-process-filter
       proc (lambda (p chunk)
              (when (buffer-live-p (process-buffer p))
                (with-current-buffer (process-buffer p) (goto-char (point-max)) (insert chunk)))
              (when (string-match "nREPL server started on port \\([0-9]+\\)" chunk)
                (set-process-filter p nil)
                (clotran-connect (string-to-number (match-string 1 chunk))))))
      (set-process-sentinel
       proc (lambda (p event)
              (unless (process-live-p p)
                (message "clotran nrepl: %s" (string-trim event)))))
      proc)))

(defun clotran-quit ()
  "Close the connection, and stop the server if this Emacs started it."
  (interactive)
  (when (clotran--connected-p) (delete-process clotran--conn))
  (when (and clotran--server (process-live-p clotran--server)) (delete-process clotran--server))
  (setq clotran--conn nil clotran--server nil clotran--session nil)
  (message "clotran: disconnected"))

;;; evaluating

(defvar clotran-output-buffer "*clotran*" "Where what evaluations print goes.")

(defun clotran--append-output (text)
  "Append TEXT to `clotran-output-buffer'."
  (when (and text (> (length text) 0))
    (with-current-buffer (get-buffer-create clotran-output-buffer)
      (goto-char (point-max))
      (insert text))))

(defun clotran--show (r)
  "Show an evaluation's combined reply R in the echo area and the output buffer.
Return the last value, as a string."
  (clotran--append-output (cdr (assoc "out" r)))
  (clotran--append-output (cdr (assoc "err" r)))
  (let ((err (cdr (assoc "err" r)))
        (vals (cdr (assoc "value" r))))
    (cond ((and err (> (length err) 0)) (message "%s" (string-trim err)))
          (vals (message "=> %s" (string-join vals " ")))
          (t (message "=> (nothing)")))
    (car (last vals))))

(defun clotran--ns-loaded-p (ns)
  "Return non-nil when the server has namespace NS.
Evaluating in one it does not have fails, as clj's nREPL does, on the
first symbol."
  (equal '("true") (cdr (assoc "value" (clotran--request-sync `(("op" . "eval") ("code" . ,(format "(some? (find-ns '%s))" ns))))))))

(defun clotran-eval-string (code &optional ns)
  "Evaluate CODE in NS and show the answer; return the last value, a string.
NS defaults to the buffer's, found by `clojure-find-ns'.  A namespace
the server has not loaded yet is said so, and CODE runs in user:
\\<clotran-mode-map>\\[clotran-load-buffer] loads the file."
  (let* ((ns (or ns (ignore-errors (clojure-find-ns))))
         (ns (cond ((null ns) nil)
                   ((clotran--ns-loaded-p ns) ns)
                   (t (clotran--append-output (format ";; %s is not loaded (C-c C-k loads the file); evaluated in user\n" ns))
                      nil))))
    (clotran--show (clotran--request-sync (append `(("op" . "eval") ("code" . ,code))
                                                  (when ns `(("ns" . ,ns))))))))

(defun clotran-eval-last-sexp ()
  "Evaluate the form before point."
  (interactive)
  (clotran-eval-string (buffer-substring-no-properties (save-excursion (backward-sexp) (point)) (point))))

(defun clotran-eval-defun ()
  "Evaluate the top-level form around point."
  (interactive)
  (save-excursion
    (end-of-defun)
    (let ((end (point)))
      (beginning-of-defun)
      (clotran-eval-string (buffer-substring-no-properties (point) end)))))

(defun clotran-load-buffer ()
  "Save this buffer and load its file into clotran."
  (interactive)
  (unless buffer-file-name (user-error "clotran: this buffer has no file"))
  (save-buffer)
  (let ((r (clotran--request-sync `(("op" . "load-file")
                                    ("file" . ,(buffer-substring-no-properties (point-min) (point-max)))
                                    ("file-path" . ,buffer-file-name)
                                    ("file-name" . ,(file-name-nondirectory buffer-file-name))))))
    (clotran--show r)
    (unless (> (length (cdr (assoc "err" r))) 0)
      (message "clotran: %s loaded" (file-name-nondirectory buffer-file-name)))
    r))

(defun clotran--eval-sync (code &optional secs)
  "Evaluate CODE, waiting up to SECS, and return the combined reply.
Through this file's client, or, when CIDER holds the connection
instead, through CIDER's."
  (cond ((clotran--connected-p)
         (clotran--request-sync `(("op" . "eval") ("code" . ,code)) secs))
        ((and (fboundp 'cider-connected-p) (cider-connected-p))
         (let ((d (cider-nrepl-sync-request:eval code)))
           `(("value" . ,(let ((v (nrepl-dict-get d "value"))) (when v (list v))))
             ("out" . ,(or (nrepl-dict-get d "out") ""))
             ("err" . ,(or (nrepl-dict-get d "err") ""))
             ("status" . ,(nrepl-dict-get d "status")))))
        (t (user-error "clotran: not connected -- C-c C-z (clotran-jack-in) first"))))

(defun clotran-compile-buffer ()
  "Save this file, load it into clotran, and compile it to native code.
Wait for the build: the compiled functions replace the interpreted
ones.  Say in the minibuffer what came of it, and return the build's
state (`installed', `none', `failed', ...)."
  (interactive)
  (unless buffer-file-name (user-error "clotran: this buffer has no file to compile"))
  (save-buffer)
  (let* ((file (expand-file-name buffer-file-name))
         (name (file-name-nondirectory file))
         (form (format (concat "(do (clojure.core/load-file %S)"
                               " (let [st (clotran.loader/compile-now %S)]"
                               "   [st (:log (get @@(resolve (quote clotran.loader/builds)) %S))]))")
                       file file file))
         (_ (message "clotran: compiling %s..." name))
         (r (clotran--eval-sync form 600))
         (err (cdr (assoc "err" r)))
         (value (car (last (cdr (assoc "value" r))))))
    (cond
     ((and err (> (length err) 0)) (message "clotran: %s did not load: %s" name (string-trim err)) 'error)
     ((and value (string-match "\\`\\[:\\([a-z]+\\) \\(.*\\)\\]\\'" value))
      (let ((state (match-string 1 value))
            (log (match-string 2 value)))
        (pcase state
          ("installed" (message "clotran: %s is compiled" name))
          ("none" (message "clotran: nothing in %s compiles; it runs interpreted" name))
          (_ (message "clotran: %s did not compile (%s); see %s" name state log)))
        (intern state)))
     (t (message "clotran: no answer from compiling %s" name) nil))))

(provide 'clotran-mode)
;;; clotran-mode.el ends here
