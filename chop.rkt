#lang racket
(require "git.rkt")
(provide go)

(define (go dest-dir tmp-dir dry-run?)
  
  (define-values (oldest-relevant start-at-commit)
    (apply values
           (call-with-input-file (build-path dest-dir "oldest.rktd")
             read)))
  (cond 
    [start-at-commit
     (define start-time (current-milliseconds))
     (printf "\n# git-slice: chopping early commits ...\n\n")
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
     
     (if dry-run?
         (printf "grafting from ~a\n" (car starts))
         (with-output-to-file
             ".git/info/grafts"
           (lambda ()
             (displayln (car starts)))))
     
     
     ((if dry-run? -system*/print -system*)
      git-exe
      "filter-branch"
      (and tmp-dir "-d")
      (and tmp-dir (~s tmp-dir))
      "--force")
     
     (unless dry-run? (delete-file ".git/info/grafts"))
     (define end-time (current-milliseconds))
     (printf "\n### git-slice: chopped commits in ~a seconds\n" (/ (- end-time start-time) 1000.))
     end-time]
    [else 
     (printf "\n# git-slice: no chopping to do\n")
     (current-milliseconds)]))

(module+ main
  (define tmp-dir #f)
  (define dry-run? #f)
  
  (define-values (dest-dir)
    (command-line
     #:once-each
     ["-d" scratch-dir
           "use <scratch-dir> as temporary working directory for `git filter-branch'"
           (set! tmp-dir (path->complete-path scratch-dir))]
     ["--dry-run"
      "describe but don't do destructive operations"
      (set! dry-run? #t)]
     #:args
     (dest-dir)
     (path->complete-path dest-dir)))

  (void (go dest-dir tmp-dir dry-run?)))
