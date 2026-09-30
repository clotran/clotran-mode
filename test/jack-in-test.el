;;; test/jack-in-test.el -- clotran-jack-in, headless, in a scratch project
;;; with a local dependency: the server starts, CIDER connects, the
;;; dependency and a .cljf file of the project load, interpreted and then
;;; compiled. Exits 0 when every check passes. Run by test/run.sh.
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
(defun repl-buffer ()
  (seq-find (lambda (b) (with-current-buffer b (derived-mode-p 'cider-repl-mode))) (buffer-list)))

(let* ((root (make-temp-file "clotran-mode-test" t))
       (proj (expand-file-name "app" root))
       (lib (expand-file-name "lib" root)))
  (make-directory (expand-file-name "src/app" proj) t)
  (make-directory (expand-file-name "src/dep" lib) t)
  (with-temp-file (expand-file-name "deps.edn" proj) (insert "{:deps {jborden/lib {:local/root \"../lib\"}}}"))
  (with-temp-file (expand-file-name "deps.edn" lib) (insert "{}"))
  (with-temp-file (expand-file-name "src/dep/core.cljf" lib) (insert "(ns dep.core) (def answer 42)\n"))
  (with-temp-file (expand-file-name "src/app/main.cljf" proj)
    (insert "(ns app.main (:require [dep.core]))\n(defn twice-answer [] (* 2 dep.core/answer))\n"))
  (let ((buf (find-file-noselect (expand-file-name "src/app/main.cljf" proj))))
    (check "a .cljf file opens in clojure-mode" (with-current-buffer buf major-mode) 'clojure-mode)
    (with-current-buffer buf (cider-jack-in-clj nil))
    (check "cider-jack-in, in a .cljf buffer, starts clotran and connects" (not (null (wait-for #'repl-buffer 60))) t)
    (with-current-buffer (repl-buffer)
      (check "eval" (nrepl-dict-get (cider-nrepl-sync-request:eval "(+ 1 2)") "value") "3"))
    (with-current-buffer buf
      (cider-load-buffer)
      (wait-for (lambda () nil) 2))
    (with-current-buffer (repl-buffer)
      (check "the project's file loads, with its dependency from deps.edn"
             (nrepl-dict-get (cider-nrepl-sync-request:eval "(app.main/twice-answer)") "value") "84")
      nil)
    (with-current-buffer buf
      (check "a .cljf buffer is in clotran-mode, C-c C-K bound to compiling it"
             (list clotran-mode (key-binding (kbd "C-c C-S-k"))) '(t clotran-compile-buffer))
      (check "C-c C-K compiles the file" (call-interactively (key-binding (kbd "C-c C-S-k"))) 'installed))
    (with-current-buffer (repl-buffer)
      (check "and the compiled function is the one that runs"
             (nrepl-dict-get (cider-nrepl-sync-request:eval
                              "[(clojure.string/includes? (pr-str app.main/twice-answer) \"#<compiled\") (app.main/twice-answer)]")
                             "value")
             "[true 84]")))
  (dolist (p (process-list)) (when (string-prefix-p "clotran" (process-name p)) (delete-process p)))
  (delete-directory root t))
(kill-emacs (if (zerop fails) 0 1))
