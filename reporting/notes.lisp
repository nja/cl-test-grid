;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; Copyright (C) 2011 Anton Vodonosov (avodonosov@yandex.ru)
;;;; See LICENSE for details.

(in-package #:test-grid-reporting)

;;; Note is either a text or a ticket reference
(defclass ticket () ())
(defgeneric ticket-url (ticket))

(defun note-body-p (obj)
  (or (stringp obj)
      (typep obj 'ticket)))

(defclass launchpad-ticket (ticket)
  ((id :type string
       :accessor id
       :initarg :id
       :initform (error ":id is required"))))

(defun lp-ticket (id)
  (make-instance 'launchpad-ticket :id id))

(defmethod print-object ((ticket launchpad-ticket) stream)
  (print-unreadable-object (ticket stream :type t :identity t)
    (format stream "~S" (id ticket))))

(defmethod ticket-url ((ticket launchpad-ticket))
  (concatenate 'string
               "http://bugs.launchpad.net/bugs/"
               (id ticket)))

(defclass github-issue (ticket)
  ((user :type string
         :accessor user
         :initarg :user
         :initform (error ":user is required"))
   (repo :type string
         :accessor repo
         :initarg :repo
         :initform (error ":repo is required"))
   (numbr :type number
          :accessor numbr
          :initarg :number
          :initform (error ":number is required"))))

(defun github-issue (user repo numbr)
  (make-instance 'github-issue :user user :repo repo :number numbr))

(defmethod print-object ((ticket github-issue) stream)
  (print-unreadable-object (ticket stream :type t :identity t)
    (format stream "~A/~A/~S" (user ticket) (repo ticket) (numbr ticket))))

(defmethod ticket-url ((ticket github-issue))
  (format nil "https://github.com/~A/~A/issues/~A"
          (user ticket)
          (repo ticket)
          (numbr ticket)))

(assert (string= "https://github.com/avodonosov/test/issues/1"
                 (ticket-url (github-issue "avodonosov" "test" 1))))


(defclass prj-ticket (ticket)
  ((project-key :type keyworkd
                :accessor project-key
                :initarg :project-key
                :initform (error ":project-key is required"))
   (ticket-id :type t
              :accessor ticket-id
              :initarg :ticket-id
              :initform (error ":ticket-id is required"))))

(defparameter *prj-ticket-base-url*
  (alexandria:plist-hash-table '(:abcl "http://abcl.org/trac/ticket/"
                                 :cmucl "http://trac.common-lisp.net/cmucl/ticket/"
                                 :pgloader "https://github.com/dimitri/pgloader/issues/"
                                 :xsubseq "https://github.com/fukamachi/xsubseq/issues/"
                                 :cl-ansi-text "https://github.com/pnathan/cl-ansi-text/issues/"
                                 :ccl "http://trac.clozure.com/ccl/ticket/"
                                 :cl+ssl "https://github.com/cl-plus-ssl/cl-plus-ssl/issues/")))

(defun prj-ticket (project-key ticket-id)
  (make-instance 'prj-ticket
                 :project-key project-key
                 :ticket-id ticket-id))

(defmethod ticket-url ((ticket prj-ticket))
  (format nil "~A~A"
          (gethash (project-key ticket)
                   *prj-ticket-base-url*)
          (ticket-id ticket)))

(assert (string= (ticket-url (prj-ticket :abcl 357))
                 "http://abcl.org/trac/ticket/357"))

(assert (string= (ticket-url (prj-ticket :cmucl 99))
                 "http://trac.common-lisp.net/cmucl/ticket/99"))

;;; Note database

(defun make-note-db ()
  (make-hash-table :test 'equal))

(defun set-note (db fields field-values body)
  (let ((index (or (gethash fields db)
                   (setf (gethash fields db)
                         (make-hash-table :test 'equal)))))
    (setf (gethash field-values index) body)))

(defun note (db fields field-values)
  (let ((index (gethash fields db)))
    (when index
      (gethash field-values index))))

(let ((db (make-note-db)))
  (set-note db '(lisp) '("sbcl") "this is a note for SBCL")
  (assert (string= (note db '(lisp) '("sbcl"))
                   "this is a note for SBCL")))

(defun db-notes (db result)
  (let ((notes nil))
    (maphash (lambda (fields index)
               (let* ((field-vals (mapcar (lambda (field)
                                            (funcall field result))
                                          fields))
                      (note (gethash field-vals index)))
                 (when (functionp note)
                   ;; it's a function which preforms futher
                   ;; analisys of the RESULT and may return a note or NIL
                   (setf note (funcall note result)))
                 (when note
                   (push note notes))))
             db)
    notes))

(defun fill-note-db (note-spec-list)
  (flet ((as-list (val)
           (if (consp val)
               val
               (list val))))
    (let ((db (make-note-db)))
      (labels ((fill-rec (fields field-vals spec)
                 (if (or (note-body-p spec) (functionp spec))
                     (set-note db fields field-vals spec)
                     (let* ((cur-field (first spec))
                            (cur-field-vals (as-list (second spec)))
                            (fields (cons cur-field fields)))
                       (dolist (cur-field-val cur-field-vals)
                         (let ((field-vals (cons cur-field-val field-vals)))
                           (dolist (subspec (cddr spec))
                             (fill-rec fields field-vals subspec))))))))
        (dolist (spec note-spec-list)
          (fill-rec '() '() spec)))
      db)))

(defun ecl-alexandria-bug-p (result)
  (and (failure-p result)
       (eq :ecl (lisp-impl-type result))
       (search "COMPILE-FILE-ERROR while compiling #<cl-source-file \"alexandria\" \"macros\">"
               (fail-condition-text result))))

(defparameter *note-db*
  (fill-note-db `((lib-world "quicklisp 2013-08-13"
                 (libname (:series)
                  (lisp-impl-type :acl
                    ,(lp-ticket "1249658")))
                 (libname :com.informatimago
                  (failure-p t "author informed"))
                 (libname :asdf-dependency-grovel
                  (system-name "asdf-dependency-grovel"
                   (failure-p t "needs ASDF 3")))
                 (libname :xcvb
                  (failure-p t
                   (lisp ("acl-9.0a-win-x86" "ccl-1.8-f95-win-x64" "ccl-1.8-f95-win-x86" "sbcl-1.0.57.0.debian-linux-x64")
                     "needs ASDF 3")))
                 (libname :exscribe
                  (failure-p t
                    "needs ASDF 3"))
                 (libname (:periods :cambl)
                  (failure-p t
                    ,(lp-ticket "1229050"))))
                (lib-world "quicklisp 2013-10-03"
                 (libname (:series)
                  (lisp-impl-type :acl
                    ,(lp-ticket "1249658")))
                 (libname (:periods :cambl)
                  (lisp-impl-type :acl
                    "new dependency SERIES doesn't work on ACL"))
                 (libname :cl-annot
                   (lisp-impl-type :cmu
                     ,(lp-ticket "1242490")))
                 (libname :cl-autowrap
                   (lisp-impl-type :ccl
                     ,(lp-ticket "1242492")))
                 (libname (:cl-gdata :cl-generic-arithmetic :sexml :string-case
                           :memoize :macroexpand-dammit :conduit-packages
                           :docbrowser)
                  (failure-p t
                    ,(lp-ticket "1242500")))
                 (libname :cl-grace
                  (lisp-impl-type (:acl :abcl)
                    "Not a problem. ACL and ABCL are not supported anyway."))
                 (libname :cl-parser-combinators
                  (lisp-impl-type :ecl
                   (failure-p t
                    ,(lp-ticket "1243531"))))
                 (libname (:cl-redis :cl-secure-read :rutils)
                  (lisp ("ecl-13.4.1-0e93edfc-win-x86-bytecode"
                         "ecl-13.4.1-0e93edfc-win-x86-lisp-to-c"
                         "abcl-1.2.1-fasl42-macosx-x64")
                   (failure-p t
                    ,(lp-ticket "1243540"))))
                 (libname :opticl
                  (lisp ("cmu-snapshot-2013-04__20d_unicode_-linux-x86")
                    (failure-p t
                      ,(lp-ticket "1244452"))))
                 (system-name "lil"
                   (failure-p t "new LIL version requires ASDF 3")))
                (lib-world "quicklisp 2013-11-11"
                 (system-name "asdf-package-system"
                   (failure-p t "needs ASDF 3"))
                 (libname (:caveman :cl-emb :cl-project)
                  (lisp ("acl-9.08-linux-x64"
                         "acl-9.08-linux-x86"
                         "acl-9.08s-linux-x64"
                         "acl-9.08s-linux-x86"
                         "acl-9.0m8-linux-x64"
                         "acl-9.0m8-linux-x86"
                         "acl-9.0m8s-linux-x64"
                         "acl-9.0m8s-linux-x86"
                         "ccl-1.8-f95-win-x64"
                         "ccl-1.8-f95-win-x86"
                         "clisp-2.49-win-x86"
                         "sbcl-1.1.0.36.mswinmt.1201-284e340-win-x64"
                         "sbcl-1.1.0.36.mswinmt.1201-284e340-win-x86")
                   ,(lp-ticket "1258873")))
                 (libname :cl-annot
                   (result-spec ((:whole-test-suite :fail))
                     ,(lp-ticket "1258876")))
                 (lisp ("acl-9.0-linux-x64"
                        "acl-9.0-linux-x86"
                        "acl-9.08-linux-x64"
                        "acl-9.08-linux-x86"
                        "acl-9.08s-linux-x64"
                        "acl-9.08s-linux-x86"
                        "acl-9.0s-linux-x64"
                        "acl-9.0s-linux-x86"
                        "ccl-1.8-f95-win-x64"
                        "ccl-1.8-f95-win-x86"
                        "ccl-1.9-f96-linux-x64"
                        "ccl-1.9-f96-linux-x86"
                        "ccl-1.9-f96-macosx-x64"
                        "ccl-1.9-f96-macosx-x86")
                  (failure-p t
                    (libname (:clsql-helper :cl-csv)
                     ,(lp-ticket "1258883"))
                    (system-name ("data-table-clsql" "function-cache-clsql")
                     ,(lp-ticket "1258883"))))
                 (libname (:hunchentoot :hunchentoot-auth :hunchentoot-cgi :hunchentoot-vhost
                           :cl-dropbox :cl-oauth :cl-paypal :amazon-ecs :ayah-captcha
                           :cl-cheshire-cat :cl-server-manager :cl-webdav :cxml-rpc :ext-blog
                           :firephp :formlets :gtfl :hh-web :ht-simple-ajax :smackjack
                           :restas :restas-directory-publisher :restas.file-publisher :rpc4cl)
                  (failure-p t
                   (lisp-impl-type :clisp
                    ,(lp-ticket "1258948"))))
                 (system-name ("cl-twit-repl" "cl-twitter"
                               "clack-handler-hunchentoot" "clack-middleware-oauth")
                  (failure-p t
                   (lisp-impl-type :clisp
                    ,(lp-ticket "1258948"))))
                 (libname (:cl-html-parse :cl-openid :cl-web-crawler :nekthuth)
                  (failure-p t
                   (lisp-impl-type (:abcl :acl :cmu :ecl)
                    ,(lp-ticket "1252283"))))
                 (system-name "dbd-sqlite3"
                  (failure-p t
                    (lisp ("ecl-12.12.1-unknown-linux-i686-bytecode"
                           "ecl-13.4.1-94e04b54-linux-x64-bytecode"
                           "ecl-13.5.1-237af2e8-linux-i686-bytecode"
                           "ecl-13.5.1-unknown-linux-i686-bytecod")
                     ,(lp-ticket "1258995"))))
                 (libname :cl-launch
                  (lisp ("abcl-1.1.1-fasl39-linux-x86"
                         "clisp-2.49-unix-i386"
                         "clisp-2.49-unix-x64"
                         "clisp-2.49-win-x86"
                         "ecl-12.12.1-unknown-linux-i686-lisp-to-c"
                         "sbcl-1.0.57.0.debian-linux-x64"
                         "sbcl-1.1.0.36.mswinmt.1201-284e340-win-x64"
                         "sbcl-1.1.0.36.mswinmt.1201-284e340-win-x86")
                   (failure-p t
                     "Needs newer ASDF")))
                 (system-name ("cl-mongo" "twitter-mongodb-driver")
                  (failure-p t
                   (lisp-impl-type :ecl
                     ,(lp-ticket "1259029"))))
                 (libname (:cl-redis :cl-secure-read)
                  (failure-p t
                   ,(lp-ticket "1243540")))
                 (libname :cl-tuples (failure-p t ,(lp-ticket "1259051")))
                 (libname (:coleslaw :inferior-shell)
                  (lisp ("abcl-1.2.0-fasl42-linux-x86"
                         "abcl-1.2.1-fasl42-linux-x64"
                         "abcl-1.2.1-fasl42-macosx-x64"
                         "ccl-1.9-f96-linux-x64"
                         "ccl-1.9-f96-linux-x86"
                         "ccl-1.9-f96-macosx-x64"
                         "ccl-1.9-f96-macosx-x86"
                         "clisp-2.49-win-x86"
                         "ecl-12.12.1-unknown-linux-i686-bytecode"
                         "ecl-13.4.1-0e93edfc-win-x86-bytecode"
                         "ecl-13.4.1-0e93edfc-win-x86-lisp-to-c"
                         "ecl-13.4.1-94e04b54-linux-x64-bytecode"
                         "ecl-13.4.1-94e04b54-linux-x64-lisp-to-c"
                         "ecl-13.5.1-unknown-linux-i686-bytecode"
                         "ecl-13.5.1-unknown-linux-i686-lisp-to-c"
                         "sbcl-1.1.11-linux-x86")
                   (failure-p t
                          "inferior-shell needs newer ASDF")))
                 (libname :gendl
                  (system-name "surf"
                   (lisp "ccl-1.9-f96-linux-x86"
                     ,(lp-ticket "1261297"))))
                 (libname (:eager-future2 :intercom :stmx :thread.comm.rendezvous :myweb)
                  (lisp "ecl-13.4.1-94e04b54-linux-x64-lisp-to-c"
                    (failure-p t "Not a regresssion; bug #261 in old ECL shows up due to differrent compilation order")))
                 (system-name "funds"
                   (lisp ("sbcl-1.0.57.0.debian-linux-x64"
                          "clisp-2.49-unix-x64")
                    (failure-p t
                      "Not a regression, result of a different compilation order")))
                 (system-name "kl-verify"
                  (lisp ("cmu-snapshot-2013-04__20d_unicode_-linux-x86")
                    (failure-p t "Not a regression, result of a different compilation order")))
                 (libname (:hu.dwim.perec :jenkins :metacopy :metatilities :moptilities
                           :tinaa :weblocks :weblocks-stores :weblocks-tree-widget
                           :rpm)
                  (fail-condition-type ("ASDF:MISSING-DEPENDENCY-OF-VERSION"
                                        "ASDF/FIND-COMPONENT:MISSING-DEPENDENCY-OF-VERSION")
                   ,(lp-ticket "1262020")))
                 (libname :l-math
                   (lisp-impl-type (:acl :clisp :ecl)
                    (failure-p t
                      ,(lp-ticket "1262026"))))
                 (libname :lisp-interface-library
                  (lisp ("ccl-1.8-f95-win-x64"
                         "ccl-1.8-f95-win-x86"
                         "ccl-1.9-f96-linux-x64"
                         "ccl-1.9-f96-linux-x86"
                         "ccl-1.9-f96-macosx-x64"
                         "ccl-1.9-f96-macosx-x86"
                         "ecl-12.12.1-unknown-linux-i686-bytecode"
                         "ecl-13.4.1-0e93edfc-win-x86-bytecode"
                         "ecl-13.4.1-0e93edfc-win-x86-lisp-to-c"
                         "ecl-13.4.1-94e04b54-linux-x64-bytecode"
                         "ecl-13.4.1-94e04b54-linux-x64-lisp-to-c"
                         "ecl-13.5.1-237af2e8-linux-i686-bytecode"
                         "ecl-13.5.1-237af2e8-linux-i686-lisp-to-c"
                         "ecl-13.5.1-unknown-linux-i686-bytecode"
                         "ecl-13.5.1-unknown-linux-i686-lisp-to-c"
                         "sbcl-1.0.57.0.debian-linux-x64"
                         "sbcl-1.1.0.36.mswinmt.1201-284e340-win-x64"
                         "sbcl-1.1.0.36.mswinmt.1201-284e340-win-x86")
                   (failure-p t
                          "requires ASDF 3 or later")))
                 (libname :rutils
                  (failure-p t
                   ,(lp-ticket "1243540")))
                 (libname (:smtp4cl :plain-odbc :net4cl)
                  (lisp-impl-type :sbcl
                   (failure-p t
                     "Not a regression; constant redifinition shows up due to different compilation order."))))
                (lib-world "quicklisp 2013-12-13 + asdf.38337a5"
                 (libname (:exscribe :lisp-interface-library)
                   (fail-condition-type "QUICKLISP-CLIENT:SYSTEM-NOT-FOUND"
                     "Quicklisp dependencies calculation/handling bug"))
                 (fail-condition-type "CCL:NO-APPLICABLE-METHOD-EXISTS"
                     "CCL:SLOT-VALUE-USING-CLASS problem after ASDF upgrade")
                (system-name ("hu.dwim.computed-class+hu.dwim.logger"
                              "hu.dwim.computed-class.test"
                              "caveman-test")
                 (fail-condition-type "ASDF/FIND-SYSTEM:LOAD-SYSTEM-DEFINITION-ERROR"
                   "Quicklisp :defsystem-depends-on problem")))
                (lib-world "quicklisp 2013-12-13 + asdf.28a5c93"
                 (libname (:exscribe :lisp-interface-library)
                   (fail-condition-type "QUICKLISP-CLIENT:SYSTEM-NOT-FOUND"
                     "Quicklisp dependencies calculation/handling bug"))
                 (fail-condition-type "CCL:NO-APPLICABLE-METHOD-EXISTS"
                     "CCL:SLOT-VALUE-USING-CLASS problem after ASDF upgrade")
                 (system-name ("hu.dwim.computed-class+hu.dwim.logger"
                               "hu.dwim.computed-class.test"
                               "caveman-test")
                 (fail-condition-type "ASDF/FIND-SYSTEM:LOAD-SYSTEM-DEFINITION-ERROR"
                   "Quicklisp :defsystem-depends-on problem"))
                (system-name "ningle-test"
                  (fail-condition-type ("USOCKET:ADDRESS-IN-USE-ERROR" "USOCKET:OPERATION-NOT-PERMITTED-ERROR")
                    ,(lp-ticket "1269486"))))
                (lib-world "quicklisp 2013-12-13 + asdf.28a5c93.no-upgrade"
                 (libname (:exscribe :lisp-interface-library)
                   (fail-condition-type "QUICKLISP-CLIENT:SYSTEM-NOT-FOUND"
                     "Quicklisp dependencies calculation/handling bug"))
                 (system-name ("hu.dwim.computed-class+hu.dwim.logger"
                               "hu.dwim.computed-class.test"
                               "caveman-test")
                 (fail-condition-type "ASDF/FIND-SYSTEM:LOAD-SYSTEM-DEFINITION-ERROR"
                   "Quicklisp :defsystem-depends-on problem"))
                (system-name "ningle-test"
                  (fail-condition-type ("USOCKET:ADDRESS-IN-USE-ERROR" "USOCKET:OPERATION-NOT-PERMITTED-ERROR")
                    ,(lp-ticket "1269486"))))                (lib-world "qlalpha 2014-01-05"
                 (fail-condition-type "QUICKLISP-CLIENT:SYSTEM-NOT-FOUND"
                   "Quicklisp dependencies calculation/handling bug")
                 (fail-condition-type "ASDF/FIND-SYSTEM:LOAD-SYSTEM-DEFINITION-ERROR"
                   "Quicklisp :defsystem-depends-on problem"))
                (lib-world "qlalpha 2014-01-11"
                 (fail-condition-type "QUICKLISP-CLIENT:SYSTEM-NOT-FOUND"
                   "Quicklisp dependencies calculation/handling bug")
                 (fail-condition-type "ASDF/FIND-SYSTEM:LOAD-SYSTEM-DEFINITION-ERROR"
                   "Quicklisp :defsystem-depends-on problem"))
                (lib-world "quicklisp 2014-01-13"
                 (libname (:more-conditions :xml.location)
                   (failure-p t
                     ,(github-issue "scymtym" "more-conditions" 1)))
                 (libname (:cl-csv)
                   (lisp ("acl-9.0-linux-x64" "acl-9.0-linux-x86" "acl-9.08-linux-x64"
                          "acl-9.08-linux-x86" "acl-9.08s-linux-x64" "acl-9.08s-linux-x86"
                          "acl-9.0s-linux-x64" "acl-9.0s-linux-x86")
                     ,(github-issue "AccelerationNet" "cl-csv" 16)))
                 (libname (:collectors :clsql-helper :data-table)
                   (lisp ("acl-9.0-linux-x64"
                          "acl-9.0-linux-x86"
                          "acl-9.08-linux-x64"
                          "acl-9.08-linux-x86"
                          "acl-9.08s-linux-x64"
                          "acl-9.08s-linux-x86"
                          "acl-9.0s-linux-x64"
                          "acl-9.0s-linux-x86")
                     ,(github-issue "AccelerationNet" "collectors" 3)))
                 (libname :com.informatimago
                    (lisp "sbcl-1.1.0.36.mswinmt.1201-284e340-win-x86"
                       "QL-DIST:BADLY-SIZED-LOCAL-ARCHIVE")))
                (lib-world "qlalpha 2014-02-04"
                  ,(lambda (result)
                     (cond ((and (string= "COMMON-LISP:SIMPLE-ERROR" (fail-condition-type result))
                                 (or (search "lfp.h" (fail-condition-text result))
                                     (search "Couldn't execute \"g++\"" (fail-condition-text result))))
                            "grovel error")
                           ((and (string= "QUICKLISP-CLIENT:SYSTEM-NOT-FOUND" (fail-condition-type result))
                                 (search "System \"iolib/" (fail-condition-text result)))
                            "ql:system-not-found"))))
                (lib-world "quicklisp 2014-01-13 + asdf.3.1.0.64.warn-check"
                  (failure-p t
                    (libname :rutils
                      ,(lp-ticket "1243540"))
                    ,(lambda (result)
                       (when (search "ASDF/COMPONENT:COMPONENT-CHILDREN" (fail-condition-text result))
                         "component-children"))))
                (lib-world "quicklisp 2014-02-11"
                   (fail-condition-type "QUICKLISP-CLIENT:SYSTEM-NOT-FOUND"
                     "ql:system-not-found")
                   ,(lambda (r)
                      (cond ((search "You need ASDF >= 2.31.1"
                                     (fail-condition-text r))
                             "needs ASDF >= 2.31.1")
                            ((search "lfp.h: No such file"
                                     (fail-condition-text r))
                             "iolib grovel")
                            ((search "\"iolib."
                                     (fail-condition-text r))
                             "iolib.*")))
                   (libname :cleric
                     (lisp-impl-type (:acl :clisp)
                       ,(github-issue "flambard" "CLERIC" 9))))
                (lib-world "qlalpha 2014-03-14"
                   (fail-condition-type "QUICKLISP-CLIENT:SYSTEM-NOT-FOUND"
                     "ql:system-not-found")
                   ,(lambda (r)
                      (when (search ":ASDF does not match version 3.0.1" (fail-condition-text r))
                        "needs ASDF >= 3.0.1"))
                  (system-name "cl-lastfm-test"
                    (failure-p t
                      "no package SB-POSIX"))
                  (system-name "single-threaded-ccl"
                    (lisp "clisp-2.49-unix-x86"
                      "needs newer ASDF")))
                (lib-world "quicklisp 2014-03-17"
                  (lisp "abcl-1.3.0-svn-14683-fasl42-linux-x86"
                    ,(lambda (r)
                       (when (search "Java exception 'java.lang.NullPointerException'"
                                     (fail-condition-text r))
                         "NPE"))))
                (lib-world ("qlalpha 2014-04-21" "quicklisp 2014-04-25")
                 (libname (:more-conditions :xml.location :architecture.service-provider)
                   (failure-p t
                     ,(github-issue "scymtym" "more-conditions" 2)))
                 (system-name "cl-i18n"
                   (failure-p t
                     "Needs newer UIOP"))
                 (libname :lisp-interface-library
                   (lisp ("sbcl-1.1.11-linux-x86" "sbcl-1.1.16-linux-x86")
                     (failure-p t
                       "Needs newer UIOP")))
                 (libname :stumpwm
                   (lisp-impl-type :clisp
                     (failure-p t
                      ,(github-issue "stumpwm" "stumpwm" 88))))
                 (libname :torta
                   (lisp-impl-type :cmu
                     (failure-p t
                      ,(github-issue "sgarciac" "torta" 1))))
                 (libname :hu.dwim.computed-class
                   (lisp "sbcl-1.1.11-linux-x86"
                     (failure-p t
                       ":HU.DWIM.LOGGER not found"))))
                (lib-world "quicklisp 2014-04-25"
                 (libname (:exscribe :scribble :fare-quasiquote)
                   (failure-p t
                     "Needs newer UIOP"))
                 (lisp "abcl-1.3.1-fasl42-linux-x86"
                  (libname :cl-containers
                    ,(prj-ticket :abcl 357)))
                 (libname :utils-kt
                  (failure-p t
                    (lisp ("abcl-1.3.1-fasl42-linux-x86" "abcl-1.3.0-fasl42-linux-x86" "abcl-1.2.1-fasl42-linux-x86")
                      "stack overflow")))
                 (lisp "sbcl-1.1.18.572-8feebec-linux-x86"
                   ,(lambda (r)
                            (when (search "SB-C::IR2-BLOCK" (fail-condition-text r))
                              "NIL isn't SB-C::IR2-BLOCK"))
                   (fail-condition-type "EDITOR-HINTS.NAMED-READTABLES:READER-MACRO-CONFLICT"
                     "named-readtables")))
                (lib-world "quicklisp 2014-04-25 + asdf.synt-control.e4229d8"
                 (system-name "cl-indeterminism"
                   (lisp "sbcl-1.1.11-linux-x86"
                     "Quicklisp bug"))
                 (system-name "teepeedee2"
                   (lisp ("sbcl-1.1.11-linux-x86" "clisp-2.49-unix-x86")
                     ,(github-issue "vii" "teepeedee2" 4))))
                (lib-world "quicklisp 2014-04-25 + asfd.3.1.0.120"
                 (libname :utils-kt
                  (failure-p t
                    (lisp ("abcl-1.3.1-fasl42-linux-x86")
                      "stack overflow")))
                 (system-name "teepeedee2"
                   (lisp ("sbcl-1.1.11-linux-x86" "clisp-2.49-unix-x86")
                     ,(github-issue "vii" "teepeedee2" 4))))
                (lib-world ("qlalpha 2014-05-24" "quicklisp 2014-05-25")
                   (failure-p t
                     (libname :lquery
                       (lisp-impl-type (:ccl :clisp :cmu)
                         ,(github-issue "Shinmera" "lquery" 1)))
                     (libname :colleen
                       (lisp-impl-type :sbcl
                         ,(github-issue "Shinmera" "colleen" 5)))
                     (libname :cl-mustache
                       ,(github-issue "kanru" "cl-mustache" 15))
                     (fail-condition-type "QUICKLISP-CLIENT:SYSTEM-NOT-FOUND"
                       "ql:system-not-found")
                     ,(lambda (r)
                              (cond ((search "FAST-UNSAFE-SOURCE-FILE" (fail-condition-text r))
                                     "ASDF: don't recognize component type FAST-UNSAFE-SOURCE-FILE")
                                    ((search "C::*DEBUG*" (fail-condition-text r))
                                     "C::*DEBUG* is unbound")))))
                  (lib-world ("qlalpha 2014-06-12")
                   (failure-p t
                     (system-name ("hu.dwim.computed-class+hu.dwim.logger" "hu.dwim.computed-class.test")
                       (lisp "sbcl-1.1.11-linux-x86"
                         ":HU.DWIM.LOGGER not found"))
                     (system-name "crane-web"
                       (lisp "cmu-snapshot-2014-01__20e_unicode_-linux-x86"
                          ,(prj-ticket :cmucl 99)))
                     ,(lambda (r)
                              (when (or (search "Component \"asdf\" does not match version 3.0" (fail-condition-text r))
                                        (search "there is no package with name \"UIOP\"" (fail-condition-text r)))
                                     "needs newer ASDF"))))
                  (lib-world ("quicklisp 2014-06-16")
                    (failure-p t
                      ,(lambda (r)
                         (when (or (search "Component \"asdf\" does not match version 3.0" (fail-condition-text r))
                                   (search "there is no package with name \"UIOP\"" (fail-condition-text r)))
                           "needs newer ASDF"))
                      (system-name "crane-web"
                        (lisp ("cmu-snapshot-2014-01__20e_unicode_-linux-x86"
                               "cmu-snapshot-2014-05-dirty__20e_unicode_-linux-x86")
                          ,(prj-ticket :cmucl 99)))))
                  (lib-world ("qlalpha 2014-09-11" "quicklisp 2014-09-14")
                    (failure-p t
                      (system-name "pgloader"
                        (lisp-impl-type :abcl
                          ,(prj-ticket :pgloader 114)))
                      (system-name "lisp-unit2"
                                   "Russ Tyndall informed, fix released.")))
                  (lib-world ("quicklisp 2015-06-08 + asdf.d70a8f8"
                              "quicklisp 2015-06-08 + asdf.c3f7c73")
                    (failure-p t
                      (lisp "abcl-1.3.2-fasl42-linux-x86"
                        (system-name "cl-bloom"
                                     "Ignore - must be the same error"))
                      (lisp "abcl-1.3.0-fasl42-linux-x86"
                        (system-name "cl-bloom"
                                     "Ignore - must be the same error")
                        (system-name ("lucerne-test" "eazy-process.test")
                                     "not a regression"))
                      (lisp "abcl-1.2.1-fasl42-linux-x86"
                        (system-name ("cl-bloom" "type-i.test"
                                      "trivia.balland2006.enabled.test"
                                      "trivia.balland2006.test")
                          "not a regression"))
                      (lisp "ccl-1.8-r15286m-f95-linux-x86"
                        (system-name ("coleslaw" "lime-test" "cl-rrt.benchmark")
                                     "not a regression"))
                      (lisp "clisp-2.49-unix-x86"
                        (system-name ("eazy-gnuplot.test" "eazy-process.test"
                                      "eazy-project.test" "lime-test" "gtk-cff"
                                      "smackjack-demo" "cl-inotify")
                                     "not a regression")
                        (system-name "opticl-doc" "can be reproduced without new ASDF"))
                      (lisp "cmu-snapshot-2014-12___20f_unicode_-linux-x86"
                        (system-name ("ele-bdb" "beirc" "cl-libusb") "the same error"))
                      (lisp "ecl-13.5.1-unknown-linux-i686-bytecode"
                        (system-name ("arrow-macros" "esrap-liquid")
                                     "not a regression"))
                      (lisp "ecl-13.5.1-unknown-linux-i686-lisp-to-c"
                        (system-name "crane-test" "not a regression"))
                      (lisp "sbcl-1.0.58-linux-x86"
                        (system-name "lime-test" "not a regression")
                        ,(lambda (r)
                           (when (search "The system definition for \"sb-rotate-byte\" uses deprecated ASDF option :IF-COMPONENT-DEP-FAILS. Starting with ASDF 3, please use :IF-FEATURE instead"
                                         (fail-condition-text r))
                             "sb-rotate-byte deployed with old SBCL (it's not from Quicklisp) relies on old ASDF")))
                      (lisp "sbcl-1.2.6-linux-x86"
                        (system-name "checkl-docs" "Ignore - it uses (asdf:load-system :cl-gendoc) instead of :defsystem-depends-on")
                        (system-name "inner-conditional-test" "Ignore - SBCL conservative GC problem")
                        (system-name "racer" "Happens sometimes, without new ASDF too"))
                      (lisp-impl-type :ecl
                        (fail-condition-text "COMPILE-FILE-ERROR while compiling #<cl-source-file \"alexandria\" \"macros\">"
                           "Ignore. Wandering ECL bug, happens elsewhere too."))))

                  (lib-world ("quicklisp 2015-09-24 + asdf.3.1.5.20")
                    (failure-p t
                      (system-name "opticl-doc"
                        (lisp-impl-type :clisp
                           "Ignore. Reproduces sometimes without new ASDF too."))
                      (libname (:nst :track-best)
                        (lisp "ccl-1.8-r15286m-f95-linux-x86"
                           ;; see also: http://osdir.com/ml/asdf-devel/2015-07/msg00052.html
                           (fail-condition-text "value NIL is not of the expected type STRUCTURE."
                             ,(prj-ticket :ccl 784))))))
                  (lib-world ("quicklisp 2015-12-18")
                    (failure-p t
                      (fail-condition-text "Undefined foreign symbol: \"SSL_CTX_set_default_verify_dir\""
                        ,(prj-ticket :cl+ssl 33))))


                  ;; also reported
                  ;; https://github.com/fukamachi/quri/issues/4
                  ;; https://github.com/fukamachi/xsubseq/issues/1

                  ;; (lib-world ("qlalpha 2014-12-15" "quicklisp 2014-12-17")
                  ;;   (failure-p t
                  ;;    ,(lambda (r)
                  ;;             (when (search "VARIABLE-INFORMATION" (fail-condition-text r))
                  ;;               (prj-ticket :xsubseq 1)))
                  ;;   ))


                  ;;; Well known failures ;;;
                  (failure-p t
                    (lisp-impl-type :ccl
                      (libname :usocket
                        (result-spec ((:whole-test-suite :timeout))
                          ,(lambda (r)
                             (when (search "1.11" (lisp r))
                                   (prj-ticket :ccl 1324)))))
                      (libname :cl-python
                        (result-spec ((:whole-test-suite :fail))
                          ,(lambda (r)
                             (when (search "1.11" (lisp r))
                                   (prj-ticket :ccl 1323))))))
                    (ecl-alexandria-bug-p t
                      "Ignore. Wandering ECL bug, happens elsewhere too.")
                    (system-name "checkl-docs"
                        ,(lambda (r) (search "Component :CL-GENDOC not found"
                                            (fail-condition-text r)))
                        "Ignore - checkl-docs uses (asdf:load-system :cl-gendoc) instead of :defsystem-depends-on")
                    (lisp-impl-type :ccl
                     ,(lambda (r)
                        (when (search "No MAKE-LOAD-FORM method is defined for #S(CL-COLORS:RGB :RED 38/51 :GREEN 38/51 :BLUE 38/51)"
                                      (fail-condition-text r))
                          (prj-ticket :cl-ansi-text 7)))
                     ,(lambda (r)
                        (when (and (search "There is no applicable method for the generic function:"
                                           (fail-condition-text r))
                                   (search "#<STANDARD-GENERIC-FUNCTION CCL:SLOT-VALUE-USING-CLASS"
                                           (fail-condition-text r)))
                           (prj-ticket :ccl 1157))))
                    (lisp-impl-type :abcl
                      (fail-condition-text "There is no class named ABSTRACT-CONTAINER."
                         ,(prj-ticket :abcl 357)))
                    (fail-condition-type ("ASDF/FIND-SYSTEM:LOAD-SYSTEM-DEFINITION-ERROR"
                                          "ASDF:LOAD-SYSTEM-DEFINITION-ERROR")
                      ,(lambda (r)
                         (let ((err-text (fail-condition-text r)))
                           (when (or ;; The symbol NON-PROPAGATING-OPERATION is not present in package ASDF/INTERFACE.
                                     (search "NON-PROPAGATING-OPERATION" err-text)
                                     (search "REINITIALIZE-INSTANCE: illegal keyword/value pair" err-text)
                                     ;; :MAILTO is an invalid initarg to REINITIALIZE-INSTANCE
                                     (search "is an invalid initarg to REINITIALIZE-INSTANCE" err-text)
                                     (search "There is no symbol ASDF::NON-PROPAGATING-OPERATION" err-text)
                                     (search "Cannot COMMON-LISP:IMPORT \"NON-PROPAGATING-OPERATION\" from package \"ASDF\"" err-text)
                                     (search "Cannot IMPORT \"NON-PROPAGATING-OPERATION\" from package \"ASDF\"" err-text))
                             "needs newer ASDF"))))))))

(defclass manual-text-note ()
  ((text :initarg :text :accessor note-text)))

(defun manual-text-note (text)
  (make-instance 'manual-text-note :text text))

(defun ensure-manual-note (note)
  "Ensures the NOTE is either a ticket object, or a MANUAL-TEXT-NOTE object."
  (if (stringp note)
      (manual-text-note note)
      note))

(defun notes (result)
  (let ((notes (db-notes *note-db* result)))
    (when (ffi-failure-p result)
      (push "ffi" notes))
    (when (ffi-grovel-failure-p result)
      (push "ffi-grovel" notes))
    (setf notes (mapcar #'ensure-manual-note notes))
    (if (fail-condition-type result)
      (append notes
              (list (format nil "~A : ~A"
                            (fail-condition-type result)
                            (fail-condition-text result))))
      notes)))
