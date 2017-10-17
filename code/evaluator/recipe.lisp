;;; © 2016-2017 Marco Heisig - licensed under AGPLv3, see the file COPYING

(in-package :petalisp)

;;; The recipe of a kernel is used both as a blueprint of some
;;; performance-critical function and as a key to search whether such a
;;; function has already been generated and compiled. The latter case is
;;; expected to be far more frequent, so the primary purpose of a recipe is
;;; to select an existing function as fast as possible and without
;;; consing. To achieve this, the recipe is stored as a tree of hash
;;; conses.

(defmacro define-recipe-grammar (&body definitions)
  `(progn
     ,@(iterate
         (for definition in definitions)
         (destructuring-bind (name &key ((:= lambda-list)) &allow-other-keys) definition
           (when lambda-list
             (let* ((variadic? (eq (last-elt lambda-list) '*))
                    (lambda-list (if variadic? (butlast lambda-list) lambda-list)))
               (collect
                   `(defun ,name ,lambda-list
                      ,(if variadic?
                           `(hlist* ',name ,@lambda-list)
                           `(hlist ',name ,@lambda-list))))
               (collect
                   `(defun ,(symbolicate name "?") (x)
                      (and (hconsp x) (eq (hcons-car x) ',name))))))))))

;;; The grammar of a recipe is:

(define-recipe-grammar
  (%recipe     := (range-info* target-info* source-info* expression))
  (%reference  := (%source-or-%target %index *))
  (%store      := (%reference expression))
  (%call       := (operator expression *))
  (%reduce     := (%range operator expression))
  (%accumulate := (%range operator initial-value expression))
  (%for        := (%range expression))
  (%index      :? (symbol rational rational))
  (%source     :? (symbol))
  (%target     :? (symbol))
  (%range      :? (symbol))
  (expression  :? (or %reference %store %call %reduce %accumulate %for))
  (range-info  :? (hlist min-size max-size step))
  (target-info :? petalisp-type-specifier)
  (source-info :? petalisp-type-specifier))

(define-symbol-pool %source "S")
(define-symbol-pool %target "T")
(define-symbol-pool %index  "I")
(define-symbol-pool %range  "R")

(defgeneric %indices (transformation)
  (:method ((transformation identity-transformation))
    (let ((dimension (input-dimension transformation))
          (zeros (load-time-value (hlist 0 0))))
      (with-vector-memoization (dimension)
        (let (result)
          (iterate
            (for index from (1- dimension) downto 0)
            (setf result (hcons (hcons (%index index) zeros) result)))
          result))))
  (:method ((transformation affine-transformation))
    (let (result)
      (iterate
        (for column in-vector (spm-column-indices (linear-operator transformation)) downto 0)
        (for value in-vector (spm-values (linear-operator transformation)) downto 0)
        (for offset in-vector (translation-vector transformation) downto 0)
        (setf result (hcons (hlist (%index column) value offset) result)))
      result)))

;; ugly
(defun zero-based-transformation (index-space)
  (let* ((ranges (ranges index-space))
         (dimension (length ranges)))
    (make-affine-transformation
     (make-array dimension :initial-element nil)
     (scaled-permutation-matrix
      dimension dimension
      (apply #'vector (iota dimension))
      (map 'vector #'range-step ranges))
     (map 'vector #'range-start ranges))))

;; the iterator should be factored out as a separate utility...
(define-condition iterator-exhausted () ())

(defvar *recipe-sources* nil)

(defvar *recipe-space* nil)

(defun map-recipes (function data-structure &key (leaf-test #'immediate?))
  "Apply FUNCTION to all recipes that compute values of DATA-STRUCTURE
   and reference data-structures that satisfy LEAF-TEST.

   For every recipe, FUNCTION receives the following arguments:
   1. the recipe
   2. the index space computed by the recipe
   3. a vector of all referenced data-structures"
  (labels
      ((mkiter (node space transformation depth)
         ;; convert leaf nodes to an iterator with a single value
         (if (funcall leaf-test node)
             (let ((first-visit? t))
               (λ (if first-visit?
                      (let ((index
                              (or (position node *recipe-sources*)
                                  (vector-push-extend node *recipe-sources*)))
                            (transformation
                              (composition
                               (inverse (zero-based-transformation (index-space node)))
                               (composition
                                transformation
                                (zero-based-transformation (index-space data-structure))))))
                        (setf first-visit? nil)
                        (%reference (%source index) (%indices transformation)))
                      (signal 'iterator-exhausted))))
             (etypecase node
               ;; unconditionally eliminate fusion nodes by path
               ;; replication. This replication process is the only
               ;; reason why we use tree iterators. A fusion node with
               ;; N inputs returns an iterator returning N recipes.
               (fusion
                (let ((input-iterators
                        (map 'vector
                             (λ input (mkiter input (index-space input) transformation depth))
                             (inputs node)))
                      (spaces (map 'vector #'index-space (inputs node)))
                      (index 0))
                  (λ (loop
                       (if (= index (length input-iterators))
                           (signal 'iterator-exhausted)
                           (handler-case
                               (let ((input-iterator (aref input-iterators index))
                                     (space (intersection
                                             space
                                             (funcall (inverse transformation)
                                                      (aref spaces index)))))
                                 (when space
                                   (setf *recipe-space* space)
                                   (return (funcall input-iterator))))
                             (iterator-exhausted ())))
                       (incf index)))))
               ;; application nodes simply call the iterator of each input
               (application
                (let ((input-iterators
                        (map 'vector
                             (λ x (mkiter x space transformation depth))
                             (inputs node))))
                  (λ
                   (let (args)
                     (iterate (for input-iterator in-vector input-iterators downto 0)
                              (setf args (hcons (funcall input-iterator) args)))
                     (%call (operator node) args)))))
               ;; eliminate reference nodes entirely
               (reference
                (let ((new-transformation (composition (transformation node) transformation))
                      (space (intersection
                              space
                              (funcall (inverse transformation)
                                       (index-space node)))))
                  (mkiter (input node) space new-transformation depth)))
               ;; reduction nodes
               (reduction
                (let ((input-iterator (mkiter (input node) space transformation (1+ depth))))
                  (λ (%reduce (%range depth) (operator node) (funcall input-iterator)))))))))
    (let ((recipe-iterator
            (mkiter data-structure
                    (index-space data-structure)
                    (make-identity-transformation (dimension data-structure))
                    (dimension data-structure))))
      (handler-case
          (loop
            (let ((*recipe-sources* (make-array 6 :fill-pointer 0))
                  (*recipe-space* (index-space data-structure)))
              (funcall function
                       (funcall recipe-iterator)
                       *recipe-space*
                       *recipe-sources*)))
        (iterator-exhausted () (values))))))