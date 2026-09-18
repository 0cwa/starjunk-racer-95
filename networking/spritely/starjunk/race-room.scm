(define-module (starjunk race-room)
  #:use-module (goblins)
  #:use-module (goblins actor-lib methods)
  #:export (^race-room ^racer-facet race-control-protocol))

(define race-control-protocol "starjunk95/race-control/1")

(define-actor (^racer-facet _bcom racer-id)
  (methods
   [(id) racer-id]
   [(ready value)
    (and (boolean? value) value)]))

(define-actor (^race-room _bcom)
  (methods
   [(protocol) race-control-protocol]
   [(join racer-id)
    (unless (and (string? racer-id)
                 (> (string-length racer-id) 0)
                 (<= (string-length racer-id) 96))
      (error "invalid racer id"))
    (spawn ^racer-facet racer-id)]))
