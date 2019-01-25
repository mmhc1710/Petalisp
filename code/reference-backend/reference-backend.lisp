;;;; © 2016-2019 Marco Heisig         - license: GNU AGPLv3 -*- coding: utf-8 -*-

(in-package #:petalisp.reference-backend)

;;; The purpose of the reference backend is to compute reference solutions
;;; for automated testing. It is totally acceptable that this
;;; implementation is slow or eagerly consing, as long as it is obviously
;;; correct.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Generic Functions

(defgeneric evaluate (strided-array))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Classes

(defclass reference-backend (backend)
  ())

(defun make-reference-backend ()
  (make-instance 'reference-backend))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods

(defmethod compute-immediates ((strided-arrays list) (backend reference-backend))
  (mapcar #'evaluate strided-arrays))

;;; Memoization

(defvar *memoization-table*)

(defmethod compute-immediates :around
    ((strided-arrays list) (backend reference-backend))
  (let ((*memoization-table* (make-hash-table :test #'eq)))
    (call-next-method)))

(defmethod evaluate :around ((strided-array strided-array))
  (petalisp.memoization:with-hash-table-memoization (strided-array)
      *memoization-table*
    (call-next-method)))

;;; Evaluation

(defmethod evaluate ((simple-immediate simple-immediate))
  simple-immediate)

(defmethod evaluate ((array-immediate array-immediate))
  (make-simple-immediate
   (shape array-immediate)
   (lambda (index)
     (apply #'aref (storage array-immediate) index))))

(defmethod evaluate ((range-immediate range-immediate))
  (make-simple-immediate (shape range-immediate) #'first))

(defmethod evaluate ((application application))
  (let ((inputs (mapcar #'evaluate (inputs application))))
    (make-simple-immediate
     (shape application)
     (lambda (index)
       (nth-value
        (value-n application)
        (apply (operator application)
               (mapcar (lambda (input) (iref input index)) inputs)))))))

(defmethod evaluate ((reduction reduction))
  (let* ((inputs (mapcar #'evaluate (inputs reduction)))
         (k (length inputs)))
    (make-simple-immediate
     (shape reduction)
     (lambda (index)
       (labels ((divide-and-conquer (range)
                  (if (size-one-range-p range)
                      (values-list
                       (mapcar (lambda (input)
                                 (iref input (cons (range-start range) index)))
                               inputs))
                      (multiple-value-bind (left right)
                          (split-range range)
                        (values-list
                         (subseq
                          (multiple-value-list
                           (multiple-value-call (operator reduction)
                             (divide-and-conquer left)
                             (divide-and-conquer right)))
                          0 k))))))
         (nth-value
          (value-n reduction)
          (divide-and-conquer (first (ranges (shape (first inputs)))))))))))

(defmethod evaluate ((fusion fusion))
  (let ((inputs (mapcar #'evaluate (inputs fusion))))
    (make-simple-immediate
     (shape fusion)
     (lambda (index)
       (iref (find-if (lambda (input) (set-contains (shape input) index)) inputs)
             index)))))

(defmethod evaluate ((reference reference))
  (let ((input (evaluate (input reference))))
    (make-simple-immediate
     (shape reference)
     (lambda (index)
       (iref input (transform index (transformation reference)))))))