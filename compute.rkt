#lang racket

(require "git.rkt")
(provide go)

(define (go subdir dest-dir tmp-dir dry-run?)
  (printf "# git-slice: computing commits ...\n\n")
  (define start-time (current-milliseconds))
  
  (printf "Using temporary directory ~a\n" (path->string dest-dir))
  (when tmp-dir
    (printf "Using scratch directory ~a\n" (path->string tmp-dir)))
  
  (define exists-flag (if dry-run? 'error 'truncate))
  
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
  
  (define main-line-commits
    (let loop ([a head-commit])
      (cons a
            (let ([p (hash-ref commit->parents a)])
              (if (null? p)
                  null
                  (loop (car p)))))))
  
  (define commit->main?
    (for/hash ([f (in-list main-line-commits)])
      (values f #t)))
  
  (define (advance-to-main commit)
    (if (hash-ref commit->main? commit #f)
        commit
        (advance-to-main (car (hash-ref commit->children commit)))))
  
  (define files
    (for/list ([f (in-directory subdir)]
               #:when (file-exists? f))
      (path->bytes f)))
  
  (define lifetimes (make-hash))
  (define relevants (make-hash))
  
  ;; Since a file can be copied, it might have multiple "ending"
  ;; points in the lifetimes of different files, so make sure we
  ;; consider its latest ending point.
  (define (already-started-later? f start-commit)
    (define lt (hash-ref lifetimes f #f))
    (and lt
         (let ([old-start-commit (car lt)])
           (define m (member old-start-commit main-line-commits))
           (unless m (error 'slide "start commit not found in main line: ~a" old-start-commit))
           (or (member start-commit m)
               (begin
                 (unless (member start-commit main-line-commits)
                   (error 'slide "new start commit not found in main line: ~a" start-commit))
                 #f)))))
  
  ;; Determine the commit range that applies to a file.
  ;; We use `git log --follow' for this, because it's good
  ;; at find the point at which a file name changes.
  ;; We don't use `git log --follow' to get the full history
  ;; of a file, because it's incomplete after a rename.
  (define (find-lifetime! f start-commit)
    (unless (already-started-later? f start-commit)
      (let ([current-name f]
            [prev-name #f]
            [in-commit #f]
            [done? #f])
        (define (do-commit!)
          (when (and in-commit prev-name)
            (printf "~a : ~a...~a^\n" prev-name start-commit in-commit)
            (hash-set! lifetimes prev-name (cons start-commit in-commit))
            (find-lifetime! current-name (advance-to-main in-commit))
            (set! done? #t)))
        (void
         (filter-input
          (lambda (l)
            (cond
              [done? (void)]
              [(regexp-match #rx"^commit (.*)$" l)
               =>
               (lambda (m)
                 (do-commit!)
                 (set! in-commit (cadr m))
                 (hash-set! relevants in-commit #t))]
              [(regexp-match #rx#"^(?:copy|rename) to (.*)$" l)
               =>
               (lambda (m)
                 (define old-name (cadr m))
                 (unless (equal? old-name prev-name)
                   (error 'slice (~a "confused by rename\n"
                                     "  current: ~a\n"
                                     "  from: ~a\n"
                                     "  previous: ~a\n"
                                     "  starting name: ~a")
                          current-name
                          old-name
                          prev-name
                          f)))]
              [(regexp-match #rx#"^(?:copy|rename) from (.*)$" l)
               =>
               (lambda (m)
                 (set! prev-name current-name)
                 (set! current-name (cadr m)))])
            #f)
          git-exe
          "log"
          "--follow"
          "-p"
          start-commit
          "--"
          f))
        (unless done?
          (do-commit!))
        (unless done?
          (printf "~a : ~a...\n" current-name start-commit)
          (hash-set! lifetimes current-name (cons start-commit #f))))))
  
  ;; Collect lifetimes of all interesting files, starting
  ;; with the ones we want in the end:
  (for ([f (in-list files)])
    (find-lifetime! f head-commit))
  
  (define commit->actions (make-hash))
  
  (for ([(f lt) (in-hash lifetimes)])
    (hash-update! commit->actions
                  (car lt)
                  (lambda (l)
                    (cons `(leave ,f) l))
                  null)
    (hash-update! commit->actions
                  (cdr lt)
                  (lambda (l)
                    (cons `(enter ,f) l))
                  null))
  
  (with-output-to-file (build-path dest-dir "state.rktd")
    #:exists exists-flag
    (lambda ()
      (write
       (for/hash ([a (in-list (hash-ref commit->actions #f null))])
         (values (cadr a) #t)))))
  
  (hash-remove! commit->actions #f)
  (with-output-to-file (build-path dest-dir "actions.rktd")
    #:exists exists-flag
    (lambda ()
      (write (for/hash ([(k v) (in-hash commit->actions)])
               (values (string->bytes/utf-8 k) v)))))
  
  (define oldest-relevant
    (let ([advanced-relevants
           (for/hash ([c (in-hash-keys relevants)])
             (values (advance-to-main c) #t))])
      (let loop ([cs main-line-commits] [c head-commit])
        (cond
          [(null? cs) c]
          [(hash-ref advanced-relevants (car cs) #f)
           (loop (cdr cs) (car cs))]
          [else (loop (cdr cs) c)]))))
  (printf "relevant commits bounded by ~a\n" oldest-relevant)
  (hash-set! relevants oldest-relevant #t)
  
  (with-output-to-file (build-path dest-dir "relevants.rktd")
    #:exists exists-flag
    (lambda ()
      (write (for/hash ([(k v) (in-hash relevants)])
               (values (string->bytes/utf-8 k) v)))))
  
  (with-output-to-file (build-path dest-dir "oldest.rktd")
    #:exists exists-flag
    (lambda ()
      (write (list oldest-relevant
                   (let ([parents (hash-ref commit->parents oldest-relevant)])
                     (and (pair? parents) (car parents)))))))
  
  (define how-many-relevant? (hash-count relevants))
  (define how-many-filtered? (for/sum ([i (in-list commits)]
                                       #:break (equal? i oldest-relevant))
                               1))
  
  (define end-time (current-milliseconds))
  (printf "\n### git-slice: computed commits in ~a seconds\n" (/ (- end-time start-time) 1000.))
  (values end-time how-many-relevant? how-many-filtered?))

(module+ main
  (define tmp-dir #f)
  (define dry-run? #f)
  (define-values (subdir dest-dir)
    (command-line
     #:once-each
     ["-d" scratch-dir
           "use <scratch-dir> as temporary working directory for `git filter-branch'"
           (set! tmp-dir (path->complete-path scratch-dir))]
     ["--dry-run"
      "describe but don't do destructive operations"
      (set! dry-run? #t)]
     #:args
     (subdir dest-dir)
     (values subdir (path->complete-path dest-dir))))
  (go subdir dest-dir tmp-dir dry-run?)
  (void))