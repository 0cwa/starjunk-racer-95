(use-modules (goblins)
             (goblins ocapn captp)
             (goblins ocapn netlayer websocket)
             (starjunk race-room))

(define (make-browser-capn)
  (let ((netlayer
         (spawn ^websocket-netlayer
                #:verify-certificates? #t)))
    (spawn-mycapn netlayer)))

(define (browser-bridge-dispatch operation . args)
  (cond
   ((string=? operation "control-protocol")
    race-control-protocol)
   ((string=? operation "browser-capn-supported")
    (procedure? make-browser-capn))
   ((string=? operation "ready-content-valid")
    (and (= (length args) 2)
         (ready-content-valid? (car args) (cadr args))))
   (else
    (error "unknown Starjunk browser bridge operation" operation))))

browser-bridge-dispatch
