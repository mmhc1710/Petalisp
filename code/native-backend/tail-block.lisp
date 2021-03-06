;;;; © 2016-2019 Marco Heisig         - license: GNU AGPLv3 -*- coding: utf-8 -*-

(in-package #:petalisp.native-backend)

;;; A tail block is a basic block that ends in a particular form, e.g.,
;;; (values X Y) and has no successors.
(defclass tail-block (basic-block)
  ((%tail :initarg :tail :accessor tail)))

(defmethod tail-form ((tail-block tail-block))
  (tail tail-block))

(defun make-tail-block (&key tail immediate-dominator)
  (make-instance 'tail-block
    :tail tail
    :immediate-dominator immediate-dominator))
