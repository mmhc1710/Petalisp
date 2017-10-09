;;; © 2016-2017 Marco Heisig - licensed under AGPLv3, see the file COPYING

(in-package :petalisp)

(define-class kernel-target (strided-array-computation)
  ((fragments :type (vector kernel-fragment))
   (users :initform nil
          :type (vector kernel-fragment)
          :accessor users)))

(defun kernel-ready? (kernel-target)
  (zerop (unevaluated-fragment-counter kernel-target)))

(defmethod graphviz-successors ((purpose data-flow-graph) (kernel-target kernel-target))
  (apply #'concatenate 'list
         (fragments kernel-target)
         (mapcar #'bindings (fragments kernel-target))))

(defmethod graphviz-node-plist append-plist ((purpose data-flow-graph) (kernel-target kernel-target))
  `(:shape "octagon"
    :fillcolor "cornflowerblue"))

(defmethod graphviz-edge-plist append-plist
    ((purpose data-flow-graph) (a kernel-target) (b kernel-target))
  `(:style "dashed"))
