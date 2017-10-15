;;; © 2016-2017 Marco Heisig - licensed under AGPLv3, see the file COPYING

(in-package :petalisp)

(defun evaluate-kernel (kernel)
  (let* ((binding-symbols
           (iterate (for index below (length (bindings kernel)))
                    (collect (binding-symbol index))))
         (target-declaration-specifier
           `(type ,(type-of (storage (target kernel))) target))
         (binding-declaration-specifiers
           (iterate (for binding in-vector (bindings kernel)
                         with-index index downto 0)
                    (collect
                        `(type ,(type-of (storage binding))
                               ,(binding-symbol index))
                      at beginning))))
    (apply
     (compile-form
      `(lambda (target ,@binding-symbols)
         (declare
          ,target-declaration-specifier
          ,@binding-declaration-specifiers)
         (%for ,(ranges
                 (funcall
                  (inverse (zero-based-transformation (target kernel)))
                  (index-space kernel)))
               ,(recipe kernel))))
      (storage (target kernel))
      (map 'list #'storage (bindings kernel)))))

(define-symbol-pool binding-symbol "A")

(defmacro %for (ranges body)
  (let* ((indices (iterate (for index below (length ranges))
                           (collect (index-symbol index))))
         (result `(setf (aref target ,@indices) ,body)))
    (iterate
      (for range in-vector ranges)
      (for index from 0)
      (setf result
            `(iterate (for (the fixnum ,(index-symbol index))
                           from ,(range-start range)
                           by   ,(range-step range)
                           to   ,(range-end range))
                      ,result)))
    result))

(defparameter *compile-cache* (make-hash-table :test #'equalp))

(defun compile-form (form)
  (with-hash-table-memoization (form :multiple-values nil)
      *compile-cache*
    (print "Cache miss!")
    (print form)
    (compile nil form)))
