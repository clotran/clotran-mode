;;; clotran-mode.el --- Emacs for clotran: .cljf files and CIDER jack-in  -*- lexical-binding: t; -*-

;; clotran is Clojure hosted on Fortran (~/jborden/clotran). Its source
;; files are .cljf: Clojure's syntax, so they open in clojure-mode, and
;; CIDER works in them. CIDER talks to clotran through the nREPL server
;; in ~/jborden/clotran-nrepl, which is what `clotran-jack-in' starts.
;;
;;   (load "/path/to/clotran-mode/clotran-mode.el")
;;
;; then, in a buffer of a project (a directory with a deps.edn, or any
;; directory), M-x clotran-jack-in.
;;
;; This replaces the comint mode that lived here before clotran had an
;; nREPL server (see this repository's history).

(require 'clojure-mode)
(require 'cider)

(defgroup clotran nil
  "clotran: Clojure hosted on Fortran."
  :group 'languages)

(defcustom clotran-program "clotran"
  "The clotran command: the one `make install' puts on PATH, or a
checkout's `clotran' launcher."
  :type 'string)

(defcustom clotran-deps-program "clotran-deps"
  "The clotran-deps command, which answers a project's source path from
its deps.edn."
  :type 'string)

(defcustom clotran-nrepl-dir (expand-file-name "~/jborden/clotran-nrepl")
  "The clotran-nrepl checkout whose server `clotran-jack-in' starts."
  :type 'directory)

;;; .cljf files are Clojure

(add-to-list 'auto-mode-alist '("\\.cljf\\'" . clojure-mode))
(add-to-list 'interpreter-mode-alist '("clotran" . clojure-mode))

;;; jack-in

(defun clotran--project-dir ()
  (or (ignore-errors (clojure-project-dir)) default-directory))

(defun clotran--source-path (dir)
  "The project's CLOTRAN_PATH from clotran-deps, with clotran-nrepl's
sources added; the project's own part is empty with no deps.edn."
  (let* ((default-directory dir)
         (project
          (if (file-exists-p (expand-file-name "deps.edn" dir))
              (with-temp-buffer
                (let ((status (call-process clotran-deps-program nil t nil)))
                  (unless (eq status 0)
                    (error "clotran-deps failed: %s" (string-trim (buffer-string))))
                  (string-trim (buffer-string))))
            "")))
    (mapconcat #'identity
               (delq nil (list (unless (string-empty-p project) project)
                               (expand-file-name "src" clotran-nrepl-dir)))
               ":")))

(defun clotran-jack-in ()
  "Start clotran with an nREPL server in this project, and connect CIDER."
  (interactive)
  (let* ((dir (clotran--project-dir))
         (path (clotran--source-path dir))
         (driver (make-temp-file "clotran-jack-in" nil ".clj"
                                 (concat "(require (quote clotran.nrepl.server))\n"
                                         "(println (str \"clotran nREPL server on port \" (:port (clotran.nrepl.server/start! {:port 0}))))\n"
                                         "(flush)\n@(promise)\n")))
         (buffer (generate-new-buffer (format "*clotran %s*" (file-name-nondirectory (directory-file-name dir)))))
         (process-environment (cons (concat "CLOTRAN_PATH=" path) process-environment))
         (default-directory dir)
         ;; pipes, not a pty: nothing here is a terminal for clotran to edit
         (process-connection-type nil)
         (proc (start-process "clotran" buffer clotran-program driver)))
    (set-process-filter
     proc
     (lambda (p out)
       (with-current-buffer (process-buffer p)
         (goto-char (point-max))
         (insert out)
         (when (and (not (process-get p 'clotran-connected))
                    (save-excursion
                      (goto-char (point-min))
                      (re-search-forward "clotran nREPL server on port \\([0-9]+\\)" nil t)))
           (let ((port (string-to-number (match-string 1))))
             (process-put p 'clotran-connected t)
             (message "clotran: server on port %d, connecting CIDER" port)
             (cider-connect-clj (list :host "localhost" :port port :project-dir dir)))))))
    (message "clotran: starting in %s" dir)
    proc))

(provide 'clotran-mode)
;;; clotran-mode.el ends here
