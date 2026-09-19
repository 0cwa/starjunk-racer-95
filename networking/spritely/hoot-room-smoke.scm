(use-modules (goblins)
             (goblins ocapn captp)
             (goblins ocapn netlayer websocket)
             (starjunk race-room)
             (starjunk content)
             (rnrs bytevectors))

(define (make-browser-capn)
  (let ((netlayer
         (spawn ^websocket-netlayer
                #:verify-certificates? #t)))
    (spawn-mycapn netlayer)))

(define hoot-content-smoke
  (let* ((descriptor
          (list "starjunk95/content/1"
                "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                "starjunk95/car/1"))
         (bytes (bytevector 95 42))
         (content (spawn ^content-reader descriptor
                         (list (cons "model.glb" bytes))))
         (blob ($ content 'open-blob "model.glb")))
    (list ($ blob 'size)
          ($ blob 'read 0 2))))

(list race-control-protocol
      content-protocol
      max-blob-chunk-bytes
      (procedure? make-browser-capn)
      hoot-content-smoke)
