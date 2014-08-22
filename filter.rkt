#lang racket
(require "git.rkt")
(provide go)

(define prune (path->string (collection-file-path "prune.rkt" "git-slice")))
(define commit (path->string (collection-file-path "commit.rkt" "git-slice")))

(define (go dest-dir tmp-dir dry-run? [counts #f])
  (printf "\n# git-slice: filtering relevant commits ...\n\n")
  (define start-time (current-milliseconds))
 
  (define-values (oldest-relevant start-at-commit)
    (apply values
           (call-with-input-file (build-path dest-dir "oldest.rktd")
             read)))
  (define -dest-dir (if (path? dest-dir) (path->string dest-dir) dest-dir))

  (define res
    ((if dry-run? -system*/print -system*)
     git-exe
     "filter-branch"
     (and tmp-dir "-d")
     (and tmp-dir tmp-dir)
     "--index-filter" (~a "racket " (~s prune) " " (~s -dest-dir))
     "--commit-filter" (~a "if ! racket " (~s commit) " " (~a -dest-dir) " \"$@\" ;"
                           " then skip_commit \"$@\" ;"
                           " fi")
     (and start-at-commit "--")
     (and start-at-commit (~a start-at-commit "..HEAD"))))
  (unless res
      (error 'git-slice "filtering failed"))
  (define end-time (current-milliseconds))
  (define secs (/ (- end-time start-time) 1000.))
  (printf "\n### git-slice: filtered~a commits in ~a seconds~a\n" 
          (if counts (format " ~a (~a relevant)" (second counts) (first counts)) "")
          secs
          (if counts (format " (~a per second)" (/ (second counts) secs)) ""))
  end-time)

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
  
