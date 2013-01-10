(defpackage local-package-aliases
  (:use #:cl)
  (:shadow #:set)
  (:export #:set
           #:aliasing-readtable
           #:call-with-aliasing-readtable))

(in-package #:local-package-aliases)

(define-condition aliased-ref-error (simple-error reader-error) ())

(defun err (format-control &rest format-arguments)
  (error 'aliased-ref-error
         :format-control format-control
         :format-arguments format-arguments))

;;; datastructure to store package aliases

(defparameter *package-to-aliases-map* (make-hash-table :test #'eq)
  "Mapping from package object to a hash-table of local aliases active in this package.
The hash-table of local aliases maps string alias to a package designator.")

(defun alias-table-for (package)
  (gethash package *package-to-aliases-map*))

(defun has-local-aliases-p (package)
  (let ((alias-table (alias-table-for package)))
    (and alias-table (> (hash-table-count alias-table) 0))))

(defun set-local-aliases (&rest package-alias-pairs)
  "PACKAGE-ALIAS-PAIRS is a list in the form (PACKAGE-DESIGNATOR ALIAS-STRING ...)"
  (let ((aliases-table (make-hash-table :test #'equal)))
    (loop for (package alias) on package-alias-pairs by #'cddr
         do (setf (gethash (string alias) aliases-table) package))
    (setf (gethash *package* *package-to-aliases-map*) aliases-table)))

(defmacro set (&rest package-alias-pairs)
  (let ((args (loop for (package alias) on package-alias-pairs by #'cddr
                 nconcing (list (if (symbolp package) (list 'quote package) package)
                                (string alias)))))
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       (set-local-aliases ,@args))))

(defun find-aliased-package (alias)
  (or (gethash alias
               (or (gethash *package* *package-to-aliases-map*)
                   (err "There is no alias ~A in the package ~A" alias *package*)))
      (err "There is no alias ~A in the package ~A" alias *package*)))

;;; reader macro 

(defun find-aliased-symbol (token)
  "TOEKN is a string in the form alias:symbol or alias::symbol."
  (let* ((colon-pos (or (position #\: token :test #'char=)
                        (err "Wrong aliased reference: ~A" token)))
         (double-colon-p (if (<= (length token) (1+ colon-pos))
                             (err "Wrong aliased reference: ~A" token)
                             (char= #\: (aref token (1+ colon-pos)))))
         (package-alias (subseq token 0 colon-pos))
         (package (find-aliased-package package-alias))
         (symbol-name (subseq token (+ colon-pos (if double-colon-p 2 1)))))
    (multiple-value-bind (symbol status) (find-symbol symbol-name package)     
      (when (null status)
        (err "Symbol ~A is not found in the package ~A" symbol-name package))
      (when (and (not double-colon-p)
                 (not (eq :external status)))
        (err "Symbol ~A is not external in the package ~A" symbol-name package))
      symbol)))

(defun whitespace-p (char)
  (or (case char ((#\Space #\Tab #\Return #\Linefeed #\Page)
                  t))
      (char= #\Newline char)))

(defun terminating-macro-char-p (char)
  (case char ((#\" #\' #\( #\) #\, #\; #\`)
                  t)))

(defun terminator-p (char)
  (or (whitespace-p char)
      (terminating-macro-char-p char)))

(defun apply-case-mode (readtable-case-mode str)
  (funcall (ecase readtable-case-mode
             (:upcase #'string-upcase)
             (:downcase #'string-downcase)
             (:preserve #'identity)
             (:invert (error ":invert readtable-case mode handling is not implemented yet")))
           str))

(defun read-token (stream)
  (let ((str (make-array 3 :element-type 'character :adjustable t :fill-pointer 0))
        char)
    (loop       
       (setf char (read-char stream nil nil))
       (when (null char) (RETURN))
       (when (terminator-p char)
         (unread-char char stream)
         (RETURN))
       (vector-push-extend char str))
    (apply-case-mode (readtable-case *readtable*) str)))

(defun read-package-aliased-symbol (stream char original-readtable)
  (if (has-local-aliases-p *package*)
      (find-aliased-symbol (read-token stream))
      (let ((*readtable* (copy-readtable *readtable*)))
        (set-syntax-from-char char char *readtable* original-readtable)
        (with-input-from-string (s (string char))
          (read (make-concatenated-stream s stream) t nil t)))))

(defun aliasing-readtable (&optional (prototype-readtable *readtable*) (macro-char #\$))
  (let ((readtable (copy-readtable prototype-readtable)))
    (set-macro-character macro-char
                         (lambda (stream char)
                           (read-package-aliased-symbol stream char prototype-readtable))
                         t
                         readtable)
    readtable))

(defun call-with-aliasing-readtable (thunk)
  "Convenience function to use in ASDF's :around-compile argument."
  (let ((*readtable* (aliasing-readtable)))
    (funcall thunk)))
