(defsystem "petalisp.core"
  :author "Marco Heisig <marco.heisig@fau.de>"
  :license "AGPLv3"

  :depends-on
  ("alexandria"
   "closer-mop"
   "bordeaux-threads"
   "lparallel"
   "trivia"
   "trivial-arguments"
   "petalisp.utilities")

  :in-order-to ((test-op (test-op "petalisp.test-suite")))

  :serial t
  :components
  ((:file "packages")

   ;; Utilities
   (:file "ucons")

   ;; Type inference
   (:file "atomic-types")
   (:file "function-lambda-lists")
   (:file "inference")
   (:file "numbers")
   (:file "data-and-control-flow")

   ;; Sets
   (:file "set")
   (:file "empty-set")
   (:file "explicit-set")
   (:file "range")
   (:file "shape")

   ;; Transformations
   (:file "transformation")
   (:file "identity-transformation")
   (:file "invertible-transformation")
   (:file "hairy-transformation")
   (:file "make-transformation")
   (:file "shape-transformations")

   ;; Strided arrays.
   (:file "strided-array")
   (:file "immediate")
   (:file "reference")
   (:file "application")
   (:file "reduction")
   (:file "fusion")

   ;; Backend
   (:file "backend")))
