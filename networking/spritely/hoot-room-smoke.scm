(use-modules (fibers)
             (fibers operations)
             (fibers promises)
             ((goblins) #:hide ($))
             ((goblins) #:select (($ . :)))
             (goblins ocapn ids)
             (goblins ocapn captp)
             (goblins ocapn netlayer websocket)
             (goblins vat)
             (starjunk race-room))

(define browser-vat #f)
(define browser-mycapn #f)
(define browser-racer #f)
(define browser-room-reference #f)
(define browser-racer-id #f)

;; Hoot/Goblins promises are not JavaScript promises. Convert a Goblins promise
;; reference into a Fibers operation so Procedure.call_async can yield without
;; blocking browser WebSocket callbacks. This mirrors the pinned Goblins/Hoot
;; browser integration pattern rather than exposing vows to JavaScript.
(define (await-promise-operation vat promise)
  (define (try-fn) #f)
  (define (block-fn state resume)
    (with-vat vat
      (on promise
          (lambda (value)
            (when (op-state-complete! state)
              (resume (lambda () value))
              #t))
          #:catch
          (lambda (err)
            (when (op-state-complete! state)
              (resume
               (lambda ()
                 (error "remote capability call failed" err)))
              #f))))
    (values))
  (make-base-operation #f try-fn block-fn))

(define (await-promise vat promise)
  (perform-operation (await-promise-operation vat promise)))

(define (call-with-vat* vat thunk)
  (call-with-values
      (lambda () (call-with-vat vat thunk))
    (case-lambda
      (() (values))
      ((value)
       (if (promise-refr? value)
           (await-promise vat value)
           value))
      (values*
       (apply values values*)))))

(define-syntax-rule (with-vat* vat body ...)
  (call-with-vat* vat (lambda () body ...)))

(define (make-browser-capn)
  (unless browser-vat
    (set! browser-vat
          (spawn-vat #:name "starjunk-browser")))
  (unless browser-mycapn
    (set! browser-mycapn
          (with-vat browser-vat
            (let ((netlayer
                   (spawn ^websocket-netlayer
                          #:verify-certificates? #t)))
              (spawn-mycapn netlayer)))))
  browser-mycapn)

(define (browser-join-room room-reference racer-id)
  (unless (and (string? room-reference)
               (string-prefix? "ocapn://" room-reference))
    (error "room reference must be an OCapN sturdyref"))
  (unless (and (string? racer-id)
               (> (string-length racer-id) 0)
               (<= (string-length racer-id) 96))
    (error "invalid racer id"))

  (let* ((mycapn (make-browser-capn))
         (remote-room
          (with-vat browser-vat
            (: mycapn
               'enliven
               (string->ocapn-id room-reference))))
         (protocol
          (with-vat* browser-vat
            (<- remote-room 'protocol))))
    (unless (string=? protocol race-control-protocol)
      (error "remote room protocol mismatch" protocol))
    (let ((racer
           (with-vat* browser-vat
             (<- remote-room 'join racer-id))))
      (set! browser-racer racer)
      (set! browser-room-reference room-reference)
      (set! browser-racer-id racer-id)
      #t)))

(define (browser-ready car-content-id track-content-id)
  (unless browser-racer
    (error "cannot become ready before joining a room"))
  (unless (ready-content-valid? car-content-id track-content-id)
    (error "ready content ids must be canonical sha256 identities"))
  (with-vat* browser-vat
    (<- browser-racer
        'ready
        #t
        car-content-id
        track-content-id)))

(define (browser-bridge-dispatch operation . args)
  (cond
   ((string=? operation "control-protocol")
    race-control-protocol)
   ((string=? operation "browser-capn-supported")
    (procedure? make-browser-capn))
   ((string=? operation "ready-content-valid")
    (and (= (length args) 2)
         (ready-content-valid? (car args) (cadr args))))
   ((string=? operation "joined-room-reference")
    (or browser-room-reference ""))
   ((string=? operation "joined-racer-id")
    (or browser-racer-id ""))
   (else
    (error "unknown Starjunk browser bridge operation" operation))))

(define (browser-bridge-dispatch-async resolved rejected operation . args)
  (call-with-async-result
   resolved rejected
   (lambda ()
     (cond
      ((string=? operation "join-room")
       (unless (= (length args) 2)
         (error "join-room requires room reference and racer id"))
       (browser-join-room (car args) (cadr args)))
      ((string=? operation "ready")
       (unless (= (length args) 2)
         (error "ready requires car and track content ids"))
       (browser-ready (car args) (cadr args)))
      (else
       (error "unknown asynchronous Starjunk browser bridge operation"
              operation))))))

(values browser-bridge-dispatch
        browser-bridge-dispatch-async)
