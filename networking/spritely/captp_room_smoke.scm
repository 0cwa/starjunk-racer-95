(use-modules (goblins)
             (goblins actor-lib methods)
             (goblins ocapn ids)
             (goblins ocapn captp)
             (goblins ocapn netlayer tcp-tls)
             (fibers conditions))

(define control-protocol "starjunk95/race-control/3")

(define-actor (^racer-facet bcom racer-id)
  (methods
   [(whoami) racer-id]
   [(protocol) control-protocol]
   [(ready value) (and value #t)]))

(define-actor (^race-room bcom)
  (methods
   [(protocol) control-protocol]
   [(join racer-id)
    (spawn ^racer-facet racer-id)]))

(define host-vat (spawn-vat #:name "starjunk-host"))
(define host-netlayer
  (with-vat host-vat
    (spawn ^tcp-tls-netlayer "localhost")))
(define host-capn
  (with-vat host-vat
    (spawn-mycapn host-netlayer)))
(define room
  (with-vat host-vat
    (spawn ^race-room)))

(define sturdyref-ready (make-condition))
(define room-sturdyref-string #f)

(with-vat host-vat
  (on (<- host-capn 'register room 'tcp-tls)
      (lambda (room-sturdyref)
        (set! room-sturdyref-string
              (ocapn-id->string room-sturdyref))
        (signal-condition! sturdyref-ready))
      #:catch
      (lambda (err)
        (format (current-error-port) "registration failed: ~a~%" err)
        (exit 2))))

(wait sturdyref-ready)

(unless (and (string? room-sturdyref-string)
             (string-prefix? "ocapn://" room-sturdyref-string))
  (error "expected an OCapN sturdyref" room-sturdyref-string))

(define client-vat (spawn-vat #:name "starjunk-client"))
(define client-netlayer
  (with-vat client-vat
    (spawn ^tcp-tls-netlayer "localhost")))
(define client-capn
  (with-vat client-vat
    (spawn-mycapn client-netlayer)))

(define done (make-condition))
(define result #f)

(with-vat client-vat
  (define room-vow
    (<- client-capn
        'enliven
        (string->ocapn-id room-sturdyref-string)))
  (on (<- room-vow 'join "racer-95")
      (lambda (racer-facet)
        (on (<- racer-facet 'whoami)
            (lambda (racer-id)
              (on (<- racer-facet 'protocol)
                  (lambda (protocol)
                    (set! result (list racer-id protocol))
                    (signal-condition! done))
                  #:catch
                  (lambda (err)
                    (format (current-error-port) "protocol call failed: ~a~%" err)
                    (exit 5))))
            #:catch
            (lambda (err)
              (format (current-error-port) "facet call failed: ~a~%" err)
              (exit 4))))
      #:catch
      (lambda (err)
        (format (current-error-port) "join failed: ~a~%" err)
        (exit 3))))

(wait done)

(unless (equal? result (list "racer-95" control-protocol))
  (error "unexpected remote facet result" result))

(format #t "STARJUNK_SPRITELY_CAPTP_OK ~s~%" result)
