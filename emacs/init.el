;;; init.el --- TEI/XML editing setup -*- lexical-binding: t; -*-

;;; ---------------- Package system ----------------

(require 'package)

(setq package-archives
      '(("melpa" . "https://melpa.org/packages/")
        ("gnu"   . "https://elpa.gnu.org/packages/")))

(package-initialize)

(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t)

(require 'cl-lib)
(require 'seq)

;;; ---------------- Basic UI ----------------

(setq inhibit-startup-message t)

(global-display-line-numbers-mode 1)
(setq-default display-line-numbers-type 'visual)

(column-number-mode 1)

(when (fboundp 'tool-bar-mode)   (tool-bar-mode   -1))
(when (fboundp 'menu-bar-mode)   (menu-bar-mode   -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))

(set-face-attribute 'default nil :height 80)

(load-theme 'tango-dark t)

;;; ---------------- Performance ----------------

(setq fast-but-imprecise-scrolling t)
(setq redisplay-skip-fontification-on-input t)

(global-so-long-mode 1)

(setq make-backup-files nil)
(setq auto-save-default nil)

(setq-default indent-tabs-mode nil)
(setq-default tab-width 2)

;; CAMBIO: electric-pair-mode desactivado globalmente.
;; nxml-mode ya cierra tags automáticamente; activarlo causaba
;; dobles cierres y corrupción de estructura XML.
;; Si lo necesitas en otros modos, actívalo con un hook específico.
;; (electric-pair-mode 1)

;;; ---------------- Ivy navigation ----------------

(use-package ivy
  :init
  (setq ivy-use-virtual-buffers t
        enable-recursive-minibuffers t)
  :config
  (ivy-mode 1))

(use-package swiper
  :bind (("C-s" . swiper)))

(use-package counsel
  :bind (("M-x"     . counsel-M-x)
         ("C-x C-f" . counsel-find-file)
         ("C-x b"   . counsel-switch-buffer))
  :config
  (counsel-mode 1))

(use-package magit
  :bind (("C-x g"   . magit-status)
         ("C-x M-g" . magit-dispatch))
  :custom
  (magit-diff-refine-hunk 'all)   ; diffs a nivel de palabra, muy útil en prosa XML
  (magit-save-repository-buffers 'dontask))  ; guarda sin preguntar al hacer operaciones git

;;; ---------------- Completion UI (popup) ----------------

;; CAMBIO: corfu-auto desactivado por defecto.
;; En buffers TEI el texto tiene mucho contenido prosa y el
;; autocompletado agresivo interrumpe la escritura.
;; Se activa manualmente con M-TAB / C-M-i, o bien solo dentro
;; de etiquetas mediante el hook de nxml (ver más abajo).
(use-package corfu
  :init
  (global-corfu-mode)
  :custom
  (corfu-auto nil)   ; <- era t
  (corfu-cycle t))

;;; ---------------- XML / nXML / TEI ----------------

(require 'nxml-mode)
(require 'rng-loc)
(require 'rng-valid)

(add-to-list 'auto-mode-alist '("\\.xml\\'"  . nxml-mode))
(add-to-list 'auto-mode-alist '("\\.xsl\\'"  . nxml-mode))
(add-to-list 'auto-mode-alist '("\\.xslt\\'" . nxml-mode))

;; CAMBIO: se añade el fichero de localización en lugar de
;; sobreescribir la variable. El valor por defecto de Emacs incluye
;; localizadores internos que rng necesita para funcionar; machacarlos
;; impedía encontrar schemas built-in (p.ej. XHTML, Docbook).
(add-to-list 'rng-schema-locating-files
             (expand-file-name "~/.emacs.d/schemas/schemas.xml"))

;; Validación automática desactivada para buffers grandes (más rápido).
;; Se puede lanzar manualmente con M-x rng-validate-mode.
(setq rng-nxml-auto-validate-flag nil)

(defun my-tei-buffer-p ()
  "Return t si el buffer actual parece ser TEI."
  (save-excursion
    (goto-char (point-min))
    (re-search-forward
     "xmlns=\"http://www\\.tei-c\\.org/ns/1\\.0\"" 5000 t)))

(add-hook 'nxml-mode-hook
          (lambda ()
            (when (my-tei-buffer-p)
              (rng-auto-set-schema)
              (rng-validate-mode 1))))

;;; ---------------- TEI folding ----------------

(defconst tei-fold-overlay 'tei-fold)

(defun tei-fold-show-all ()
  "Elimina todos los folds del buffer actual."
  (interactive)
  (remove-overlays (point-min) (point-max) tei-fold-overlay t))

;; CAMBIO: versión anterior usaba (search-forward ">") que se
;; confunde con ">" dentro de valores de atributos (p.ej. @select).
;; Ahora se usa nxml-token-after para avanzar al final del tag de
;; apertura de forma segura, y se añade protección contra errores
;; cuando el punto no está dentro de un elemento.
(defun tei-fold-element-region ()
  "Devuelve (content-start . content-end) del elemento que contiene el punto.
Señala un error si el punto no está dentro de un elemento."
  (save-excursion
    (condition-case err
        (progn
          (nxml-backward-up-element 1)
          (let ((start (point)))
            ;; Avanza al final del tag de apertura usando el tokenizador
            ;; de nxml en lugar de buscar el primer ">".
            (nxml-token-after)
            (let ((content-start (point)))
              (goto-char start)
              (nxml-forward-element)
              ;; Retrocede antes del tag de cierre.
              (nxml-token-before)
              (cons content-start (point)))))
      (error
       (user-error "tei-fold: no se puede determinar el elemento (%s)"
                   (error-message-string err))))))

(defun tei-fold-toggle ()
  "Pliega o despliega el elemento XML que contiene el punto."
  (interactive)
  (pcase-let ((`(,beg . ,end) (tei-fold-element-region)))
    (let ((existing
           (seq-find
            (lambda (ov) (overlay-get ov tei-fold-overlay))
            (overlays-in beg end))))
      (if existing
          (delete-overlay existing)
        (let ((ov (make-overlay beg end)))
          (overlay-put ov tei-fold-overlay t)
          (overlay-put ov 'invisible t)
          (overlay-put ov 'display " … ")
          (overlay-put ov 'evaporate t)
          (overlay-put ov 'isearch-open-invisible #'delete-overlay))))))

;;; ---------------- Imenu sidebar ----------------

(use-package imenu-list
  :bind (("C-c i" . imenu-list-smart-toggle))
  :config
  (setq imenu-list-size 0.25
        imenu-list-focus-after-activation t
        imenu-list-auto-resize t))

;; CAMBIO: versión anterior asignaba el mismo nombre a todos los
;; elementos del mismo tipo (todos los <div> aparecían como "div"),
;; haciendo el sidebar inútil para navegar.
;; Ahora se extrae el atributo @n o @xml:id si existe, y se añade
;; el número de línea para distinguir entradas sin atributo.
;; Se amplía la lista de tags relevantes para TEI (lg, l, note, etc.).
(defun my-tei-imenu-index ()
  "Construye un índice imenu para buffers TEI."
  (let (index)
    (goto-char (point-min))
    (while (re-search-forward
            "<\\([^/!? \t\r\n>/]+\\)\\([^>]*\\)>" nil t)
      (let* ((raw-tag  (match-string-no-properties 1))
             (attrs    (match-string-no-properties 2))
             (tag      (replace-regexp-in-string ".*:" "" raw-tag))
             (pos      (match-beginning 0)))
        (when (member tag '("div" "p" "s" "head" "lg" "l" "note" "body" "text"))
          (let* ((id  (when (string-match
                             "xml:id=\"\\([^\"]+\\)\"" attrs)
                        (match-string 1 attrs)))
                 (n   (when (string-match
                             "\\bn=\"\\([^\"]+\\)\"" attrs)
                        (match-string 1 attrs)))
                 ;; Etiqueta legible: tag + id/n si existe, línea si no.
                 (label (cond
                         (id (format "%s#%s" tag id))
                         (n  (format "%s[%s]" tag n))
                         (t  (format "%s:L%d" tag
                                     (line-number-at-pos pos))))))
            (push (cons label pos) index)))))
    (nreverse index)))

(add-hook 'nxml-mode-hook
          (lambda ()
            (setq imenu-create-index-function #'my-tei-imenu-index)))

;;; ---------------- Formateo XML con xmllint ----------------

;; NUEVO: formatea el buffer (o región) con xmllint --format.
;; Requiere xmllint instalado (paquete libxml2-utils en Debian/Ubuntu).
(defun my-nxml-format-buffer ()
  "Reformatea el buffer XML con xmllint --format."
  (interactive)
  (unless (executable-find "xmllint")
    (user-error "xmllint no encontrado; instala libxml2-utils"))
  (let ((pos (point)))
    (shell-command-on-region
     (point-min) (point-max)
     "xmllint --format -"
     (current-buffer) t
     "*xmllint-errors*" t)
    (goto-char pos)))

;;; ---------------- nxml keybindings ----------------

(add-hook 'nxml-mode-hook
          (lambda ()

            ;; Folding
            (local-set-key (kbd "C-c f") #'tei-fold-toggle)
            (local-set-key (kbd "C-c a") #'tei-fold-show-all)

            ;; Formateo con xmllint
            (local-set-key (kbd "C-c x f") #'my-nxml-format-buffer)

            ;; CAMBIO: eliminado C-c . porque ya está en nxml-mode-map
            ;; por defecto (nxml-complete). Añadir el binding era redundante.

            ;; Completado manual con TAB (sin ispell)
            (local-set-key (kbd "TAB") #'indent-for-tab-command)

            ;; NUEVO: corfu-auto activado solo dentro de tags (<…>)
            ;; para no interrumpir escritura de texto prosa.
            (add-hook 'post-self-insert-hook
                      (lambda ()
                        (setq-local corfu-auto
                                    (nth 3 (syntax-ppss))))
                      nil t)))

;;; ---------------- End ----------------

(provide 'init)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages nil))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
