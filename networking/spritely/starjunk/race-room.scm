(define-module (starjunk race-room)
  #:use-module (goblins)
  #:use-module (goblins actor-lib methods)
  #:export (^race-room
            ^racer-facet
            race-control-protocol
            ready-content-valid?))

(define race-control-protocol "starjunk95/race-control/3")

(define (canonical-sha256-content-id? value)
  (and (string? value)
       (= (string-length value) 71)
       (string-prefix? "sha256:" value)
       (let loop ((index 7))
         (if (= index (string-length value))
             #t
             (let ((ch (string-ref value index)))
               (and (or (char-numeric? ch)
                        (and (char>=? ch #\a)
                             (char<=? ch #\f)))
                    (loop (+ index 1))))))))

(define (ready-content-valid? car-content-id track-content-id)
  (and (canonical-sha256-content-id? car-content-id)
       (canonical-sha256-content-id? track-content-id)))

(define-actor (^racer-facet _bcom racer-id)
  (methods
   [(id) racer-id]
   [(ready value car-content-id track-content-id)
    (and (boolean? value)
         value
         (ready-content-valid? car-content-id track-content-id))]
   [(unready) #t]))

(define-actor (^race-room _bcom)
  (methods
   [(protocol) race-control-protocol]
   [(join racer-id)
    (unless (and (string? racer-id)
                 (> (string-length racer-id) 0)
                 (<= (string-length racer-id) 96))
      (error "invalid racer id"))
    (spawn ^racer-facet racer-id)]))
