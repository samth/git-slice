#lang racket

(provide git-exe
         filter-input)

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
