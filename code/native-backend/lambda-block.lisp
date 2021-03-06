;;;; © 2016-2019 Marco Heisig         - license: GNU AGPLv3 -*- coding: utf-8 -*-

(in-package #:petalisp.native-backend)

(defclass lambda-block (basic-block)
  ((%lambda-list :initarg :lambda-list :reader lambda-list)))

(defun make-lambda-block (&key lambda-list immediate-dominator)
  (make-instance 'lambda-block
    :lambda-list lambda-list
    :immediate-dominator immediate-dominator))

(defmethod form :around ((lambda-block lambda-block))
  (let ((symbols (lambda-list lambda-block)))
    `(lambda ,symbols
       (declare (ignorable ,@symbols))
       ,(call-next-method))))
