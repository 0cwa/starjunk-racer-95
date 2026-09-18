(use-modules (goblins)
             (goblins actor-lib methods))

(define control-protocol "starjunk95/race-control/1")

(define-actor (^racer-facet bcom racer-id)
  (methods
   [(whoami) racer-id]
   [(protocol) control-protocol]))

(define-actor (^race-room bcom)
  (methods
   [(protocol) control-protocol]
   [(join racer-id)
    (spawn ^racer-facet racer-id)]))

(define vat (spawn-vat #:name "starjunk-hoot-smoke"))

(with-vat vat
  (define room (spawn ^race-room))
  (define racer ($ room 'join "browser-racer"))
  (list ($ room 'protocol)
        ($ racer 'whoami)
        ($ racer 'protocol)))
