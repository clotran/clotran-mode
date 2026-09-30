;; Turns on clotran-minor-mode for this project's own Clojure(ish)
;; buffers only -- not clojure-mode-hook globally, so it doesn't touch
;; unrelated Clojure/cider projects. Requires `clotran-mode` (see
;; emacs/clotran-mode.el) to already be loaded/required in your init.
((clojure-mode . ((eval . (when (fboundp 'clotran-minor-mode) (clotran-minor-mode 1)))))
 (clojurec-mode . ((eval . (when (fboundp 'clotran-minor-mode) (clotran-minor-mode 1))))))
