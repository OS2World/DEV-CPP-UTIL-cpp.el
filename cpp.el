;;; cpp.el --- Highlight or hide text according to cpp conditionals.

;; Copyright (C) 1994 Per Abrahamsen

;; Author: Per Abrahamsen <abraham@iesd.auc.dk>
;; Version: $Id: VERSION 0.0 ALPHA RELEASE WITH LOTS OF BUGS! $
;; Keywords: c, faces, tools

;; LCD Archive Entry:
;; cpp|Per Abrahamsen|abraham@iesd.auc.dk|
;; Highlight or hide text according to cpp conditionals|
;; $Date: 1994-07-10 $|$Revision: 0.0 $|~/misc/cpp.Z|

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;; 
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; 
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

;;; Comments:

;; Parse a text for C preprocessor conditionals, and highlight or hide
;; the text inside the conditionals as you wish.

;; Insert the following in your `emacs' to activate it.  This assumes
;; you use BAW's superior cc-mode instead of Boring Old C-Mode.

;; (autoload 'cpp-parse-buffer "cpp" "Parse and display cpp conditionals." t)
;; (autoload 'cpp-parse-edit "cpp" "Edit display of cpp conditionals." t)
;; (autoload 'cpp-parse-reset "cpp" "Clear display of cpp conditionals." t)
  
;; (eval-after-load "cc-mode"
;;   '(progn
;;      (define-key c-mode-map "\C-c\C-x" 'cpp-parse-buffer)
;;      (define-key c-mode-map "\C-c\C-z" 'cpp-parse-reset)
;;      (define-key c-mode-map "\C-c\C-w" 'cpp-parse-edit)
;;      (let ((bar (lookup-key c-mode-map [ menu-bar c ])))
;;         (define-key-after bar [ cpp-reset ]
;;           '("Reset Conditionals" . cpp-parse-reset) 'up)
;;         (define-key-after bar [ cpp-edit ]
;;           '("Edit Conditionals" . cpp-parse-edit) 'up)
;;         (define-key-after bar [ cpp-parse ]
;;           '("Parse Conditionals" . cpp-parse-buffer) 'up)))))

;; Requires GNU Emacs 19.

;;; Todo:

;; Should parse "#if" and "#elif" expressions, but then what?

;; Somehow it is sometimes possible to make changes near a read only
;; area which you can't undo.

;; The Edit buffer should -- optionally -- appear in its own frame.

;;; Code:

;;; Customization:

(defvar cpp-known-face 'invisible
  "*Face used for known cpp symbols.")

(defvar cpp-unknown-face 'highlight
  "*Face used for unknown cpp cymbols.")

(defvar cpp-face-type 'light 
  "Indicate what background face type you prefer.
Can be either light or dark for color screens, mono for monochrome
screens, and none if you don't use a window system.")

(or window-system (setq cpp-face-type 'none))

;;; Parse Buffer:

(defvar cpp-parse-symbols nil
  "List of cpp macros used in the local buffer.")
(make-variable-buffer-local 'cpp-parse-symbols)

(defconst cpp-parse-regexp
  ;; Regexp matching all tokens needed to find conditionals.
  (concat
   "'\\|\"\\|/\\*\\|//\\|"
   "\\(^[ \t]*#[ \t]*\\(ifdef\\|ifndef\\|if\\|"
   "elif\\|else\\|endif\\)\\b\\)"))

;;;###autoload
(defun cpp-parse-buffer (arg)
  "Parse all conditionals in the current buffer end edit symbols.
A prefix arg supress editing the symbols."
  (interactive "P")
  (setq cpp-parse-symbols nil)
  (cpp-parse-reset)
  (let (stack)
    (save-excursion
      (goto-char (point-min))
      (cpp-progress-message "Parsing...")
      (while (re-search-forward cpp-parse-regexp nil t)
        (cpp-progress-message "Parsing...%d%%"
                          (/ (* 100 (- (point) (point-min))) (buffer-size)))
        (let ((match (buffer-substring (match-beginning 0) (match-end 0))))
          (cond ((or (string-equal match "'")
                     (string-equal match "\""))
                 (goto-char (match-beginning 0))
                 (condition-case nil
                     (forward-sexp)
                   (error (cpp-parse-error
                           "Unterminated string or character"))))
                ((string-equal match "/*")
                 (or (search-forward "*/" nil t)
                     (error "Unterminated comment")))
                ((string-equal match "//")
                 (skip-chars-forward "^\n\r"))
                (t
                 (end-of-line 1)
                 (let ((from (match-beginning 1))
                       (to (1+ (point)))
                       (type (buffer-substring (match-beginning 2)
                                               (match-end 2)))
                       (expr (buffer-substring (match-end 1) (point))))
                   (cond ((string-equal type "ifdef")
                          (cpp-parse-open t expr from to))
                         ((string-equal type "ifndef")
                          (cpp-parse-open nil expr from to))
                         ((string-equal type "if")
                          (cpp-parse-open t expr from to))
                         ((string-equal type "elif")
                          (let (cpp-known-face cpp-unknown-face)
                            (cpp-parse-close from to))
                          (cpp-parse-open t expr from to))
                         ((string-equal type "else")
                          (or stack (cpp-parse-error "Top level #else"))
                          (let ((entry (list (not (nth 0 (car stack)))
                                             (nth 1 (car stack))
                                             from to)))
                            (cpp-parse-close from to)
                            (setq stack (cons entry stack))))
                         ((string-equal type "endif")
                          (cpp-parse-close from to))
                         (t
                          (cpp-parse-error "Parser error"))))))))
      (message "Parsing...done"))
    (if stack
      (save-excursion
        (goto-char (nth 3 (car stack)))
        (cpp-parse-error "Unclosed conditional"))))
  (or arg
      (null cpp-parse-symbols)
      (cpp-parse-edit)))

(defun cpp-parse-open (branch expr begin end)
  ;; Push information about conditional to stack.
  (while (string-match "\\b[ \t]*/\\*.*\\*/[ \t]*\\b" expr)
    (setq expr (concat (substring expr 0 (match-beginning 0))
                       (substring expr (match-end 0)))))
  (if (string-match "\\b[ \t]*\\(//.*\\)?$" expr)
      (setq expr (substring expr 0 (match-beginning 0))))
  (if (string-match "[ \t]+\\b" expr)
      (setq expr (substring expr (match-end 0))))
  (setq stack (cons (list branch expr begin end) stack))
  (or (member expr cpp-parse-symbols)
      (setq cpp-parse-symbols
            (cons expr cpp-parse-symbols)))
  (if (assoc expr cpp-edit-list)
      (cpp-make-known-overlay begin end)
    (cpp-make-unknown-overlay begin end)))

(defun cpp-parse-close (from to)
  ;; Pop top of stack and create overlay.
  (let ((entry (assoc (nth 1 (car stack)) cpp-edit-list))
        (branch (nth 0 (car stack)))
        (begin (nth 2 (car stack)))
        (end (nth 3 (car stack))))
    (setq stack (cdr stack))
    (if entry
        (let ((face (nth (if branch 1 2) entry))
              (read-only (eq (not branch) (nth 3 entry)))
              (priority (nth 4 entry))
              (overlay (make-overlay end from)))
          (cpp-make-known-overlay from to)
          (setq cpp-overlay-list (cons overlay cpp-overlay-list))
          (if priority (overlay-put overlay 'priority priority))
          (cond ((eq face 'invisible)
                 (cpp-make-overlay-hidden overlay))
                ((eq face 'default))
                (t
                 (overlay-put overlay 'face face)))
          (if read-only
              (cpp-make-overlay-read-only overlay)
            (cpp-make-overlay-sticky overlay)))
      (cpp-make-unknown-overlay from to))))

(defun cpp-parse-error (error)
  ;; Error message issued by the cpp parser.
  (error (concat error " at line %d.") (count-lines (point-min) (point))))

(defun cpp-parse-reset ()
  "Reset display of cpp conditionals to normal."
  (interactive)
  (while cpp-overlay-list
    (delete-overlay (car cpp-overlay-list))
    (setq cpp-overlay-list (cdr cpp-overlay-list))))

;;;###autoload
(defun cpp-parse-edit ()
  "Edit display information for cpp conditionals."
  (interactive)
  (or cpp-parse-symbols
      (cpp-parse-buffer t))
  (let ((buffer (current-buffer)))
    (pop-to-buffer (concat "*CPP " (buffer-name) "*"))
    (cpp-edit-mode)
    (setq cpp-edit-buffer buffer)
    (cpp-edit-reset)))

;;; Overlays:

(defvar cpp-overlay-list nil)
;; List of cpp overlays active in the current buffer.
(make-variable-buffer-local 'cpp-overlay-list)

(defun cpp-make-known-overlay (start end)
  ;; Create an overlay for a known cpp command from START to END.
  (let ((overlay (make-overlay start end)))
    (if (eq cpp-known-face 'invisible)
        (cpp-make-overlay-hidden overlay)
      (or (eq cpp-known-face 'default)
          (overlay-put overlay 'face cpp-known-face))
      (overlay-put overlay 'modification-hooks '(cpp-signal-read-only))
      (overlay-put overlay 'insert-in-front-hooks '(cpp-signal-read-only)))
    (setq cpp-overlay-list (cons overlay cpp-overlay-list))))

(defun cpp-make-unknown-overlay (start end)
  ;; Create an overlay for an unknown cpp command from START to END.
  (let ((overlay (make-overlay start end)))
    (cond ((eq cpp-unknown-face 'invisible)
           (cpp-make-overlay-hidden overlay))
          ((eq cpp-unknown-face 'default))
          (t 
           (overlay-put overlay 'face cpp-unknown-face)))
    (setq cpp-overlay-list (cons overlay cpp-overlay-list))))

(defun cpp-make-overlay-hidden (overlay)
  ;; Make overlay hidden and intangible.
  (overlay-put overlay 'invisible t)
  (overlay-put overlay 'intangible t)
  ;; Unfortunately `intangible' is not implemented for overlays yet,
  ;; so we make is read-only instead.
  (overlay-put overlay 'modification-hooks '(cpp-signal-read-only)))

(defun cpp-make-overlay-read-only (overlay)
  ;; Make overlay read only.
  (overlay-put overlay 'modification-hooks '(cpp-signal-read-only))
  (overlay-put overlay 'insert-in-front-hooks '(cpp-signal-read-only))
  (overlay-put overlay 'insert-behind-hooks '(cpp-signal-read-only)))

(defun cpp-make-overlay-sticky (overlay)
  ;; Make OVERLAY grow when you insert text at either end.
  (overlay-put overlay 'insert-in-front-hooks '(cpp-grow-overlay))
  (overlay-put overlay 'insert-behind-hooks '(cpp-grow-overlay)))

(defun cpp-signal-read-only (overlay start end)
  ;; Only allow deleting the whole overlay.
  ;; Trying to change a read-only overlay.
  (if (or (< (overlay-start overlay) start)
          (> (overlay-end overlay) end))
      (error "This text is read only.")))

(defun cpp-grow-overlay (overlay start end)
  ;; Make OVERLAY grow to contain range START to END.
  (move-overlay overlay
                (min start (overlay-start overlay))
                (max end (overlay-end overlay))))

;;; Edit Buffer:

(defvar cpp-edit-list nil
  "Alist of cpp macros and information about how they should be displayed.
Each entry is a list with the following elements:
0. The name of the macro (a string).
1. Face used for text that is `ifdef' the macro.
2. Face used for text that is `ifndef' the macro.
3. `t', `nil', or `both' depending on what text may be edited.
4. Priority.  The face with the highest priority wins.")

(defvar cpp-edit-map nil)
;; Keymap for `cpp-edit-mode'.

(if cpp-edit-map
    ()
  (setq cpp-edit-map (make-keymap))
  (suppress-keymap cpp-edit-map)
  (define-key cpp-edit-map [ down-mouse-1 ] 'cpp-push-button)
  (define-key cpp-edit-map " " 'scroll-up)
  (define-key cpp-edit-map "\C-?" 'scroll-down)
  (define-key cpp-edit-map [ delete ] 'scroll-down)
  (define-key cpp-edit-map "\C-c\C-c" 'cpp-edit-apply)
  (define-key cpp-edit-map "a" 'cpp-edit-apply)
  (define-key cpp-edit-map "A" 'cpp-edit-apply)
  (define-key cpp-edit-map "r" 'cpp-edit-reset)
  (define-key cpp-edit-map "R" 'cpp-edit-reset)
  (define-key cpp-edit-map "h" 'cpp-edit-home)
  (define-key cpp-edit-map "H" 'cpp-edit-home)
  (define-key cpp-edit-map "b" 'cpp-edit-background)
  (define-key cpp-edit-map "B" 'cpp-edit-background)
  (define-key cpp-edit-map "k" 'cpp-edit-known)
  (define-key cpp-edit-map "K" 'cpp-edit-known)
  (define-key cpp-edit-map "u" 'cpp-edit-unknown)
  (define-key cpp-edit-map "u" 'cpp-edit-unknown)
  (define-key cpp-edit-map "t" 'cpp-edit-true)
  (define-key cpp-edit-map "T" 'cpp-edit-true)
  (define-key cpp-edit-map "f" 'cpp-edit-false)
  (define-key cpp-edit-map "F" 'cpp-edit-false)
  (define-key cpp-edit-map "w" 'cpp-edit-write)
  (define-key cpp-edit-map "W" 'cpp-edit-write)
  (define-key cpp-edit-map "p" 'cpp-edit-priority)
  (define-key cpp-edit-map "P" 'cpp-edit-priority)
  (define-key cpp-edit-map "q" 'bury-buffer)
  (define-key cpp-edit-map "Q" 'bury-buffer))

(defvar cpp-edit-buffer nil)
;; Real buffer whose cpp display information we are editing.
(make-variable-buffer-local 'cpp-edit-buffer)

(defvar cpp-edit-symbols nil)
;; Symbols defined in the edit buffer.
(make-variable-buffer-local 'cpp-edit-symbols)

(defun cpp-edit-mode ()
  "Major mode for editing cpp display information.
Click on objects to change them.  
You can also use the keyboard accelerators indicated like this: [K]ey."
  (kill-all-local-variables)
  (buffer-disable-undo)
  (auto-save-mode -1)
  (setq buffer-read-only t)
  (setq major-mode 'cpp-edit-mode)
  (setq mode-name "CPP Edit")
  (use-local-map cpp-edit-map))

(defun cpp-edit-apply ()
  "Apply edited display information to original buffer."
  (interactive)
  (cpp-edit-home)
  (cpp-parse-buffer t))

(defun cpp-edit-reset ()
  "Reset display information from original buffer."
  (interactive)
  (let ((buffer (current-buffer))
        (buffer-read-only nil)
        (start (window-start))
        (pos (point))
        symbols)
    (set-buffer cpp-edit-buffer)
    (setq symbols cpp-parse-symbols)
    (set-buffer buffer)
    (setq cpp-edit-symbols symbols)
    (erase-buffer)
    (insert "CPP Display Information for `")
    (cpp-make-button (buffer-name cpp-edit-buffer) 'cpp-edit-home)
    (insert "' [H]ome.\n\n")
    (insert "[B]ackground: ")
    (cpp-make-button (car (rassq cpp-face-type cpp-face-type-list))
                     'cpp-edit-background)
    (insert "\n[K]nown conditionals: ")
    (cpp-make-button (cpp-face-name cpp-known-face)
                     'cpp-edit-known nil t)
    (insert "\n[U]nknown conditionals: ")
    (cpp-make-button (cpp-face-name cpp-unknown-face)
                     'cpp-edit-unknown nil t)
    (insert (format "\n\n\n%29s: %14s %14s %7s %s\n\n" "Expression"
                    "[T]rue Face" "[F]alse Face" "[W]rite" "[P]riority"))
    (while symbols
      (let*  ((symbol (car symbols))
              (entry (assoc symbol cpp-edit-list))
              (true (nth 1 entry))
              (false (nth 2 entry))
              (write (if entry (nth 3 entry) 'both))
              (priority (nth 4 entry)))
        (setq symbols (cdr symbols))
        (if (> (length symbol) 29)
            (insert (substring symbol 0 29) ": ")
          (insert (format "%29s: " symbol)))
        (cpp-make-button (cpp-face-name true)
                         'cpp-edit-true symbol t 14)
        (insert " ")
        (cpp-make-button (cpp-face-name false)
                         'cpp-edit-false symbol t 14)
        (insert " ")
        (cpp-make-button (car (rassq write cpp-branch-list))
                         'cpp-edit-write symbol nil 6)
        (insert "  ")
        (cpp-make-button priority 'cpp-edit-priority symbol nil 4)
        (insert "\n")))
    (insert "\n")
    (cpp-make-button "[A]pply" 'cpp-edit-apply nil nil 30)
    (cpp-make-button "[R]eset" 'cpp-edit-reset nil nil 20)
    (insert "\n")
    (set-window-start nil start)
    (goto-char pos)))

(defun cpp-edit-home ()
  "Switch back to original buffer."
  (interactive)
  (pop-to-buffer cpp-edit-buffer))

(defun cpp-edit-background ()
  "Change default face collection."
  (interactive)
  (call-interactively 'cpp-choose-default-face)
  (cpp-edit-reset))

(defun cpp-edit-known ()
  "Select default for known conditionals."
  (interactive)
  (setq cpp-known-face (cpp-choose-face "Known face" cpp-known-face))
  (cpp-edit-reset))

(defun cpp-edit-unknown ()
  "Select default for unknown conditionals."
  (interactive)
  (setq cpp-unknown-face (cpp-choose-face "Unknown face" cpp-unknown-face))
  (cpp-edit-reset))

(defun cpp-edit-true (symbol face)
  "Select SYMBOL's true FACE used for highlighting taken conditionals."
  (interactive
   (let ((symbol (cpp-choose-symbol)))
     (list symbol
           (cpp-choose-face "True face"
                            (nth 1 (assoc symbol cpp-edit-list))))))
  (setcar (nthcdr 1 (cpp-edit-list-entry-get-or-create symbol)) face)
  (cpp-edit-reset))

(defun cpp-edit-false (symbol face)
  "Select SYMBOL's false FACE used for highlighting untaken conditionals."
  (interactive
   (let ((symbol (cpp-choose-symbol)))
     (list symbol
           (cpp-choose-face "False face" 
                            (nth 2 (assoc symbol cpp-edit-list))))))
  (setcar (nthcdr 2 (cpp-edit-list-entry-get-or-create symbol)) face)
  (cpp-edit-reset))

(defun cpp-edit-write (symbol branch)
  "Set which branches of SYMBOL should be writable to BRANCH.
BRANCH should be either nil (false branch), t (true branch) or 'both."
  (interactive (list (cpp-choose-symbol) (cpp-choose-branch)))
  (setcar (nthcdr 3 (cpp-edit-list-entry-get-or-create symbol)) branch)
  (cpp-edit-reset))

(defun cpp-edit-priority (symbol priority)
  "Set SYMBOL's PRIORITY."
  (interactive (list (cpp-choose-symbol) (cpp-choose-priority)))
  (setcar (nthcdr 4 (cpp-edit-list-entry-get-or-create symbol)) priority)
  (cpp-edit-reset))

(defun cpp-edit-list-entry-get-or-create (symbol)
  ;; Return the entry for SYMBOL in `cpp-edit-list'.
  ;; If it does not exist, create it.
  (let ((entry (assoc symbol cpp-edit-list)))
    (or entry
        (setq entry (list symbol nil nil 'both nil)
              cpp-edit-list (cons entry cpp-edit-list)))
    entry))

;;; Prompts:

(defun cpp-choose-symbol ()
  ;; Choose a symbol if called from keyboard, otherwise use the one clicked on.
  (if cpp-button-event
      data
    (completing-read "Symbol: " (mapcar 'list cpp-edit-symbols) nil t)))

(defconst cpp-branch-list
  ;; Alist of branches.
  '(("false" . nil)
    ("true" . t)
    ("both" . both)))

(defun cpp-choose-branch ()
  ;; Choose a branch, either nil, t, or both.
  (if cpp-button-event
      (x-popup-menu cpp-button-event
                    (list "Branch" (cons "Branch" cpp-branch-list)))
    (cdr (assoc        (completing-read "Branch: " cpp-branch-list nil t)
                cpp-branch-list))))

(defun cpp-choose-priority ()
  ;; Choose a priority.
  (if cpp-button-event
      (read-event))
  (string-to-int (read-string "Priority: ")))

(defun cpp-choose-face (prompt default)
  ;; Choose a face from cpp-face-defalt-list.
  ;; PROMPT is what to say to the user.
  ;; DEFAULT is the default face.
  (or (if cpp-button-event
          (x-popup-menu cpp-button-event
                        (list prompt (cons prompt cpp-face-default-list)))
        (let ((name (car (rassq default cpp-face-default-list))))
          (cdr (assoc (completing-read (if name
                                           (concat prompt
                                                   " (default " name "): ")
                                         (concat prompt ": "))
                                       cpp-face-default-list nil t)
                      cpp-face-all-list))))
      default))

(defconst cpp-face-type-list
  '(("light color background" . light)
    ("dark color background" . dark)
    ("monochrome" . mono)
    ("tty" . none))
  "Alist of strings and names of the defined face collections.")

(defun cpp-choose-default-face (type)
  ;; Choose default face list for screen of TYPE.
  ;; Type must be one of the types defined in `cpp-face-type-list'.
  (interactive (list (if cpp-button-event
                         (x-popup-menu cpp-button-event
                                       (list "Screen type"
                                             (cons "Screen type"
                                                   cpp-face-type-list)))
                       (cdr (assoc (completing-read "Screen type: "
                                                    cpp-face-type-list
                                                    nil t)
                                   cpp-face-type-list)))))
  (cond ((null type))
        ((eq type 'light)
         (if cpp-face-light-list
             ()
           (setq cpp-face-light-list
                 (mapcar 'cpp-create-bg-face cpp-face-light-name-list))
           (setq cpp-face-all-list
                 (append cpp-face-all-list cpp-face-light-list)))
         (setq cpp-face-type 'light)
         (setq cpp-face-default-list
               (append cpp-face-light-list cpp-face-none-list)))
        ((eq type 'dark)
         (if cpp-face-dark-list
             ()
           (setq cpp-face-dark-list
                 (mapcar 'cpp-create-bg-face cpp-face-dark-name-list))
           (setq cpp-face-all-list
                 (append cpp-face-all-list cpp-face-dark-list)))
         (setq cpp-face-type 'dark)
         (setq cpp-face-default-list
               (append cpp-face-dark-list cpp-face-none-list)))
        ((eq type 'mono)
         (setq cpp-face-type 'mono)
         (setq cpp-face-default-list
               (append cpp-face-mono-list cpp-face-none-list)))
        (t
         (setq cpp-face-type 'none)
         (setq cpp-face-default-list cpp-face-none-list))))

;;; Buttons:

(defvar cpp-button-event nil)
;; This will be t in the callback for `cpp-make-button'.

(defun cpp-make-button (name callback &optional data face padding)
  ;; Create a button at point.
  ;; NAME is the name of the button.
  ;; CALLBACK is the function to call when the button is pushed.
  ;; DATA will be available to CALLBACK as a free variable.
  ;; FACE means that NAME is the name of a face in `cpp-face-all-list'.
  ;; PADDING means NAME will be right justified at that length.
  (let ((name (format "%s" name))
        from to)
    (cond ((null padding)
           (setq from (point))
           (insert name))
          ((> (length name) padding)
           (setq from (point))
           (insert (substring name 0 padding)))
          (t
           (insert (make-string (- padding (length name)) ? ))
           (setq from (point))
           (insert name)))
    (setq to (point))
    (setq face
          (if face
              (let ((check (cdr (assoc name cpp-face-all-list))))
                (if (memq check '(default invisible))
                    'bold
                  check))
            'bold))
    (add-text-properties from to
                         (append (list 'face face)
                                 '(mouse-face highlight)
                                 (list 'cpp-callback callback)
                                 (if data (list 'cpp-data data))))))

(defun cpp-push-button (event)
  ;; Pushed a CPP button.
  (interactive "@e")
  (set-buffer (window-buffer (posn-window (event-start event))))
  (let ((pos (posn-point (event-start event))))
    (let ((data (get-text-property pos 'cpp-data))
          (fun (get-text-property pos 'cpp-callback))
          (cpp-button-event event))
      (if fun
          (call-interactively (get-text-property pos 'cpp-callback))
        (call-interactively (lookup-key global-map [ down-mouse-1]))))))

;;; Faces:

(defvar cpp-face-light-name-list
  '("light gray" "light blue" "light cyan" "light yellow" "light pink"
    "pale green" "beige" "orange" "magenta" "violet" "medium purple"
    "turquoise")
  "Background colours useful with dark foreground colors.")

(defvar cpp-face-dark-name-list
  '("dim gray" "blue" "cyan" "yellow" "red"
    "dark green" "brown" "dark orange" "dark khaki" "dark violet" "purple"
    "dark turquoise")
  "Background colours useful with light foreground colors.")

(defvar cpp-face-light-list nil
  "Alist of names and faces to be used for light backgrounds.")

(defvar cpp-face-dark-list nil
  "Alist of names and faces to be used for dark backgrounds.")

(defvar cpp-face-mono-list
  '(("bold" . 'bold)
    ("bold-italic" . 'bold-italic)
    ("italic" . 'italic)
    ("underline" . 'underline))
  "Alist of names and faces to be used for monocrome screens.")

(defvar cpp-face-none-list
   '(("default" . default)
     ("invisible" . invisible))
   "Alist of names and faces available even if you don't use a window system.")

(defvar cpp-face-all-list
  (append cpp-face-light-list
          cpp-face-dark-list
          cpp-face-mono-list
          cpp-face-none-list)
  "All faces used for highligting text inside cpp conditionals.")

(defvar cpp-face-default-list nil
  "List of faces you can choose from for cpp conditionals.")

(defun cpp-create-bg-face (color)
  ;; Create entry for face with background COLOR.
  (let ((name (intern (concat "cpp " color))))
    (make-face name)
    (set-face-background name color)
    (cons color name)))

(cpp-choose-default-face cpp-face-type)

(defun cpp-face-name (face)
  ;; Return the name of FACE from `cpp-face-all-list'.
  (let ((entry (rassq (if face face 'default) cpp-face-all-list)))
    (if entry
        (car entry)
      (format "<%s>" face))))

;;; Utilities:

(defvar cpp-progress-time 0)
;; Last time we issued a progress message.

(defun cpp-progress-message (&rest args)
  ;; Report progress at most once a second.  Take same ARGS as `message'.
  (let ((time (nth 1 (current-time))))
    (if (= time cpp-progress-time)
        ()
      (setq cpp-progress-time time)
      (apply 'message args))))

(provide 'cpp)

;;; cpp.el ends here
