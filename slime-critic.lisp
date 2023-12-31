(require :asdf)
(require :lisp-critic)

(defpackage :slime-critic
  (:use :cl)
  (:export :critique-file
           :critique-asdf-system))

(in-package :slime-critic)

(declaim (ftype (function (string) string) reformat-critique))
(defun reformat-critique (critique)
  "Remove the separators from CRITIQUE."
  (with-input-from-string (in critique)
    (let ((lines (uiop/stream:slurp-stream-lines in)))
      (with-output-to-string (s)
        (dolist (line (butlast (rest lines)))
          (write-string line s)
          (terpri s))))))

(declaim (ftype (function ((or pathname string) &key (:names list)
                                                (:return (member :simple :slime-notes)))
                          list)
                critique-file))

(defun critique-file
    (file &key (names (lisp-critic::get-pattern-names))
            (return :simple))
  "Critique definitions found in FILE, using patterns in NAMES.
The result depends on the value of RETURN:
- :SIMPLE: a list of (CONS file-position definition-critique).
- :SLIME-NOTES: the list of critiques in Emacs slime-note format."
  (let (critiques)
    (with-open-file (in file)
      (let ((eof (list nil)))
        (do ((file-position (file-position in) (file-position in))
	     (code (read in nil eof) (read in nil eof)))
            ((eq code eof) (values))
          (let ((critique
                  (with-output-to-string (out)
                    (lisp-critic::critique-definition code out names))))
            (when (not (zerop (length critique)))
              (setq critique (reformat-critique critique))
              (case return
                (:simple
                 ;; add 2 to get the exact position for Emacs buffers
                 (push (cons (+ file-position 2) critique)
                       critiques))
                (:slime-notes
                 (push (list :severity :STYLE-WARNING ;; :NOTE, :STYLE-WARNING, :WARNING, or :ERROR.
                             :message critique
                             :source-context nil
                             ;; See slime-goto-source-location for location format
                             :location (list :location
                                             (list :file (princ-to-string file))
                                             ;; add 2 to get the exact position for Emacs buffers
                                             (list :position (+ file-position 2) 0)
                                             nil))
                       critiques))))))))
    (nreverse critiques)))

(declaim (ftype (function ((or string symbol)
                           &key (:names list)
                           (:return (member :simple :slime-notes)))
                          list)
                critique-asdf-system))
(defun critique-asdf-system
    (system-name &key (names (lisp-critic::get-pattern-names))
                   (return :simple))
  "Critique all the Lisp files required by the ASDF system."
  (let* ((critiques '())
         (asdf-system (asdf:find-system system-name :error-if-not-found))
         (components (asdf:required-components asdf-system))
         (lisp-files (remove-if-not (lambda (comp)
                                      (typep comp 'asdf/lisp-action:cl-source-file))
                                    components)))
    (dolist (lisp-file lisp-files)
      (let* ((component-pathname (asdf:component-pathname lisp-file))
             (file-critiques (critique-file component-pathname
                                            :names names :return return)))
        (push (cons component-pathname file-critiques) critiques)))
    critiques))

(provide :slime-critic)
