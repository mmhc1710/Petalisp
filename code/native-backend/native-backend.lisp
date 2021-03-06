;;;; © 2016-2019 Marco Heisig         - license: GNU AGPLv3 -*- coding: utf-8 -*-

(in-package #:petalisp.native-backend)

;;; This is the default Petalisp backend.  It generates portable, highly
;;; optimized Lisp code and compiles it using CL:COMPILE.

(defclass native-backend (asynchronous-backend)
  ((%memory-pool :initarg :memory-pool :reader memory-pool)
   (%worker-pool :initarg :worker-pool :reader worker-pool)
   (%compile-cache :initarg :compile-cache :reader compile-cache
                   :initform (make-hash-table :test #'eq))))

(defun make-native-backend (&key (threads 1))
  (check-type threads positive-integer)
  (make-instance 'native-backend
    :memory-pool (make-memory-pool)
    :worker-pool (lparallel:make-kernel threads)))
