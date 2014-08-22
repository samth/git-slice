#lang racket
(require "git.rkt")

(define-values (dest-dir)
  (command-line
   #:args
   (dest-dir)
   (values dest-dir)))

(define-values (oldest-relevant start-at-commit)
  (apply values
         (call-with-input-file (build-path dest-dir "oldest.rktd")
           read)))

(define starts
  (let ([done? #f]
        [in-commit #f])
    (filter-input
     (lambda (l)
       (cond
        [done? #f]
        [(regexp-match #rx"^commit (.*)$" l)
         =>
         (lambda (m)
           (set! in-commit (cadr m))
           #f)]
        [(regexp-match #rx"^    original commit: (.*)$" l)
         =>
         (lambda (m)
           (and (equal? (cadr m) oldest-relevant)
                in-commit))]
        [else #f]))
     git-exe
     "log")))

(unless (= 1 (length starts))
  (error 'chop
         "could not find new commit for ~a"
         oldest-relevant))

(with-output-to-file
 ".git/info/grafts"
 (lambda ()
   (displayln (car starts))))

(system* git-exe
         "filter-branch"
         "--force")

(delete-file ".git/info/grafts")
