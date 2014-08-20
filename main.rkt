#lang racket

(define git-exe (find-executable-path "git"))

(unless git-exe
  (error 'git-slice "could not find `git` in path"))

(define-values (subdir dest-dir)
  (command-line
   #:args
   (subdir dest-dir)
   (values subdir dest-dir)))

(unless (directory-exists? dest-dir)
  (error 'git-slice 
         "destination directory ~a does not exist or isn't a directory"
         dest-dir))

(unless (directory-exists? subdir)
  (error 'git-slice
         "subdirectory ~a does not exist or isn't a directory"
         subdir))

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
    (path->string f)))

(define lifetimes (make-hash))

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
              (set! in-commit (cadr m)))]
           [(regexp-match #rx"^(?:copy|rename) to (.*)$" l)
            =>
            (lambda (m)
              (define old-name (cadr m))
              (unless (equal? old-name prev-name)
                (error 'slice (~a "confused by rename\n"
                                  "  current: ~a\n"
                                  "  from: ~a")
                       current-name
                       old-name)))]
           [(regexp-match #rx"^(?:copy|rename) from (.*)$" l)
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
  #:exists 'truncate
  (lambda ()
    (write
     (for/hash ([a (in-list (hash-ref commit->actions #f null))])
       (values (cadr a) #t)))))

(hash-remove! commit->actions #f)
(with-output-to-file (build-path dest-dir "actions.rktd")
  #:exists 'truncate
  (lambda ()
    (write (for/hash ([(k v) (in-hash commit->actions)])
             (values (string->bytes/utf-8 k) v)))))

                     
