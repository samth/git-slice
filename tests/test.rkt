#lang racket
(require racket/runtime-path
         rackunit)

(define-runtime-module-path-index main "../main.rkt")

(define work-dir (make-temporary-file "~a-git-slice"
                                      'directory))

(define (reset-dir dir)
  (delete-directory/files #:must-exist? #f dir)
  (make-directory* dir))

(define repo-dir (build-path work-dir "repo"))
(reset-dir repo-dir)

(define commit-counts (hash))

;; ----------------------------------------
;; Script a  repository with interesting moves, branching, etc.

(parameterize ([current-directory repo-dir])
  (system "git init")
  
  (define (slices->msg line l)
    (~s (apply ~a #:separator " " "CHANGED:" line l)))
  (define (merge-counts a b)
    (for/fold ([a a]) ([(k v) (in-hash b)])
      (hash-update a k (lambda (n) (+ n v)) 0)))
  (define (increment-counts counts slices)
    (for/fold ([ht counts]) ([slice (in-list slices)])
      (hash-update ht slice add1 0)))
  
  (define n 32)
  (define (create p)
    ;; Create a file that will not be considered a copy
    ;; of any other file.
    (make-directory* (path-only p))
    (call-with-output-file*
     p
     (lambda (o)
       (for ([i 100])
         (display (random 100) o)
         (displayln (make-bytes n 60) o))
       (set! n (add1 n)))))
  (define (modify p)
    (define s (file->bytes p))
    (call-with-output-file*
     #:exists 'update
     p
     (lambda (o)
       (displayln (bytes-append
                   (subbytes s 0 n)
                   (make-bytes 100 n)
                   (subbytes s n))
                  o)
       (set! n (add1 n)))))
  (define (move s d)
    (make-directory* (path-only d))
    (system (~a "git mv " s " " d)))
  (define (copy s d)
    (make-directory* (path-only d))
    (copy-file s d))
  (define (do-commit line . slices)
    (set! commit-counts (increment-counts commit-counts slices))
    (system (~a "git add . && git commit -m " (slices->msg line slices))))
  (define-syntax (commit stx)
    (syntax-case stx ()
      [(_ slice ...)
       #`(do-commit #,(syntax-line stx) slice ...)]))
  (define (fork a b)
    (define old-counts commit-counts)
    (set! commit-counts (hash))
    (system "git branch left && git checkout left")
    (a)
    (define left-counts commit-counts)
    (set! commit-counts (hash))
    (system "git checkout master")
    (b)
    (define right-counts commit-counts)
    (define both-counts (merge-counts left-counts right-counts))
    (define slices (hash-keys both-counts))
    (system (~a "git merge -m " (slices->msg 0 slices) " left"
                " && git branch -d left"))
    (set! commit-counts (merge-counts old-counts both-counts)))
  
  ;; ------------------------------------------------------------
  ;; Files with names ending in "..._Alpha" will end up in "alpha",
  ;; etc., and each of those directories corresponds to a slice to
  ;; try. Each `commit` names the end slices that should include
  ;; the commit.
  
  (create "a/x_Alpha")
  (commit "Alpha")
  (modify "a/x_Alpha")
  (create "a/y_Alpha")
  (commit "Alpha")
  (create "b/x_Beta")
  (create "b/y_Beta")
  (commit "Beta")
  (move "a/x_Alpha" "a/z_Alpha")
  (move "a/y_Alpha" "c/y_Alpha")
  (commit "Alpha")
  (copy "b/x_Beta" "b/z_Beta")
  (commit "Beta")
  
  (fork
   (lambda ()
     (create "c/x_Gamma")
     (commit "Gamma")
     (modify "a/z_Alpha")
     (commit "Alpha"))
   (lambda ()
     (create "d/x_Delta")
     (commit "Delta")
     (modify "b/z_Beta")
     (move "b/y_Beta" "c/y_Beta")
     (commit "Beta")))
  
  ;; Move all into place:
  (move "a/z_Alpha" "alpha/x_Alpha")
  (move "c/y_Alpha" "alpha/y_Alpha")
  (move "b/x_Beta" "beta/x_Beta")
  (move "c/y_Beta" "beta/y_Beta")
  (move "b/z_Beta" "beta/z_Beta")
  (move "c/x_Gamma" "gamma/x_Gamma")
  (move "d/x_Delta" "delta/x_Delta")
  (commit "Alpha" "Beta" "Gamma" "Delta"))

;; ----------------------------------------
;; Extract and check slices

(define (slice slice)
  (define slice-dir (build-path work-dir "slice"))
  (reset-dir slice-dir)
  (parameterize ([current-directory work-dir])
    (system "git clone repo slice"))
  
  (define dir (string-foldcase slice))
  
  (parameterize ([current-directory slice-dir]
                 [current-command-line-arguments (vector dir)]
                 [current-namespace (make-base-namespace)])
    (define-values (name base) (module-path-index-split main))
    (dynamic-require (module-path-index-join name base) #f))
  
  (check-equal? (directory-list slice-dir)
                (map string->path (list ".git" dir)))
  
  (parameterize ([current-directory slice-dir])
    (define o (open-output-bytes))
    (parameterize ([current-output-port o])
      (system "git log"))
    (define commit-count
      (for/fold ([count 0]) ([l (in-lines (open-input-string
                                           (get-output-string o)))])
        (cond
         [(regexp-match? #rx"^commit " l)
          (add1 count)]
         [(regexp-match? #rx"^CHANGED: " l)
          (check-true (member slice (string-split l)))]
         [else count])))
    (check-equal? commit-count (hash-ref commit-counts slice))
    (unless (equal? commit-count (hash-ref commit-counts slice))
      (exit))
    ))

(slice "Alpha")
(slice "Beta")
(slice "Gamma")
(slice "Delta")

;; ----------------------------------------

(delete-directory/files work-dir)
