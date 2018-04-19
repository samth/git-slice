#lang racket

(provide git-exe
         filter-input
         -system*
         -system*/print
         extract-commits
         closure)

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
  
  (let ([num-without-parents (for/sum ([v (in-hash-values commit->parents)])
                               (if (null? v)
                                   1
                                   0))])
    (unless (= 1 num-without-parents)
      (error 'git-slice
             (~a "expect 1 initial commit, found ~a commits without parents\n"
                 "commits: ~a")
             num-without-parents
             (for/list ([(k v) commit->parents]
                        #:when (null? v))
               k))))
  
  (values commits head-commit commit->parents commit->children))


(define (closure start-commits commit->next)
  (let ([ht (make-hash)])
    (for ([start-commit (in-list start-commits)])
      (let loop ([a start-commit])
        (or (hash-ref ht a #f)
            (let ([s (for/fold ([s (set a)]) ([p (in-list (hash-ref commit->next a null))])
                       (set-union s (loop p)))])
              (hash-set! ht a s)
              s))))
    ht))
