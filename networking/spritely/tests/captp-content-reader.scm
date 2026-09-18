(use-modules (goblins)
             (goblins ocapn ids)
             (goblins ocapn captp)
             (goblins ocapn netlayer tcp-tls)
             (fibers conditions)
             (rnrs bytevectors)
             (starjunk content))

(define (check value message)
  (unless value
    (error message)))

(define fixture-size 70000)
(define fixture (make-bytevector fixture-size 95))
(bytevector-u8-set! fixture (- fixture-size 1) 42)

(define content-id
  "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
(define descriptor
  (list "starjunk95/content/1"
        content-id
        "starjunk95/car/1"
        (list (list "model.glb"
                    fixture-size
                    "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"))))

(define host-vat (spawn-vat #:name "starjunk-content-host"))
(define client-vat (spawn-vat #:name "starjunk-content-client"))

(define host-netlayer
  (with-vat host-vat
    (spawn ^tcp-tls-netlayer "localhost")))
(define client-netlayer
  (with-vat client-vat
    (spawn ^tcp-tls-netlayer "localhost")))

(define host-capn
  (with-vat host-vat
    (spawn-mycapn host-netlayer)))
(define client-capn
  (with-vat client-vat
    (spawn-mycapn client-netlayer)))

(define content
  (with-vat host-vat
    (spawn ^content-reader
           descriptor
           (list (cons "model.glb" fixture)))))

(define registered (make-condition))
(define sturdyref-string #f)
(with-vat host-vat
  (on (<- host-capn 'register content 'tcp-tls)
      (lambda (sturdyref)
        (set! sturdyref-string (ocapn-id->string sturdyref))
        (signal-condition! registered))
      #:catch
      (lambda (err)
        (format (current-error-port) "content registration failed: ~a~%" err)
        (exit 2))))
(wait registered)

(check (and (string? sturdyref-string)
            (string-prefix? "ocapn://" sturdyref-string))
       "expected content OCapN sturdyref")

(define done (make-condition))
(define failure #f)

(with-vat client-vat
  (define remote-content
    (<- client-capn
        'enliven
        (string->ocapn-id sturdyref-string)))
  (on (<- remote-content 'descriptor)
      (lambda (remote-descriptor)
        (unless (equal? remote-descriptor descriptor)
          (set! failure "remote content descriptor mismatch"))
        (on (<- remote-content 'open-blob "model.glb")
            (lambda (blob)
              (unless (remote-refr? blob)
                (set! failure "open-blob did not return a remote capability"))
              (on (<- blob 'size)
                  (lambda (size)
                    (unless (= size fixture-size)
                      (set! failure "remote blob size mismatch"))
                    (on (<- blob 'read 0 max-blob-chunk-bytes)
                        (lambda (first)
                          (unless (= (bytevector-length first)
                                     max-blob-chunk-bytes)
                            (set! failure "first chunk length mismatch"))
                          (unless (= (bytevector-u8-ref first 0) 95)
                            (set! failure "first chunk bytes mismatch"))
                          (on (<- blob
                                  'read
                                  max-blob-chunk-bytes
                                  max-blob-chunk-bytes)
                              (lambda (second)
                                (unless (= (bytevector-length second)
                                           (- fixture-size
                                              max-blob-chunk-bytes))
                                  (set! failure "second chunk length mismatch"))
                                (unless (= (bytevector-u8-ref
                                            second
                                            (- (bytevector-length second) 1))
                                           42)
                                  (set! failure "second chunk tail mismatch"))
                                (signal-condition! done)))))))))))))

(wait done)
(vat-halt! client-vat)
(vat-halt! host-vat)

(when failure
  (error failure))

(format #t "STARJUNK_CONTENT_CAPABILITY_OK ~a ~a bytes~%"
        content-id
        fixture-size)
