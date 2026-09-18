(define-module (starjunk content)
  #:use-module (goblins)
  #:use-module (goblins actor-lib methods)
  #:use-module (rnrs bytevectors)
  #:export (^content-reader
            ^blob-reader
            content-protocol
            max-blob-chunk-bytes))

(define content-protocol "starjunk95/content-capability/1")
(define max-blob-chunk-bytes 65536)

(define (find-blob blobs path)
  (let ((entry (assoc path blobs)))
    (and entry (cdr entry))))

(define (copy-bytevector-range source offset count)
  (let ((result (make-bytevector count 0)))
    (let loop ((index 0))
      (when (< index count)
        (bytevector-u8-set!
         result
         index
         (bytevector-u8-ref source (+ offset index)))
        (loop (+ index 1))))
    result))

(define-actor (^blob-reader _bcom path bytes)
  (define byte-count (bytevector-length bytes))
  (methods
   [(protocol) content-protocol]
   [(path) path]
   [(size) byte-count]
   [(read offset requested-count)
    (unless (and (integer? offset)
                 (>= offset 0)
                 (<= offset byte-count))
      (error "invalid blob offset"))
    (unless (and (integer? requested-count)
                 (> requested-count 0)
                 (<= requested-count max-blob-chunk-bytes))
      (error "invalid blob read size"))
    (let ((count (min requested-count (- byte-count offset))))
      (copy-bytevector-range bytes offset count))]))

(define-actor (^content-reader _bcom descriptor blobs)
  (methods
   [(protocol) content-protocol]
   [(descriptor) descriptor]
   [(open-blob path)
    (unless (string? path)
      (error "blob path must be a string"))
    (let ((bytes (find-blob blobs path)))
      (unless (bytevector? bytes)
        (error "unknown blob path"))
      (spawn ^blob-reader path bytes))]))
