#lang racket
(require "git.rkt"
         (prefix-in filter: "filter.rkt")
         (prefix-in compute: "compute.rkt")
         (prefix-in chop: "chop.rkt"))

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
   (subdir [dest-dir (make-temporary-file "slicetmp~a" 'directory)])
   (values subdir (path->complete-path dest-dir))))

(unless (directory-exists? dest-dir)
  (error 'git-slice 
         "destination directory ~a does not exist or isn't a directory"
         dest-dir))

(unless (directory-exists? subdir)
  (error 'git-slice
         "subdirectory ~a does not exist or isn't a directory"
         subdir))

(when (and tmp-dir (directory-exists? tmp-dir))
  (error 'git-slice
         "scratch directory ~a must not already exist"
         tmp-dir))

(when (and tmp-dir (file-exists? tmp-dir))
  (error 'git-slice
         "scratch directory ~a must not already exist"
         tmp-dir))


(define init-time (current-milliseconds))
(define-values (comp-time relevant filtered) (compute:go subdir dest-dir tmp-dir dry-run?))
(define filter-time (filter:go dest-dir tmp-dir dry-run? (list relevant filtered)))
(define end-time (chop:go dest-dir tmp-dir dry-run?))

(printf "\n### git-slice: finished in ~a total seconds\n" (/ (- end-time init-time) 1000.))
