(use-modules (goblins)
             (goblins ocapn ids)
             (goblins ocapn captp)
             (goblins ocapn netlayer websocket)
             (goblins actor-lib methods)
             (fibers conditions)
             (starjunk race-room))

(define (check value message)
  (unless value
    (error message)))

(define host-vat (spawn-vat #:name "starjunk-host"))
(define client-vat (spawn-vat #:name "starjunk-client"))

(define host-netlayer
  (with-vat host-vat
    (spawn ^websocket-netlayer
           #:host "127.0.0.1"
           #:port 0
           #:encrypted? #f)))

(define client-netlayer
  (with-vat client-vat
    (spawn ^websocket-netlayer
           #:host "127.0.0.1"
           #:port 0
           #:encrypted? #f)))

(define host-mycapn
  (with-vat host-vat
    (spawn-mycapn host-netlayer)))

(define client-mycapn
  (with-vat client-vat
    (spawn-mycapn client-netlayer)))

(define room
  (with-vat host-vat
    (spawn ^race-room)))

;; Registration can depend on asynchronous netlayer startup. Exercise the
;; public asynchronous path instead of assuming the netlayer is immediately
;; ready for a synchronous local call.
(define registered? (make-condition))
(define room-sref #f)
(with-vat host-vat
  (on (<- host-mycapn 'register room 'websocket)
      (lambda (sref)
        (set! room-sref sref)
        (signal-condition! registered?))))
(wait registered?)

(define room-sref-string (ocapn-id->string room-sref))
(check (string-prefix? "ocapn://" room-sref-string)
       "registered room did not produce an OCapN sturdyref")

(define done? (make-condition))
(define failure #f)

(define remote-room
  (with-vat client-vat
    (<- client-mycapn
        'enliven
        (string->ocapn-id room-sref-string))))

(with-vat client-vat
  (on (<- remote-room 'protocol)
      (lambda (protocol)
        (unless (string=? protocol race-control-protocol)
          (set! failure "remote room protocol mismatch"))
        (on (<- remote-room 'join "client-racer-95")
            (lambda (racer)
              (unless (remote-refr? racer)
                (set! failure "returned racer facet was not a remote capability"))
              (on (<- racer 'id)
                  (lambda (racer-id)
                    (unless (string=? racer-id "client-racer-95")
                      (set! failure "remote racer facet returned wrong id"))
                    (on (<- racer 'ready #t)
                        (lambda (ready?)
                          (unless ready?
                            (set! failure "remote racer ready call failed"))
                          (signal-condition! done?))))))))))

(wait done?)

(vat-halt! client-vat)
(vat-halt! host-vat)

(when failure
  (error failure))

(format #t "Starjunk CapTP WebSocket two-node capability test passed: ~a~%"
        room-sref-string)
