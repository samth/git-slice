(module prune '#%kernel
  (#%require (for-syntax '#%kernel '#%utils))

  (define-syntaxes (git-exe-stx)
    (lambda (stx)
      (let-values ([(pth) (find-executable-path "git")])
        (if (not pth)
            (error 'git-prune "could not find `git` in path")
            (datum->syntax stx (cons 'quote (cons pth null)))))))

  (define-values (git-exe) (git-exe-stx))

  (define-values (dir) (vector-ref (current-command-line-arguments) 0))

  (define-values (commit)
    (environment-variables-ref (current-environment-variables)
                               #"GIT_COMMIT"))

  (define-values (relevants-file) (build-path dir "relevants.rktd"))
  (define-values (relevants) (call-with-input-file relevants-file read))

  ;; Shortcut for irrelevant commits:
  (if (not (hash-ref relevants commit #f))
      (exit 0)
      (void))

  (define-values (state-file) (build-path dir "state.rktd"))
  (define-values (keeps) (call-with-input-file state-file read))

  (define-values (actions-file) (build-path dir "actions.rktd"))
  (define-values (actionss) (call-with-input-file actions-file read))

  #;
  (call-with-output-file
      (build-path dir "log")
    (lambda (o) (fprintf o "~s\npre: ~s\n" commit keeps))
    'append)

  (define-values (actions) (hash-ref actionss commit null))

  (for-each (lambda (a)
              (if (eq? (car a) 'enter)
                  (set! keeps (hash-set keeps (cadr a) #t))
                  (void)))
            actions)

  (define-values (p i o e) (subprocess #f
                                       (current-input-port)
                                       (current-error-port)
                                       git-exe
                                       "ls-files"))
  (define-values (loop)
    (lambda (l)
      (define-values (r) (read-bytes-line i))
      (if (eof-object? r)
          l
          (if (hash-ref keeps r #f)
              (loop l)
              (loop (cons r l))))))

  (define-values (files) (loop null))

  (define-values (split)
    (lambda (a l i)
      (if (zero? i)
          (values a l)
          (if (null? l)
              (values a null)
              (split (cons (car l) a)
                     (cdr l)
                     (sub1 i))))))

  (define-values (do-in-chunks)
    (lambda (l)
      (define-values (chunk rest) (split null l 1024))
      (define-values (p2 i2 o2 e2) (apply
                                    subprocess
                                    (current-output-port)
                                    (current-input-port)
                                    (current-error-port)
                                    git-exe
                                    "rm"
                                    "--cached"
                                    "-q"
                                    chunk))
      (subprocess-wait p2)
      (if (null? rest)
          (void)
          (do-in-chunks rest))))

  (if (null? files)
      (void)
      (do-in-chunks files))

  (for-each (lambda (a)
              (if (eq? (car a) 'leave)
                  (set! keeps (hash-remove keeps (cadr a)))
                  (void)))
            actions)

  (if (null? actions)
      void
      (call-with-output-file state-file (lambda (o) (write keeps o)) 'truncate))

  #;
  (call-with-output-file
      (build-path dir "log")
    (lambda (o) (fprintf o "~a\npost: ~s\n" commit keeps))
    'append)

  )
