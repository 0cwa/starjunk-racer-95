(use-modules (goblins)
             (goblins ocapn captp)
             (goblins ocapn netlayer websocket)
             (starjunk race-room))

(define (make-browser-capn)
  (let ((netlayer
         (spawn ^websocket-netlayer
                #:verify-certificates? #t)))
    (spawn-mycapn netlayer)))

(list race-control-protocol
      (procedure? make-browser-capn))
