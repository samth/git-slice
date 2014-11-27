(module commit '#%kernel
  (#%require (for-syntax '#%kernel '#%utils))

  (define-values (dir) (vector-ref (current-command-line-arguments) 0))

  (define-values (commit)
    (environment-variables-ref (current-environment-variables)
                               #"GIT_COMMIT"))

  (define-values (relevants-file) (build-path dir "relevants.rktd"))
  (define-values (relevants) (call-with-input-file relevants-file read))

  ;; Shortcut for irrelevant commits:
  (if (not (hash-ref relevants commit #f))
      (exit 1)
      (void))

  (define-syntaxes (git-exe-stx)
    (lambda (stx)
      (let-values ([(pth) (find-executable-path "git")])
        (if (not pth)
            (datum->syntax stx '(error 'git-commit "could not find `git` in path"))
            (datum->syntax stx (cons 'quote (cons pth null)))))))

  (define-values (git-exe) (git-exe-stx))

  (define-values (in) (current-input-port))


  (define-values (tree-args)
    (cdr (vector->list (current-command-line-arguments))))

  (define-values (p i o e) (apply subprocess
                                  (current-output-port)
                                  #f
                                  (current-error-port)
                                  git-exe
                                  "commit-tree"
                                  tree-args))

  (define-values (bstr) (make-bytes 4096))

  (define-values (copy-loop)
    (lambda ()
      (define-values (n) (read-bytes! bstr in))
      (if (eof-object? n)
          (void)
          (begin
            (write-bytes bstr o 0 n)
            (copy-loop)))))
  (copy-loop)
  (write-bytes #"\noriginal commit: " o)
  (write-bytes commit o)
  (write-bytes #"\n" o)
  (close-output-port o)

  (subprocess-wait p))
