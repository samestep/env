(toggle-frame-maximized)
(setq inhibit-splash-screen t)

(menu-bar-mode 0)
(tool-bar-mode 0)
(scroll-bar-mode 0)
(column-number-mode 1)

(setq-default show-trailing-whitespace t)

(windmove-default-keybindings)

(ido-mode 1)
(ido-everywhere 1)

(setq-default fill-column 80)
(setq sentence-end-double-space nil)

(setq-default indent-tabs-mode nil)
(setq css-indent-offset 2)
(setq js-indent-level 2)

(setq make-backup-files nil)
(setq auto-save-default nil)

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))
(package-install 'use-package)
(setq use-package-always-ensure t)

(use-package cargo
  :init
  (add-hook 'rust-mode-hook 'cargo-minor-mode))

(use-package cider
  :init
  (setq cider-repl-display-help-banner nil)
  (put 'cider-boot-parameters 'safe-local-variable #'stringp))

(use-package clj-refactor
  :init
  (add-hook 'clojure-mode-hook
            (lambda ()
              (clj-refactor-mode 1)
              (yas-minor-mode 1)
              (cljr-add-keybindings-with-prefix "C-c C-m")))
  (setq cljr-warn-on-eval nil))

(use-package clojure-mode
  :config
  (define-clojure-indent
    (clojure.spec/fdef 1)))

(use-package company
  :init
  (setq company-idle-delay 0.1)
  :config
  (global-company-mode 1))

(use-package evil
  :init
  (fset 'evil-visual-update-x-selection 'ignore)
  :config
  (evil-mode 1)
  (add-to-list 'evil-emacs-state-modes 'project-explorer-mode))

(use-package evil-smartparens
  :init
  (add-hook 'smartparens-enabled-hook (lambda () (evil-smartparens-mode 1))))

(use-package flycheck
  :config
  (global-flycheck-mode 1))

(use-package flycheck-pos-tip
  :config
  (flycheck-pos-tip-mode 1))

(use-package flycheck-rust
  :init
  (add-hook 'flycheck-mode-hook (lambda () (flycheck-rust-setup))))

(use-package ido-ubiquitous
  :config
  (ido-ubiquitous-mode 1))

(use-package ido-yes-or-no
  :config
  (ido-yes-or-no-mode 1))

(use-package impatient-mode)

(use-package magit
  :bind ("C-x g" . magit-status)
  :init
  (setq magit-completing-read-function 'magit-ido-completing-read))

(use-package markdown-mode
  :init
  (setq markdown-command "pandoc -sf commonmark"))

(use-package project-explorer
  :bind ("C-x p" . project-explorer-open))

(use-package projectile
  :config
  (projectile-global-mode 1))

(use-package racer
  :init
  (setq racer-rust-src-path
        (concat "~/.multirust/toolchains/"
                "stable-x86_64-unknown-linux-gnu"
                "/lib/rustlib/src/rust/src"))
  (add-hook 'rust-mode-hook (lambda () (racer-mode)))
  (add-hook 'racer-mode-hook (lambda () (eldoc-mode 1))))

(use-package rainbow-delimiters
  :init
  (add-hook 'smartparens-enabled-hook (lambda () (rainbow-delimiters-mode 1))))

(use-package rust-mode)

(use-package smartparens
  :bind (:map smartparens-mode-map
         ("C-M-f" . sp-next-sexp)
         ("C-M-b" . sp-backward-sexp)
         ("C-M-d" . sp-down-sexp)
         ("C-M-a" . sp-backward-down-sexp)
         ("C-M-u" . sp-up-sexp)
         ("C-M-e" . sp-backward-up-sexp)
         ("C-M-n" . sp-forward-sexp)
         ("C-M-p" . sp-previous-sexp)
         ("C-S-d" . sp-beginning-of-sexp)
         ("C-S-a" . sp-end-of-sexp)
         ("C-M-k" . sp-kill-sexp)
         ("C-M-w" . sp-copy-sexp)
         ("M-<delete>" . sp-unwrap-sexp)
         ("M-<backspace>" . sp-backward-unwrap-sexp)
         ("M-D" . sp-splice-sexp)
         ("C-S-<backspace>" . sp-splice-sexp-killing-around)
         ("C-<right>" . sp-forward-slurp-sexp)
         ("C-<left>" . sp-forward-barf-sexp)
         ("C-S-<left>" . sp-backward-slurp-sexp)
         ("C-S-<right>" . sp-backward-barf-sexp))
  :init
  (dolist (mode-hook
           '(cider-repl-mode-hook
             clojure-mode-hook
             css-mode-hook
             emacs-lisp-mode-hook
             html-mode-hook))
    (add-hook mode-hook (lambda () (smartparens-strict-mode 1))))
  (setq sp-cancel-autoskip-on-backward-movement nil)
  :config
  (require 'smartparens-config))

(use-package smex
  :bind (("M-x" . smex)
         ("M-X" . smex-major-mode-commands)
         ("C-c C-c M-x" . execute-extended-command)))

(use-package tagedit
  :init
  (add-hook 'html-mode-hook (lambda () (tagedit-mode 1)))
  (setq tagedit-expand-one-line-tags nil)
  :config
  (tagedit-add-experimental-features))

(use-package tex-site
  :ensure auctex
  :init
  (setq-default TeX-engine 'xetex)
  (setq font-latex-fontify-sectioning 'color
        font-latex-fontify-script nil))

(use-package zenburn-theme)

(load-file (let ((coding-system-for-read 'utf-8))
                (shell-command-to-string "agda-mode locate")))

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   (quote
    (zenburn-theme use-package tagedit smex rainbow-delimiters racer projectile project-explorer magit impatient-mode ido-yes-or-no flycheck-rust flycheck-pos-tip evil-smartparens company clj-refactor cargo auctex))))
(custom-set-faces)
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
