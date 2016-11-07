;;; © 2016 Marco Heisig - licensed under AGPLv3, see the file COPYING

(in-package :petalisp)

(define-class strided-array-fusion (strided-array fusion) ())

;;; (fusion #i((1 2 3) (1 2 3)) #i((2 2 4) (1 2 3)) #i((1 2 3) (2 2 4)) #i((2 2 4) (2 2 4)))
(defmethod fusion ((object strided-array-index-space) &rest more-objects)
  (let ((objects (list* object more-objects))
        (dimension (dimension object)))
    (apply #'make-index-space
           (loop for i below dimension
                 collect (apply #'fuse-dimension i objects)))))

(defmethod fusion ((object strided-array) &rest more-objects)
  (let ((objects (list* object more-objects)))
    (make-instance
     'strided-array-fusion
     :objects objects
     :ranges (ranges (apply #'fusion (mapcar #'index-space objects))))))

(defmethod fusion ((range range) &rest more-ranges)
  (let* ((ranges (list* range more-ranges))
         (fusion
           (loop for range in ranges
                 sum (size range) into number-of-elements
                 maximize (range-end range) into end
                 minimize (range-start range) into start
                 finally
                    (let ((step (ceiling (1+ (- end start))
                                         number-of-elements)))
                      (return (range start step end))))))
    fusion))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; fusion islands - index spaces that keep track of the ranges that must
;;; be fused in the next higher dimension

(define-class fusion-island (strided-array-index-space)
  (ranges-to-fuse))

;;; (fuse-dimension 0 #i((1 2 3) (1 2 3)) #i((2 2 4) (1 2 3)) #i((1 2 3) (2 2 4)) #i((2 2 4) (2 2 4)))
(defun fuse-dimension (dimension &rest objects)
  (let* ((islands
           (apply
            #'subdivision
            (mapcar
             (lambda (object)
               (let ((ranges (ranges object)))
                 (make-instance
                  'fusion-island
                  :ranges (subseq ranges (1+ dimension))
                  :ranges-to-fuse (list (aref ranges dimension)))))
             objects)))
         (fusions
           (mapcar
            (lambda (fusion-island)
              (apply #'fusion (ranges-to-fuse fusion-island)))
            islands)))
    (assert (identical fusions :test #'equal?))
    (first fusions)))

(defmethod intersection :around ((space-1 fusion-island)
                                 (space-2 fusion-island))
  (let ((result (call-next-method)))
    (when result
      (change-class result 'fusion-island
                    :ranges-to-fuse (union (ranges-to-fuse space-1)
                                           (ranges-to-fuse space-2))))))

(defmethod difference :around ((space-1 fusion-island)
                               (space-2 fusion-island))
  (let ((result (call-next-method)))
    (mapcar
     (lambda (x)
       (change-class x 'fusion-island
                     :ranges-to-fuse (ranges-to-fuse space-1)))
     result)))
