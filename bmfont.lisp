(in-package :3b-bmfont)

#++
(ql:quickload '3b-bmfont)

(defun fs (f p)
  (let ((p (find-package p)))
    (when p
      (find-symbol (string f) p))))

(defun add-origins (font)
  ;; pre-calculate offsets to move glyph to baseline, accounting for
  ;; padding and Y-Axis direction
  (when font
    (loop with (nil nil down nil) = (padding font) ;; up right down left
          with chars = (chars font)
          with base = (base font)
          for c being the hash-keys of chars
            using (hash-value v)
          unless (glyph-origin v)
            do (let ((x (glyph-xoffset v))
                     (y (glyph-yoffset v)))
                 (setf (glyph-origin v) (list x (- y down base)))
                 (setf (glyph-origin-y-up v) (list x (- base (- y down)))))))
  font)

(defun read-bmfont (filename)
  (add-origins
   (with-open-file (f filename)
     (let ((c (peek-char t f nil nil)))
       (case c
         (#\<
          (let ((rf (fs '#:read-bmfont-xml '#:3b-bmfont-xml)))
            (if rf
                (funcall rf f)
                (error "can't read font metadata from ~s, xml backend not loaded"
                       filename))))
         (#\{
          (let ((rf (fs '#:read-bmfont-json '#:3b-bmfont-json)))
            (if rf
                (funcall rf f)
                (error "can't read font metadata from ~s, json backend not loaded"
                       filename))))
         (#\i
          (let ((rf (fs '#:read-bmfont-text '#:3b-bmfont-text)))
            (if rf
                (funcall rf f)
                (error "can't read font metadata from ~s, text backend not loaded"
                       filename))))
         (#\B
          (error "binary bmfont metadata format not implemented yet"))
         (t
          (error "unable to detect format of file ~s?" filename)))))))

(defun write-bmfont (font filename &key type)
  (let ((type (cond (type type)
                    ((string-equal "txt" (pathname-type filename)) :text)
                    ((string-equal "json" (pathname-type filename)) :json)
                    ((string-equal "xml" (pathname-type filename)) :xml)
                    (T (restart-case (error "Unknown file format ~s.~%Please specify the desired format type." (pathname-type filename))
                         (specify-type (type)
                           :interactive (lambda () (read *query-io*))
                           :report "Specify a new type."
                           type))))))
    (ecase type
      (:text
       (let ((wf (fs '#:write-bmfont-text '#:3b-bmfont-text)))
         (with-open-file (f filename :direction :output
                                     :if-does-not-exist :create
                                     :if-exists :supersede)
           (funcall wf font f))))
      (:xml
       (let ((wf (fs '#:write-bmfont-xml '#:3b-bmfont-xml)))
         (with-open-file (f filename :direction :output
                                     :if-does-not-exist :create
                                     :if-exists :supersede
                                     :element-type '(unsigned-byte 8))
           (funcall wf font f))))
      (:json
       (let ((wf (fs '#:write-bmfont-json '#:3b-bmfont-json)))
         (with-open-file (f filename :direction :output
                                     :if-does-not-exist :create
                                     :if-exists :supersede)
           (funcall wf font f)))))))

(defun space-size (font)
  (let ((glyph (or (gethash #\space (chars font))
                   (gethash #\n (chars font)))))
    (if glyph
        (glyph-xadvance glyph)
        (/ (loop for c in (alexandria:hash-table-values
                           (chars font))
                 sum (or (glyph-xadvance c) 0))
           (float (hash-table-count (chars font)))))))

(defun char-data (char font)
  (let ((chars (chars font)))
    (or (gethash char chars)
        (gethash :invalid chars)
        (gethash (code-char #xFFFD) chars)
        (load-time-value (make-glyph)))))

(defun map-glyphs (font function string &key model-y-up texture-y-up start end
                                          extra-space (x 0) (y 0))
  (loop with sw = (float (scale-w font))
        with sh = (float (scale-h font))
        with y = y
        with x = x
        with line = (line-height font)
        with space = (space-size font)
        with kernings = (kernings font)
        for p = nil then c
        for i from (or start 0) below (or end (length string))
        for c = (aref string i)
        for char = (char-data c font)
        for k = (%kerning kernings p c)
        for (dx dy) = (if model-y-up
                          (glyph-origin-y-up char)
                          (glyph-origin char))
        do (case c
             (#\newline
              (setf x 0)
              (incf y (if model-y-up (- line) line)))
             (#\space
              (incf x space))
             (#\tab
              ;; todo: make this configurable, add tab stop option?
              (incf x (* 8 space)))
             (t
              (incf x k)
              (let* ((x- (+ x dx))
                     (y- (+ y dy))
                     (cw (glyph-width char))
                     (ch (glyph-height char))
                     (x+ (+ x- cw))
                     (y+ (if model-y-up
                             (- y- ch)
                             (+ y- ch)))
                     (cx (glyph-x char))
                     (cy (glyph-y char))
                     (u- (/ cx sw))
                     (v- (/ cy sh))
                     (u+ (/ (+ cx cw) sw))
                     (v+ (/ (+ cy ch) sh)))
                (when texture-y-up
                  (psetf v- (- 1 v-)
                         v+ (- 1 v+)))
                (funcall function x- y- x+ y+ u- v- u+ v+))
              (incf x (glyph-xadvance char))
              (when extra-space (incf x extra-space))))
        finally (return (values x y))))

(defun measure-glyphs (font string &key start end)
  (loop with y = 0
        with x = 0
        with line = (line-height font)
        with space = (space-size font)
        with kernings = (kernings font)
        for p = nil then c
        for i from (or start 0) below (or end (length string))
        for c = (aref string i)
        for char = (char-data c font)
        for k = (%kerning kernings p c)
        do (case c
             (#\newline
              (setf x 0)
              (incf y line))
             (#\space
              (incf x space))
             (#\tab
              ;; todo: make this configurable, add tab stop option?
              (incf x (* 8 space)))
             (t
              (incf x k)
              (incf x (glyph-xadvance char))))
        finally (return (values x (+ y (base font))))))

#++
(ql:quickload '3b-bmfont/xml)
#++
(map-glyphs (read-bmfont "/tmp/r2.fnt")
            (lambda (x y x2 y2 u1 v1 u2 v2)
              (format t "~s ~s : ~s ~s   @   ~s ~s : ~s ~s~%"
                      x y x2 y2 u1 v1 u2 v2))
            "testing, 1 2 3
next line	tabbed")
