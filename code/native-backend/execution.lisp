;;;; © 2016-2019 Marco Heisig         - license: GNU AGPLv3 -*- coding: utf-8 -*-

(in-package #:petalisp.native-backend)

(defmethod compute-immediates ((lazy-arrays list)
                               (native-backend native-backend))
  (let ((root-buffers (petalisp.ir:ir-from-lazy-arrays lazy-arrays native-backend)))
    (petalisp.ir:normalize-ir root-buffers)
    (loop for root-buffer in root-buffers
          for lazy-array in lazy-arrays
          ;; We add a fictitious kernel to the outputs of each root buffer,
          ;; to avoid that their memory is reclaimed.
          do (push (make-instance 'kernel) (petalisp.ir:outputs root-buffer))
          collect
          (if (immediatep lazy-array)
              lazy-array
              (coerce-to-lazy-array
               (storage
                (compute-buffer root-buffer native-backend)))))))

(defmethod compute-buffer ((buffer immediate-buffer) (native-backend native-backend))
  buffer)

(defmethod compute-buffer ((buffer non-immediate-buffer) (native-backend native-backend))
  (unless (slot-boundp buffer '%storage)
    (setf (storage buffer)
          (memory-pool-allocate
           (memory-pool native-backend)
           (element-type buffer)
           (mapcar #'set-size (ranges (petalisp.ir:buffer-shape buffer)))))
    (loop for kernel in (inputs buffer) do
      (execute-kernel kernel native-backend))
    buffer))

(defmethod execute-kernel :before
    ((kernel kernel) (native-backend native-backend))
  (loop for load in (petalisp.ir:loads kernel) do
    (compute-buffer (petalisp.ir:buffer load) native-backend)))

(defmethod execute-kernel
    ((kernel kernel) (native-backend native-backend))
  (unless (executedp kernel)
    (compile-and-execute-kernel kernel native-backend)
    (setf (executedp kernel) t)
    ;; Free the memory of buffers that are no longer in use.
    (flet ((maybe-free (buffer)
             (when (every #'executedp (petalisp.ir:outputs buffer))
               (free-storage buffer native-backend))))
      (mapc (compose #'maybe-free #'petalisp.ir:buffer)
            (petalisp.ir:stores kernel)))))

(defun compile-and-execute-kernel (kernel backend)
  (let ((ranges (load-time-value (make-array 0 :adjustable t :fill-pointer 0) nil))
        (reduction-range (load-time-value (make-array 3) nil))
        (arrays (load-time-value (make-array 0 :adjustable t :fill-pointer 0) nil))
        (functions (load-time-value (make-array 0 :adjustable t :fill-pointer 0) nil))
        (compiled-kernel
          (let ((blueprint (petalisp.ir:blueprint kernel)))
            (petalisp.utilities:with-hash-table-memoization (blueprint)
                (compile-cache backend)
              (compile nil (lambda-expression-from-blueprint blueprint))))))
    (setf (fill-pointer ranges) 0)
    (setf (fill-pointer arrays) 0)
    (setf (fill-pointer functions) 0)
    ;; Initialize the range arguments.
    (loop for range in (ranges (petalisp.ir:iteration-space kernel))
          for offset from 0 by 3 do
            (multiple-value-bind (start step end)
                (range-start-step-end range)
              (vector-push-extend start ranges)
              (vector-push-extend step ranges)
              (vector-push-extend end ranges)))
    ;; Initialize the reduction range.
    (let ((range (petalisp.ir:reduction-range kernel)))
      (unless (null range)
        (multiple-value-bind (start step end)
            (range-start-step-end range)
          (setf (aref reduction-range 0) start)
          (setf (aref reduction-range 1) step)
          (setf (aref reduction-range 2) end))))
    ;; Initialize the array arguments.
    (loop for buffer in (petalisp.ir:kernel-buffers kernel) do
      (vector-push-extend (the array (storage buffer)) arrays))
    ;; Initialize the function arguments.
    (petalisp.ir:map-instructions
     (lambda (instruction)
       (when (typep instruction
                    '(or petalisp.ir:call-instruction petalisp.ir:reduce-instruction))
         (let ((operator (operator instruction)))
           (when (functionp operator)
             (vector-push-extend (operator instruction) functions)))))
     kernel)
    ;; Now call the compiled kernel.
    (funcall compiled-kernel ranges reduction-range arrays functions)))

(defgeneric free-storage (buffer backend))

(defmethod free-storage ((buffer buffer) (backend native-backend))
  (values))

(defmethod free-storage ((buffer non-immediate-buffer) (backend native-backend))
  (let ((memory-pool (memory-pool backend))
        (storage (storage buffer)))
    (setf (storage buffer) nil)
    (memory-pool-free memory-pool storage)
    (values)))
