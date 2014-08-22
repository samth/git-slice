#lang racket
(require "git.rkt")

(define-values (dest-dir)
  (command-line
   #:args
   (dest-dir)
   (values dest-dir)))

(define prune (path->string (collection-file-path "prune.rkt" "git-slice")))
(define commit (path->string (collection-file-path "commit.rkt" "git-slice")))

(define-values (oldest-relevant start-at-commit)
  (apply values
         (call-with-input-file (build-path dest-dir "oldest.rktd")
           read)))

(system* git-exe
         "filter-branch"
         "--index-filter" (~a "racket " (~s prune) " " (~s dest-dir))
         "--commit-filter" (~a "if ! racket " (~s commit) " " (~a dest-dir) " \"$@\" ;"
                               " then skip_commit \"$@\" ;"
                               " fi")
         "--"
         (~a start-at-commit "..HEAD"))
