;;; test/repl-test.el -- clotran-mode's own REPL and the language server,
;;; headless, with no CIDER: in a scratch project with a local dependency,
;;; C-c C-z starts `clotran nrepl' and connects; C-x C-e, C-M-x and C-c C-k
;;; evaluate and load through the client in clotran-mode.el; C-c C-K
;;; compiles; eglot, when Emacs has it, is given `clotran lsp' and answers
;;; a definition. Exits 0 when every check passes. Run by test/run.sh.
(require 'package)
(package-initialize)
(load (expand-file-name "clotran-mode.el" (getenv "CLOTRAN_MODE_DIR")))
(defvar fails 0)
(defmacro check (label got want)
  `(let ((g (condition-case err ,got (error (list 'ERROR err)))))
     (if (equal g ,want)
         (princ (format "ok   - %s\n" ,label))
       (setq fails (1+ fails))
       (princ (format "FAIL - %s\n  got:  %S\n  want: %S\n" ,label g ,want)))))
(defun wait-for (pred secs)
  (let ((n 0)) (while (and (not (funcall pred)) (< n (* 10 secs))) (accept-process-output nil 0.1) (setq n (1+ n))))
  (funcall pred))

(check "bencode: strings by their byte length, keys sorted, lists"
       (clotran--bencode '(("op" . "eval") ("code" . "λ") ("l" . (1 "a"))))
       "d4:code2:\316\2731:lli1e1:ae2:op4:evale")
(check "bencode decodes what it encoded, and says when a message is short"
       (list (car (clotran--bdecode (clotran--bencode '(("a" . 1) ("b" . ("x" "é")))) 0))
             (clotran--bdecode "d1:a" 0))
       '((("a" . 1) ("b" "x" "é")) nil))

(let* ((root (make-temp-file "clotran-mode-test" t))
       (proj (expand-file-name "app" root))
       (lib (expand-file-name "lib" root)))
  (make-directory (expand-file-name "src/app" proj) t)
  (make-directory (expand-file-name "src/dep" lib) t)
  (with-temp-file (expand-file-name "deps.edn" proj) (insert "{:deps {local/lib {:local/root \"../lib\"}}}"))
  (with-temp-file (expand-file-name "deps.edn" lib) (insert "{}"))
  (with-temp-file (expand-file-name "src/dep/core.cljf" lib) (insert "(ns dep.core)\n(def answer 42)\n"))
  (with-temp-file (expand-file-name "src/app/main.cljf" proj)
    (insert "(ns app.main (:require [dep.core]))\n(defn twice-answer [] (* 2 dep.core/answer))\n(println \"loaded é\")\n"))
  ;; the scratch project is under no version control: project.el must
  ;; still see it, as it sees a deps.edn directory for a user (the marker
  ;; clotran-mode adds), so eglot manages its buffers
  (add-hook 'project-find-functions
            (lambda (dir) (when (string-prefix-p (file-name-as-directory proj) (file-name-as-directory (expand-file-name dir)))
                            (cons 'transient (file-name-as-directory proj))))
            -90)
  (let ((clotran-eglot-auto nil)
        (buf (find-file-noselect (expand-file-name "src/app/main.cljf" proj))))
    (with-current-buffer buf
      (check "a .cljf file opens in clotran-mode, which is clojure-mode"
             (list major-mode (and (derived-mode-p 'clojure-mode) t)) '(clotran-mode t))
      (check "the keys" (list (key-binding (kbd "C-c C-z")) (key-binding (kbd "C-x C-e")) (key-binding (kbd "C-M-x"))
                              (key-binding (kbd "C-c C-k")) (key-binding (kbd "C-c C-S-k")))
             '(clotran-jack-in clotran-eval-last-sexp clotran-eval-defun clotran-load-buffer clotran-compile-buffer))
      (call-interactively #'clotran-jack-in)
      (check "C-c C-z starts clotran nrepl in the project and connects" (and (wait-for #'clotran--connected-p 90) t) t)
      (check "the session" (stringp clotran--session) t)
      (check "completion asks the running clotran: an alias offers its namespace's vars, nothing it has seen elsewhere"
             (progn (clotran--request-sync (quote (("op" . "eval") ("code" . "(require (quote [clojure.string :as str]))"))))
                    (with-temp-buffer
                      (clotran-mode)
                      (insert "(str/up")
                      (let* ((c (clotran-completion-at-point))
                             (cands (all-completions (buffer-substring-no-properties (nth 0 c) (nth 1 c)) (nth 2 c))))
                        (list (and (member "str/upper-case" cands) t)
                              (cl-every (lambda (x) (string-prefix-p "str/up" x)) cands)))))
             (quote (t t)))
      (check "C-x C-e evaluates the form before point -- in user, and says so, while the file's namespace is not loaded"
             (progn (goto-char (point-max)) (insert "(+ 1 2)")
                    (list (call-interactively #'clotran-eval-last-sexp)
                          (with-current-buffer clotran-output-buffer (buffer-string))))
             '("3" ";; app.main is not loaded (C-c C-k loads the file); evaluated in user\n"))
      (delete-region (line-beginning-position) (point))
      (with-current-buffer clotran-output-buffer (erase-buffer))
      (check "C-c C-k loads the file, its dependency from deps.edn, and shows what it printed"
             (progn (call-interactively #'clotran-load-buffer)
                    (list (clotran-eval-string "(app.main/twice-answer)")
                          (with-current-buffer clotran-output-buffer (buffer-string))))
             '("84" "loaded é\n"))
      (check "C-M-x evaluates the top-level form around point, in the buffer's namespace"
             (progn (goto-char (point-min)) (search-forward "(* 2") (call-interactively #'clotran-eval-defun)
                    (clotran-eval-string "(twice-answer)"))
             "84")
      (check "an error is shown, not raised"
             (clotran-eval-string "(/ 1 0)") nil)
      (check "C-c C-K compiles the file" (call-interactively #'clotran-compile-buffer) 'installed)
      ;; a Fortran package in the project: C-c C-k in its .f90 builds it,
      ;; and again after an edit, replacing the routine
      (let ((pkg (expand-file-name "src/pkg" proj)))
        (make-directory pkg t)
        (with-temp-file (expand-file-name "package.edn" pkg) (insert "{:name \"tpkg\" :sources [\"tpkg.f90\"]}"))
        (with-temp-file (expand-file-name "tpkg.f90" pkg)
          (insert "module tpkg\n  implicit none\ncontains\n  real(8) function twice(x)\n    real(8), intent(in) :: x\n    twice = 2 * x\n  end function twice\nend module tpkg\n"))
        (with-current-buffer (find-file-noselect (expand-file-name "tpkg.f90" pkg))
          (check "a .f90 of a package gets clotran-fortran-mode, C-c C-k bound"
                 (list clotran-fortran-mode (key-binding (kbd "C-c C-k"))) '(t clotran-load-buffer))
          (call-interactively #'clotran-load-buffer)
          (check "C-c C-k in the .f90 builds the package" (clotran-eval-string "(tpkg.raw/twice 21.0)") "42.0")
          (goto-char (point-min)) (search-forward "twice = 2") (replace-match "twice = 3")
          (with-current-buffer clotran-output-buffer (erase-buffer))
          (call-interactively #'clotran-load-buffer)
          (check "and again after an edit: rebuilt, replaced, and said so"
                 (list (clotran-eval-string "(tpkg.raw/twice 21.0)")
                       (with-current-buffer clotran-output-buffer (buffer-string)))
                 '("63.0" "clotran: tpkg.raw rebuilt from its sources: 1 routines replaced, module state fresh\n"))))
      (check "and the compiled function is the one that runs"
             (clotran-eval-string "[(clojure.string/includes? (pr-str app.main/twice-answer) \"#<compiled\") (app.main/twice-answer)]")
             "[true 84]")
      (set-buffer buf)
      (if (and (require 'eglot nil t) (fboundp 'eglot))
          (progn
            (check "eglot knows how to start clotran lsp for a clotran buffer"
                   (funcall (alist-get 'clotran-mode eglot-server-programs) nil) (list (expand-file-name clotran-program) "lsp"))
            (setq eglot-sync-connect t eglot-connect-timeout 90)
            (let ((server (eglot 'clotran-mode (project-current) 'eglot-lsp-server (clotran--lsp-contact nil) "clojure")))
              (check "eglot connects to it" (plist-get (eglot--server-info server) :name) "clotran-ide")
              (goto-char (point-min)) (search-forward "dep.core/answer") (backward-char 3)
              (xref-find-definitions (xref-backend-identifier-at-point 'eglot))
              (check "M-. on dep.core/answer goes to the dependency's file"
                     (list (file-name-nondirectory (buffer-file-name)) (line-number-at-pos)) '("core.cljf" 2))
              (eglot-shutdown server)))
        (princ "note: no eglot in this Emacs, the language server part is skipped\n"))
      (clotran-quit)
      (check "C-c C-q disconnects and stops the server" (list (clotran--connected-p) clotran--server) '(nil nil))))
  (dolist (p (process-list)) (when (string-prefix-p "clotran" (process-name p)) (delete-process p)))
  (delete-directory root t))
(kill-emacs (if (zerop fails) 0 1))
