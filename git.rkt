#lang racket

(provide git-exe
         filter-input
         -system*
         -system*/print
         extract-commits)

(define git-exe (find-executable-path "git"))

(unless git-exe
  (error 'git-slice "could not find `git` in path"))

(define (filter-input filter . cmd)
  (define-values (p out in err)
    (apply subprocess
           #f
           (current-input-port)
           (current-output-port)
           cmd))
  (begin0
   (for*/list ([l (in-lines out)]
               [v (in-value (filter l))]
               #:when v)
     v)
   (close-input-port out)
   (subprocess-wait p)))

(define (-system* cmd . args) (apply system* cmd (filter values args)))
(define (-system*/print . args) (displayln (apply ~a (add-between (filter values args) " "))))


(define (extract-commits)
  (define commits
    (filter-input
     string-split
     git-exe
     "log"
     "--pretty=%H %P"))
  
  (define head-commit (caar commits))
  
  (define commit->parents
    (for/hash ([cs (in-list commits)])
      (values (car cs) (cdr cs))))
  
  (define commit->children
    (for*/fold ([ht (hash)]) ([(k v) (in-hash commit->parents)]
                              [(c) (in-list v)])
      (hash-update ht c (lambda (p) (cons k p)) null)))
  
  (values commits head-commit commit->parents commit->children))
