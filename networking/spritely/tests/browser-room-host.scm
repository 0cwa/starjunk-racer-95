(use-modules (goblins)
             (goblins ocapn ids)
             (goblins ocapn captp)
             (goblins ocapn netlayer websocket)
             (fibers conditions)
             (starjunk race-room))

(define args (command-line))
(unless (= (length args) 2)
  (error "usage: browser-room-host.scm <sturdyref-output>"))

(define sturdyref-output (cadr args))
(define host-vat (spawn-vat #:name "starjunk-browser-smoke-host"))
(define host-netlayer
  (with-vat host-vat
    (spawn ^websocket-netlayer
           #:host "127.0.0.1"
           #:port 0
           #:encrypted? #f)))
(define host-mycapn
  (with-vat host-vat
    (spawn-mycapn host-netlayer)))
(define room
  (with-vat host-vat
    (spawn ^race-room)))

(define registered? (make-condition))
(define room-reference #f)

(with-vat host-vat
  (on (<- host-mycapn 'register room 'websocket)
      (lambda (sturdyref)
        (set! room-reference (ocapn-id->string sturdyref))
        (call-with-output-file sturdyref-output
          (lambda (port)
            (display room-reference port)
            (newline port)))
        (signal-condition! registered?))
      #:catch
      (lambda (err)
        (format (current-error-port)
                "browser room registration failed: ~a~%"
                err)
        (exit 2))))

(wait registered?)
(format #t "STARJUNK_BROWSER_ROOM_READY ~a~%" room-reference)
(force-output)

;; The shell harness terminates this process after Chromium has joined and
;; proven readiness.  Keeping the vat alive preserves the registered room.
(wait (make-condition))
