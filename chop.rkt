#lang racket
(require "git.rkt")
(provide go)

(define (go dest-dir tmp-dir dry-run?)
  
  (define-values (oldest-relevant start-at-commit drop-oldest?)
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

     (define oldest-now (car starts))
     
     (cond
      [dry-run?
       (printf "grafting from ~a~a\n"
               (if drop-oldest? "children of " "")
               oldest-now)]
      [drop-oldest?
       (define-values (commits head-commit commit->parents commit->children)
         (extract-commits))
       
       (define cs (hash-ref commit->children oldest-now))
       (define new-initials (make-hash))
       (let loop ([cs cs])
         (for ([c (in-list cs)])
           (define ps (remove oldest-now (hash-ref commit->parents c)))
           (if (null? ps)
               (hash-set! new-initials c #t)
               (loop ps))))
       (define new-root
         (cond
          [((hash-count new-initials) . > . 1)
           ;; Dropping `oldest-now` might would multiple initial
           ;; commits, which is potentially confusing (to `git-slice`
           ;; itself, for example). Add an empty commit to serve
           ;; as the root.
           (printf "\n# Adding commit to serve as new initial commit\n")
           (-system* git-exe "checkout" "--orphan" "newroot")
           (-system* git-exe "rm" "-rf" ".")
           (-system* git-exe "commit" "--allow-empty" "-m" "create slice")
           (define new-root
             (car
              (filter-input (lambda (l)
                              (cond
                               [(regexp-match #rx"^commit (.*)$" l)
                                => (lambda (m) (cadr m))]
                               [else #f]))
                            git-exe
                            "log")))
           (-system* git-exe "checkout" "master")
           (-system* git-exe "branch" "-D" "newroot")
           new-root]
          [else #f]))
       (with-output-to-file ".git/info/grafts"
         (lambda ()
           (for ([c (in-list cs)])
             (displayln (apply ~a c
                               #:separator " "
                               (let ([ps (remove oldest-now
                                                 (hash-ref commit->parents c))])
                                 (if new-root
                                     (cons new-root ps)
                                     ps)))))))]
      [else
       (with-output-to-file ".git/info/grafts"
         (lambda ()
           (displayln oldest-now)))])
     
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
