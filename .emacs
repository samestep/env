;; -*- lexical-binding: t -*-
;; https://stackoverflow.com/a/35585260

;; don't keep fonts when yanking
(defun wrap-yank (key func)
  ;; https://stackoverflow.com/a/1030409
  (global-set-key (kbd key)
                  (lambda (&optional arg)
                    (interactive "*p")
                    (funcall func arg)
                    ;; https://stackoverflow.com/a/22044138
                    (set-text-properties (point) (mark) nil))))

(wrap-yank "C-y" #'yank)
(wrap-yank "M-y" #'yank-pop)

;; https://www.gnu.org/software/emacs/manual/html_node/emacs/Clipboard.html
;; https://stackoverflow.com/q/24196020
(setq save-interprogram-paste-before-kill t)

(column-number-mode 1)

(windmove-default-keybindings)

;; https://orgmode.org/manual/Conflicts.html
(setq org-replace-disputed-keys 1)

(ido-mode 1)
(ido-everywhere 1)

(setq-default fill-column 80)
(setq sentence-end-double-space nil)

(setq-default indent-tabs-mode nil)

(setq show-paren-delay 0)
(show-paren-mode 1)

(setq make-backup-files nil)
(setq auto-save-default nil)

;; stupid transpose keyboard shortcut has caused me to accidentally push typos
;; by failing to Alt-Tab to Chrome and trying to open a new tab
(global-unset-key (kbd "C-t"))

;; https://gitlab.com/GrammaTech/Mnemosyne/argot-server/-/blob/23c4cd61/.lisp-format#L50-61
;; https://www.gnu.org/software/emacs/manual/html_node/elisp/List-Elements.html
;; https://common-lisp.net/project/slime/doc/html/Semantic-indentation.html
;;; Specify indentation levels for specific functions.
(mapc (lambda (pair) (put (car pair) 'common-lisp-indent-function (cadr pair)))
      '((make-instance 1)
        (if-let 1)
        (if-let* 1)
        (when-let 1)
        (when-let* 1)
        (mvlet* 1)
        (fbind 1)
        (defixture 1)
        (lambda-bind 1)
        (register-groups-bind 2)))

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))
(package-install 'use-package)
(require 'use-package-ensure)
(setq use-package-always-ensure t)

(use-package amx
  :config
  (amx-mode 1))

(use-package browse-kill-ring
  :config
  (browse-kill-ring-default-keybindings))

(use-package crm-custom
  :config
  (crm-custom-mode 1))

(defun project-root (project)
  (car (project-roots project)))

(use-package eglot
  :config
  (add-to-list 'eglot-server-programs '(lisp-mode . ("localhost" 10003)))
  (add-to-list 'eglot-server-programs '(js-mode . ("localhost" 10003)))
  (add-to-list 'eglot-server-programs '(python-mode . ("localhost" 10003))))

(use-package htmlize)

(use-package icomplete
  :config
  (icomplete-mode 1))

(use-package ido-completing-read+
  :config
  (ido-ubiquitous-mode 1))

(use-package ido-yes-or-no
  :config
  (ido-yes-or-no-mode 1))

(use-package magit
  :bind ("C-x g" . magit-status)
  :init
  (setq magit-completing-read-function 'magit-ido-completing-read)
  (setq git-commit-summary-max-length 50)
  :config
  (add-hook 'after-save-hook 'magit-after-save-refresh-status t)
  (add-hook 'git-commit-mode-hook (lambda () (setq fill-column 72))))

(use-package markdown-mode
  :mode (("README\\.md\\'" . gfm-mode)
         ("\\.md\\'" . markdown-mode)
         ("\\.markdown\\'" . markdown-mode))
  :init
  (setq markdown-list-indent-width 2)
  ;; https://emacs.stackexchange.com/a/33497
  (setq markdown-fontify-code-blocks-natively t))

(use-package monokai-theme)

(use-package ox-gfm)

(use-package paredit
  ;; https://www.emacswiki.org/emacs/ParEdit#toc1
  ;; https://github.com/DamienCassou/emacs.d/blob/55b6b63/init.el#L1300-L1304
  :hook ((emacs-lisp-mode
          eval-expression-minibuffer-setup
          ielm-mode
          lisp-interaction-mode
          lisp-mode
          scheme-mode
          slime-repl-mode)
         . enable-paredit-mode)
  ;; https://github.com/eschulte/curry-compose-reader-macros
  :config
  ;; Syntax table
  (modify-syntax-entry ?\[ "(]" lisp-mode-syntax-table)
  (modify-syntax-entry ?\] ")[" lisp-mode-syntax-table)
  (modify-syntax-entry ?\{ "(}" lisp-mode-syntax-table)
  (modify-syntax-entry ?\} "){" lisp-mode-syntax-table)
  (modify-syntax-entry ?\« "(»" lisp-mode-syntax-table)
  (modify-syntax-entry ?\» ")«" lisp-mode-syntax-table)
  (modify-syntax-entry ?\‹ "(›" lisp-mode-syntax-table)
  (modify-syntax-entry ?\› ")‹" lisp-mode-syntax-table)

  ;; Paredit keys

  ;; not sure why these are suggested
  ;; (define-key paredit-mode-map "[" 'paredit-open-parenthesis)
  ;; (define-key paredit-mode-map "]" 'paredit-close-parenthesis)
  ;; (define-key paredit-mode-map "(" 'paredit-open-bracket)
  ;; (define-key paredit-mode-map ")" 'paredit-close-bracket)

  ;; https://github.com/clojure-emacs/cider/issues/1479
  (define-key paredit-mode-map "{" 'paredit-open-curly)
  (define-key paredit-mode-map "}" 'paredit-close-curly)

  ;; not sure what these do either
  ;; they break C-x 8 < and C-x 8 >
  ;; (define-key paredit-mode-map "«" 'paredit-open-special)
  ;; (define-key paredit-mode-map "»" 'paredit-close-special)

  ;; paredit-*-special don't seem to exist
  ;; (define-key paredit-mode-map "‹" 'paredit-open-special)
  ;; (define-key paredit-mode-map "›" 'paredit-close-special)
  )

;; https://docs.projectile.mx/en/latest/installation/#installation-via-use-package
(use-package projectile
  :config
  (define-key projectile-mode-map (kbd "C-c p") 'projectile-command-map)
  (projectile-mode +1))

;; https://www.emacswiki.org/emacs/ParEdit#toc3
;; Stop SLIME's REPL from grabbing DEL,
;; which is annoying when backspacing over a '('
(defun override-slime-repl-bindings-with-paredit ()
  (define-key slime-repl-mode-map
    (read-kbd-macro paredit-backward-delete-key) nil))

(use-package slime
  :init
  (setq inferior-lisp-program "sbcl")
  ;; https://gist.github.com/arademaker/6d6644405824fbdbb047ce6923bb2a12
  :config
  (add-hook 'slime-repl-mode-hook 'override-slime-repl-bindings-with-paredit))

(use-package smex
  :bind (("M-x" . smex)
         ("M-X" . smex-major-mode-commands)
         ("C-c C-c M-x" . execute-extended-command)))

(use-package undo-tree
  :config
  (global-undo-tree-mode))

(use-package yaml-mode
  :config
  (add-to-list 'auto-mode-alist '("\\.yml\\'" . yaml-mode))
  (add-hook 'yaml-mode-hook
            '(lambda ()
               (define-key yaml-mode-map "\C-m" 'newline-and-indent))))

(load (expand-file-name "~/quicklisp/clhs-use-local.el") t)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(org-export-backends (quote (ascii html icalendar latex md odt)))
 '(package-selected-packages
   (quote
    (yaml-mode eglot markdown-mode ox-gfm htmlize browse-kill-ring paredit undo-tree slime smex highlight-parentheses projectile magit amx ido-yes-or-no ido-completing-read+ use-package)))
 '(safe-local-variable-values (quote ((eval subword-mode t)))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
