;;;  (c) copyright 2003 by Mathieu Chabanne, Camille Constant,
;;;                        Emmanuel Necibar and Stephanie Recco
;;;
;;;  (c) copyright 2003 by Robert Strandh (strandh@labri.fr)
;;;
;;;  (c) copyright 2007 by David Lewis, Marcus Pearce, Christophe
;;;                        Rhodes and contributors
;;;
;;; This library is free software; you can redistribute it and/or
;;; modify it under the terms of version 2 of the GNU Lesser General
;;; Public License as published by the Free Software Foundation.
;;;
;;; This library is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Lesser General Public License for more details.
;;;
;;; You should have received a copy of the GNU Lesser General Public
;;; License along with this library; if not, write to the
;;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;;; Boston, MA  02111-1307  USA.
;;;
;;; This file contains library for MIDI and Midifiles. Messages are
;;; represented as CLOS class instances in a class hierarchy that
;;; reflects interesting aspects of the messages themselves.

(defpackage "MIDI"
  (:use "COMMON-LISP")
  (:export "ACTIVE-SENSING-MESSAGE" "ALL-NOTES-OFF-MESSAGE"
           "AUTHORIZATION-SYSTEM-EXCLUSIVE-MESSAGE" "CHANNEL-MESSAGE"
           "CHANNEL-PREFIX-MESSAGE" "CHANNEL-PRESSURE-MESSAGE"
           "COMMON-MESSAGE" "CONTINUE-SEQUENCE-MESSAGE"
           "CONTROL-CHANGE-MESSAGE" "COPYRIGHT-MESSAGE"
           "CUE-POINT-MESSAGE" "DATA-BYTE" "DEVICE-NAME-MESSAGE"
           "END-OF-TRACK-MESSAGE" "GENERAL-TEXT-MESSAGE" "HEADER"
           "HEADER-TYPE" "INSTRUMENT-MESSAGE" "KEY-SIGNATURE-MESSAGE"
           "LOCAL-CONTROL-MESSAGE" "LYRIC-MESSAGE" "MARKER-MESSAGE"
           "MESSAGE" "MESSAGE-CHANNEL" "MESSAGE-CONTROLLER"
           "MESSAGE-DATA" "MESSAGE-DENOMINATOR" "MESSAGE-KEY"
           "MESSAGE-MI" "MESSAGE-NUMERATOR" "MESSAGE-PORT"
           "MESSAGE-PRESSURE" "MESSAGE-PROGRAM" "MESSAGE-SEQUENCE"
           "MESSAGE-SF" "MESSAGE-TEMPO" "MESSAGE-TEXT" "MESSAGE-TIME"
           "MESSAGE-VALUE" "MESSAGE-VELOCITY" "MIDIFILE"
           "MIDIFILE-DIVISION" "MIDIFILE-FORMAT" "MIDIFILE-TRACKS"
           "MODE-MESSAGE" "MONO-MODE-ON-MESSAGE" "NOTE-OFF-MESSAGE"
           "NOTE-ON-MESSAGE" "OMNI-MODE-OFF-MESSAGE"
           "OMNI-MODE-ON-MESSAGE" "PITCH-BEND-MESSAGE"
           "POLY-MODE-ON-MESSAGE" "POLYPHONIC-KEY-PRESSURE-MESSAGE"
           "PROGRAM-CHANGE-MESSAGE" "PROGRAM-NAME-MESSAGE"
           "PROPRIETARY-EVENT" "READ-MIDI-FILE" "REAL-TIME-MESSAGE"
           "RESET-ALL-CONTROLLERS-MESSAGE" "SEQUENCE-NUMBER-MESSAGE"
           "SEQUENCE/TRACK-NAME-MESSAGE" "SMPTE-OFFSET-MESSAGE"
           "SONG-POSITION-POINTER-MESSAGE" "SONG-SELECT-MESSAGE"
           "START-SEQUENCE-MESSAGE" "STATUS" "STATUS-MIN"
           "STOP-SEQUENCE-MESSAGE" "SYSTEM-EXCLUSIVE-MESSAGE"
           "SYSTEM-MESSAGE" "TEMPO-MAP-MESSAGE" "TEMPO-MESSAGE"
           "TIME-SIGNATURE-MESSAGE" "TIMING-CLOCK-MESSAGE"
           "TIMING-CODE-MESSAGE" "TUNE-REQUEST-MESSAGE"
           "UNKNOWN-EVENT" "STRAY-DATA-BYTE-ERROR" "VOICE-MESSAGE"
           "WRITE-MIDI-FILE")
  (:export ;; extensions
   "ACTUAL-READ-NEXT-BYTE" "ACTUAL-UNREAD-BYTE" "ACTUAL-WRITE-BYTES"
   "READ-MIDI-MESSAGE" "WRITE-MIDI-MESSAGE"
   "MESSAGE-LENGTH"))

(in-package "MIDI")

(deftype octet () '(unsigned-byte 8))
(defun make-octet-vector (size) (make-array size :element-type 'octet))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; print-object utility

(declaim (declaration stepper))
(defvar *step-mode* :run)

(defun object-identity (object)
  "
RETURN:         A string containing the object identity as printed by
                PRINT-UNREADABLE-OBJECT.
"
  (declare (stepper disable))
  (let ((*step-mode* :run)
        (*print-readably* nil))
    (let ((ident
            (with-output-to-string (stream)
              (print-unreadable-object (object stream :type nil :identity t)))))
      (if (< 3 (length ident))
          (subseq ident 3 (1- (length ident)))
          ident))))


(defun call-print-parseable-object (object stream type identity thunk)
  "
SEE:            PRINT-PARSEABLE-OBJECT
"
  (declare (stepper disable))
  (let ((*step-mode* :run))
    (if *print-readably*
        (error 'print-not-readable :object object)
        (progn
          (format stream "~S"
                  (append (when type
                            (list (class-name (class-of object))))
                          (funcall thunk object)
                          (when identity
                            (list (object-identity object)))))
          object))))


(eval-when (:compile-toplevel :load-toplevel :execute)

  (defun extract-slots-form (ovar slots)
    "
SEE:            PRINT-PARSEABLE-OBJECT
RETURN:         A form building a plist of slot values.
"
    (cons 'list
          (loop
            :for slot :in slots
            :collect  (if (symbolp slot)
                          (intern (symbol-name slot) "KEYWORD")
                          `(quote ,(first slot)))
            :collect  (if (symbolp slot)
                          `(ignore-errors (if (slot-boundp ,ovar ',slot)
                                              (slot-value ,ovar ',slot)
                                              '#:<UNBOUND>))
                          `(ignore-errors ,(second slot))))))

  (defun extract-slots (object slots)
    "
SEE:            PRINT-PARSEABLE-OBJECT
RETURN:         A plist of slot values.
"
    (loop
      :for slot :in slots
      :collect  (if (symbolp slot)
                    (intern (symbol-name slot) "KEYWORD")
                    (first slot))
      :collect  (if (symbolp slot)
                    (ignore-errors (if (slot-boundp object slot)
                                       (slot-value object slot)
                                       '#:<UNBOUND>))
                    (second slot)))))


(defmacro print-parseable-object ((object stream &key (type t) identity) &rest slots)
  "

DO:             Prints on the STREAM the object as a list.  If all the
                objects printed inside it are printed readably or with
                PRINT-PARSEABLE-OBJECT, then that list should be
                readable, at least with *READ-SUPPRESS* set to T.

OBJECT:         Either a variable bound to the object to be printed,
                or a binding list (VARNAME OBJECT-EXPRESSION), in
                which case the VARNAME is bound to the
                OBJECT-EXPRESSION during the evaluation of the SLOTS.

STREAM:         The output stream where the object is printed to.

TYPE:           If true, the class-name of the OBJECT is printed as
                first element of the list.

IDENTITY:       If true, the object identity is printed as a string in
                the last position of the list.

SLOTS:          A list of either a symbol naming the slot, or a list
                (name expression), name being included quoted in the
                list, and the expression being evalauted to obtain the
                value.

RETURN:         The object that bas been printed (so that you can use
                it in tail position in PRINT-OBJECT conformingly).

"
  `(locally (declare (stepper disable))
     ,(if (symbolp object)
          `(call-print-parseable-object ,object ,stream ,type ,identity
                                        (lambda (,object)
                                          (declare (ignorable ,object) (stepper disable))
                                          ,(extract-slots-form object slots)))
          (destructuring-bind (ovar oval) object
            `(let ((,ovar ,oval))
               (call-print-parseable-object ,ovar ,stream ,type ,identity
                                            (lambda (,ovar)
                                              (declare (ignorable ,ovar) (stepper disable))
                                              ,(extract-slots-form ovar slots))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Midifile protocol

(defgeneric midifile-format (midifile))
(defgeneric (setf midifile-format) (format midifile))
(defgeneric midifile-division (midifile))
(defgeneric midifile-tracks (midifile))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Message protocol

(defgeneric message-time(message))
(defgeneric (setf message-time) (time message))
(defgeneric message-status (message))
(defgeneric message-channel (message))
(defgeneric message-key (message))
(defgeneric message-velocity (message))
(defgeneric message-tempo (message))
(defgeneric message-numerator (message))
(defgeneric message-denominator (message))
(defgeneric message-sf (message))
(defgeneric message-mi (message))
(defgeneric message-program (message))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; File support

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun string-code (s)
    "compute the ASCII-based numerical value of the string [warning:
works only if the chars are coded in ASCII]"
    (let ((v 0))
      (loop for i from 0 to (1- (length s))
            do (setf v (+ (* v 256) (char-code (aref s i)))))
      v)))

(defconstant +header-mthd+ #.(string-code "MThd"))
(defconstant +header-mtrk+ #.(string-code "MTrk"))
(defconstant +header-mthd-length+ 6 "value of the header MThd data's length")



(define-condition unknown-event (error)
  ((status :initarg :status :reader status)
   (data-byte :initform "" :initarg :data-byte :reader data-byte))
  (:documentation "condition when the event does not exist in the library"))

(define-condition stray-data-byte-error (unknown-event)
  ()
  (:documentation "condition when we read a data byte when a status byte was expected"))

(define-condition header (error)
  ((header-type :initarg :header :reader header-type))
  (:report (lambda (condition stream)
             (format stream "Invalid header type ~S" (header-type condition))))
  (:documentation "condition when the header is not correct"))



(defgeneric actual-read-next-byte   (source)
  (:documentation "Get a byte from the SOURCE.
RETURN: The byte read; the SOURCE (or a new source for next bytes)."))

(defgeneric actual-unread-next-byte (source byte)
  (:documentation "Unread a byte.
RETURN: the SOURCE (or a new source for next bytes)."))

(defgeneric actual-write-bytes      (destination bytes)
  (:documentation "Writes a sequence of BYTES to the destination.
RETURN: the DESTINATION (or a new destination for the following bytes)"))



(defmethod actual-read-next-byte   ((buffer vector))
  (values (vector-pop buffer)
          buffer))

(defmethod actual-unread-next-byte ((buffer vector) byte)
  (vector-push-extend byte buffer)
  buffer)

(defmethod actual-write-bytes      ((buffer vector) bytes)
  (map nil (lambda (byte) (vector-push-extend byte buffer)) bytes)
  buffer)


;; A cons cell is used to wrap lists (stored in the cdr):
(defmethod actual-read-next-byte   ((buffer cons))
  (values (pop (cdr buffer))
          ;; Cf.  (actual-unread-next-byte stream byte)
          (if (listp (cdr buffer))
              buffer
              (cdr buffer))))

(defmethod actual-unread-next-byte ((buffer cons) byte)
  (push byte (cdr buffer))
  buffer)

;; No write on a list (we would have to append to the end).



(defmethod actual-read-next-byte   ((stream stream))
  (values (read-byte stream)
          stream))

(defmethod actual-unread-byte      ((stream stream) byte)
  ;; No unread-byte in CL…
  (cons nil (cons byte stream)))

(defmethod actual-write-bytes      ((stream stream) bytes)
  (write-sequence bytes stream)
  stream)



(defparameter *midi-input*    nil
  "
May be:
- a stream for reading a Midifile,
- a cons cell whose cdr is a list of bytes (with possibly a tail of another class),
- a possibly adjustable vector with fill-pointer,
- or some other class of object provided an implementation of the
  actual-read-next-byte and actual-unread-byte methods.
")


(defparameter *midi-output*   nil
    "
May be:
- a stream for writing a Midifile,
- a cons cell whose cdr is a list of bytes (with possibly a tail of another class),
- a possibly adjustable vector with fill-pointer,
- or some other class of object provided an implementation of the
  actual-write-bytes method.
")


(declaim (inline read-next-byte unread-byte write-bytes))

(defun read-next-byte ()
  "read an unsigned 8-bit byte from *midi-input* checking for unread bytes"
  (let (byte)
    (multiple-value-setq (byte *midi-input*) (actual-read-next-byte *midi-input*))
    byte))

(defun unread-byte (byte)
  "unread a byte from *midi-input*"
  (setf *midi-input* (actual-unread-byte *midi-input* byte)))

(defun write-bytes (&rest bytes)
  "write an arbitrary number of bytes to *midi-output*"
  (setf *midi-output* (actual-write-bytes *midi-output* bytes)))



(defun read-fixed-length-quantity (nb-bytes)
  "read an unsigned integer of nb-bytes bytes from *midi-input*"
  (loop :with result := 0
        :for i :from 1 :to nb-bytes
        :do (setf result (logior (ash result 8) (read-next-byte)))
        :finally (return result)))

(defun write-fixed-length-quantity (quantity nb-bytes)
  "write an unsigned integer of nb-bytes bytes to *midi-output*"
  (unless (zerop nb-bytes)
    (write-fixed-length-quantity (ash quantity -8) (1- nb-bytes))
    (write-bytes (logand quantity #xff))))

(defmacro with-midi-input ((pathname &rest open-args &key &allow-other-keys) &body body)
  "execute body with *midi-input* assigned to a stream from pathname"
  `(with-open-file (*midi-input* ,pathname
                                 :direction :input :element-type 'octet
                                 ,@open-args)
     ,@body))

(defmacro with-midi-output ((pathname &rest open-args &key &allow-other-keys) &body body)
  "execute body with *midi-output* assigned to a stream from pathname"
  `(with-open-file (*midi-output* ,pathname
                                  :direction :output :element-type 'octet
                                  ,@open-args)
     ,@body))

(defun read-variable-length-quantity ()
  "read a MIDI variable length quantity from *midi-input*"
  (loop :with result = 0
        :with byte
        :do (setf byte (read-next-byte)
                  result (logior (ash result 7) (logand byte #x7f)))
        :until (< byte #x80)
        :finally (return result)))

(defun write-variable-length-quantity (quantity &optional (termination 0))
  (when (> quantity 127)
    (write-variable-length-quantity (ash quantity -7) #x80))
  (write-bytes (logior (logand (round quantity) #x7f) termination)))

(defun length-of-variables-length-quantity (quantity)
  (1+ (if (< quantity 128)
          0
          (length-of-variables-length-quantity (ash quantity -7)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; MIDI file representation

(defclass midifile ()
  ((format :initarg :format :reader midifile-format)
   (division :initarg :division :reader midifile-division)
   (tracks :initarg :tracks :reader midifile-tracks))
  (:documentation "the class that represents a Midifile in core"))

(defmethod print-object ((self midifile) stream)
  (print-parseable-object (self stream :type t :identity nil)
                          format division track))

(defvar *dispatch-table* (make-array 256 :initial-element nil)
  "given values of status (and perhaps data1), find a class to create")

(defvar *status*         nil "the status while reading an event")
(defvar *running-status* 144 "the running status while reading an event")


(defun read-message ()
  "read a message without time indication from *midi-input*"
  (let ((status-or-data (read-next-byte)))
    (if (>= status-or-data #x80)
        (progn (setf *status* status-or-data)
               (when (<= *status* #xef)
                 (setf *running-status* *status*)))
        (progn (unread-byte status-or-data)
               (setf *status* *running-status*)))
    (let ((message (let ((classname-or-subtype (aref *dispatch-table* *status*)))
                     (unless classname-or-subtype
                       (error (if (< *status* 128)
                                  'stray-data-byte-error
                                  'unknown-event) :status *status*))
                     (if (symbolp classname-or-subtype)
                         (make-instance classname-or-subtype)
                         (let* ((data-byte (read-next-byte))
                                (classname (aref classname-or-subtype data-byte)))
                           (unless classname
                             (error 'unknown-event
                                    :status *status*
                                    :data-byte data-byte))
                           (unread-byte data-byte)
                           (make-instance classname))))))
      (fill-message message)
      message)))

(defvar *time* 0 "accumulated time from the start of the track")

(defun read-timed-message ()
  "read a message preceded with a delta-time indication"
  (let ((delta-time (read-variable-length-quantity)))
    (let ((message (read-message)))
      (setf (message-time message) (incf *time* delta-time))
      message)))

(defun write-timed-message (message)
  "write a message preceded with a delta-time indication"
  (write-variable-length-quantity (- (message-time message) *time*))
  (setf *time* (message-time message))
  (write-message message))

(defun read-track ()
  "read a track as a list of timed messages, excluding the end-of-track message"
  (let ((type (read-fixed-length-quantity 4))
        (length (read-fixed-length-quantity 4)))
    (declare (ignore length))
    (unless (= type +header-mtrk+)
      (error (make-condition 'header :header "MTrk")))
    (loop with message = nil
          do (setf message (read-timed-message))
          until (typep message 'end-of-track-message)
          collect message)))

(defun write-track (track)
  "write a track (which does not contain the end-of-track message"
  (write-fixed-length-quantity  +header-mtrk+ 4)
  (let ((end-of-track-message (make-instance 'end-of-track-message)))
    ;; write the length of the track
    (write-fixed-length-quantity
     (+ (reduce #'+ track :key #'message-length)
        (message-length end-of-track-message)
        (loop with time = *time*
              for message in track
              sum (prog1 (length-of-variables-length-quantity
                          (- (message-time message) time))
                    (setf time (message-time message))))
        1) ; the delta time of the end-of-track message
     4)
    (dolist (message track)
      (write-timed-message message))
    (setf (message-time end-of-track-message) *time*)
    (write-timed-message end-of-track-message)))

(defun read-midi-file (filename)
  "read an entire Midifile from the file with name given as argument"
  (let ((*time* 0))
    (with-midi-input (filename)
      (let ((type (read-fixed-length-quantity 4))
            (length (read-fixed-length-quantity 4))
            (format (read-fixed-length-quantity 2))
            (nb-tracks (read-fixed-length-quantity 2))
            (division (read-fixed-length-quantity 2)))
        (unless (and (= length +header-mthd-length+) (= type +header-mthd+))
          (error 'header :header "MThd"))
        (make-instance 'midifile
                       :format format
                       :division division
                       :tracks (loop repeat nb-tracks
                                     do (when (= format 1) (setf *time* 0))
                                     collect (read-track)))))))

(defun write-midi-file (midifile filename)
  (let ((*time* 0))
    (with-midi-output (filename :if-exists :supersede)
      (write-fixed-length-quantity +header-mthd+ 4)
      (write-fixed-length-quantity +header-mthd-length+ 4)
      (with-slots (format division tracks) midifile
        (write-fixed-length-quantity format 2)
        (write-fixed-length-quantity (length tracks) 2)
        (write-fixed-length-quantity division 2)
        (setf *time* 0)
        (loop for track in tracks do
          (write-track track)
          (when (= (slot-value midifile 'format) 1)
            (setf *time* 0)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Conversion routines

(defun format1-tracks-to-format0-tracks (tracks)
  (list (reduce (lambda (t1 t2) (merge 'list t1 t2 #'< :key #'message-time))
                (copy-tree tracks))))

(defun format0-tracks-to-format1-tracks (tracks)
  (assert (null (cdr tracks)))
  (let (tempo-map track)
    (dolist (message (car tracks) (list (nreverse tempo-map) (nreverse track)))
      (if (typep message 'tempo-map-message)
          (push message tempo-map)
          (push message track)))))

(defun change-to-format-0 (midifile)
  (assert (= (midifile-format midifile) 1))
  (setf (slot-value midifile 'format) 0
        (slot-value midifile 'tracks) (format1-tracks-to-format0-tracks (midifile-tracks midifile))))

(defun change-to-format-1 (midifile)
  (assert (= (midifile-format midifile) 0))
  (setf (slot-value midifile 'format) 1
        (slot-value midifile 'tracks) (format0-tracks-to-format1-tracks (midifile-tracks midifile))))

(defmethod (setf midifile-format) (new-value midifile)
  (cond
    ((= (midifile-format midifile) new-value) new-value)
    ((and (= new-value 0) (= (midifile-format midifile) 1))
     (change-to-format-0 midifile)
     new-value)
    ((and (= new-value 1) (= (midifile-format midifile) 0))
     (change-to-format-1 midifile)
     new-value)
    (t (error "Unsupported conversion from format ~S to format ~S"
              (midifile-format midifile) new-value))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Macro for defining midi messages

(defvar *status-min* (make-hash-table :test #'eq)
  "given a class name, find the minimum status value for the type of message")
(defvar *status-max* (make-hash-table :test #'eq)
  "given a class name, find the maximum status value for the type of message")
(defvar *data-min* (make-hash-table :test #'eq)
  "given a class name, find the minimum data1 value for the type of message")
(defvar *data-max* (make-hash-table :test #'eq)
  "given a class name, find the maximum data1 value for the type of message")

(defun register-class (class superclass status-min status-max data-min data-max)
  (unless status-min
    (setf status-min (gethash superclass *status-min*)))
  (unless status-max
    (setf status-max (gethash superclass *status-max*)))
  (unless data-min
    (setf data-min (gethash superclass *data-min*)))
  (unless data-max
    (setf data-max (gethash superclass *data-max*)))
  ;; set status values for this class
  (setf (gethash class *status-min*) status-min)
  (setf (gethash class *status-max*) status-max)
  (setf (gethash class *data-min*) data-min)
  (setf (gethash class *data-max*) data-max)
  ;; update the dispatch table
  (when status-min
    (if data-min
        (progn (unless (arrayp (aref *dispatch-table* status-min))
                 (let ((secondary-dispatch (make-array 256 :initial-element nil)))
                   (loop :for i :from status-min :to status-max
                         :do (setf (aref *dispatch-table* i) secondary-dispatch))))
               (loop :for i :from data-min :to data-max
                     :do (setf (aref (aref *dispatch-table* status-min) i) class)))
        (loop :for i :from status-min :to status-max
              :do (setf (aref *dispatch-table* i) class)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; main filler, length, and writer methods

(defgeneric fill-message (message))
(defgeneric write-message (message))
(defgeneric message-length (message)
  (:method-combination +))

(defmethod fill-message (message)
  (declare (ignore message))
  nil)

(defmethod message-length + (message)
  (declare (ignore message))
  0)

(defmethod write-message (message)
  (declare (ignore message))
  nil)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defvar *slots* (make-hash-table) "Maps classes to superclass and direct slots.")
  (defun all-slots (classname)
    (destructuring-bind (&optional superclass slots) (gethash classname *slots*)
      (if superclass
          (nconc (all-slots superclass) (copy-list slots))
          (copy-list slots)))))

(defmacro define-midi-message (name superclasses
                               &key slots filler (length 0) writer
                                 status-min status-max data-min data-max)
  (let ((slot-names (mapcar (lambda (x) (if (symbolp x) x (first x))) slots)))
    `(progn

       (defclass ,name ,superclasses
         ((status-min :initform ,status-min :allocation :class)
          (status-max :initform ,status-max :allocation :class)
          (data-min :initform ,data-min :allocation :class)
          (data-max :initform ,data-max :allocation :class)
          ,@slots))

       (eval-when (:compile-toplevel :load-toplevel :execute)
         (setf (gethash ',name *slots*) (list ',(car superclasses) ',slot-names)))

       (defmethod print-object ((self ,name) stream)
         (call-print-parseable-object self stream t nil
                                      (lambda (object)
                                        (declare (ignorable object) (stepper disable))
                                        (extract-slots object (all-slots ',name)))))

       (defmethod fill-message :after ((message ,name))
         (with-slots ,slot-names message
           (symbol-macrolet ((next-byte (read-next-byte)))
             ,filler)))

       (defmethod message-length + ((message ,name))
         (with-slots (status-min status-max data-min data-max ,@slot-names)
             message
           ,length))

       (defmethod write-message :after ((message ,name))
         (with-slots (status-min status-max data-min data-max ,@slot-names)
             message
           ,writer))

       (register-class ',name ',(car superclasses)
                       ,status-min ,status-max ,data-min ,data-max)

       ',name)))

(defun status-min (class-name)
  (gethash class-name *status-min*))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; midi messages

(define-midi-message message ()
  :slots ((time :initarg :time :accessor message-time)
          (status :initarg :status :reader message-status))
  :length 1
  :filler (setf status *status*)
  :writer (write-bytes status))

(define-midi-message channel-message (message)
  :slots ((channel :initarg :channel :reader message-channel))
  :filler (setf channel (logand *status* #x0f)))

(defmethod initialize-instance :after ((message channel-message) &key &allow-other-keys)
  (cond
    ((slot-boundp message 'channel)
     (setf (slot-value message 'status)
           (+ (slot-value message 'status-min)
              (slot-value message 'channel))))
    ((and (not (slot-boundp message 'channel))
          (slot-boundp message 'status))
     (setf (slot-value message 'channel)
           (logand #x0f (slot-value message 'status))))))

(defmethod (setf message-channel) (new-channel (message channel-message))
  (check-type new-channel (integer 0 15))
  (setf (slot-value message 'status) (+ (slot-value message 'status-min)
                                        new-channel)
        (slot-value message 'channel) new-channel))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; voice messages

(define-midi-message voice-message (channel-message))

(define-midi-message note-off-message (voice-message)
  :status-min #x80 :status-max #x8f
  :slots ((key :initarg :key :reader message-key)
          (velocity :initarg :velocity :reader message-velocity))
  :filler (setf key next-byte
                velocity next-byte)
  :length 2
  :writer (write-bytes key velocity))

(define-midi-message note-on-message (voice-message)
  :status-min #x90 :status-max #x9f
  :slots ((key :initarg :key :reader message-key)
          (velocity :initarg :velocity :reader message-velocity))
  :filler (setf key next-byte
                velocity next-byte)
  :length 2
  :writer (write-bytes key velocity))

(define-midi-message polyphonic-key-pressure-message (voice-message)
  :status-min #xa0 :status-max #xaf
  :slots ((key :initarg :key :reader message-key)
          (pressure :initarg :pressure :reader message-pressure))
  :filler (setf key next-byte
                pressure next-byte)
  :length 2
  :writer (write-bytes key pressure))

(define-midi-message control-change-message (voice-message)
  :status-min #xb0 :status-max #xbf
  :data-min #x00 :data-max #x78
  :slots ((controller :initarg :controller :reader message-controller)
          (value :initarg :value :reader message-value))
  :filler (setf controller next-byte
                value next-byte)
  :length 2
  :writer (write-bytes controller value))

(define-midi-message program-change-message (voice-message)
  :status-min #xc0 :status-max #xcf
  :slots ((program :initarg :program :reader message-program))
  :filler (setf program next-byte)
  :length 1
  :writer (write-bytes program))

(define-midi-message channel-pressure-message (voice-message)
  :status-min #xd0 :status-max #xdf
  :slots ((pressure :initarg :pressure :reader message-pressure))
  :filler (setf pressure next-byte)
  :length 1
  :writer (write-bytes pressure))

(define-midi-message pitch-bend-message (voice-message)
  :status-min #xe0 :status-max #xef
  :slots ((value :initarg :value :reader message-value))
  :filler (setf value (logior next-byte (ash next-byte 7)))
  :length 2
  :writer (write-bytes (logand value #x7f) (logand (ash value -7) #x7f)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; mode messages

(define-midi-message mode-message (channel-message)
  :filler next-byte) ; consume data byte

(define-midi-message reset-all-controllers-message (mode-message)
  :status-min #xb0 :status-max #xbf
  :data-min #x79 :data-max #x79
  :filler next-byte ; consume unused byte
  :length 2
  :writer (write-bytes #x79 0))

(define-midi-message local-control-message (mode-message)
  :status-min #xb0 :status-max #xbf
  :data-min #x7a :data-max #x7a
  :slots ((mode))
  :filler (setf mode (if (= next-byte 0) :off :on))
  :length 2
  :writer (write-bytes #x7a (if (eq mode :off) 0 127)))

(define-midi-message all-notes-off-message (mode-message)
  :status-min #xb0 :status-max #xbf
  :data-min #x7b :data-max #x7b
  :filler next-byte ; consume unused byte
  :length 2
  :writer (write-bytes #x7b 0))

(define-midi-message omni-mode-off-message (mode-message)
  :status-min #xb0 :status-max #xbf
  :data-min #x7c :data-max #x7c
  :filler next-byte ; consume unused byte
  :length 2
  :writer (write-bytes #x7c 0))

(define-midi-message omni-mode-on-message (mode-message)
  :status-min #xb0 :status-max #xbf
  :data-min #x7d :data-max #x7d
  :filler next-byte ; consume unused byte
  :length 2
  :writer (write-bytes #x7d 0))

(define-midi-message mono-mode-on-message (mode-message)
  :status-min #xb0 :status-max #xbf
  :data-min #x7e :data-max #x7e
  :slots ((nb-channels))
  :filler (setf nb-channels next-byte)
  :length 2
  :writer (write-bytes #x7e nb-channels))

(define-midi-message poly-mode-on-message (mode-message)
  :status-min #xb0 :status-max #xbf
  :data-min #x7f :data-max #x7f
  :filler next-byte ; consume unused byte
  :length 2
  :writer (write-bytes #x7f 0))

(define-midi-message system-message (message))

(define-midi-message tempo-map-message (message))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; system common messages

(define-midi-message common-message (system-message))

(define-midi-message timing-code-message (common-message)
  :status-min #xf1 :status-max #xf1
  :slots ((code))
  :filler (setf code next-byte)
  :length 1
  :writer (write-bytes code))

(define-midi-message song-position-pointer-message (common-message)
  :status-min #xf2 :status-max #xf2
  :slots ((pointer))
  :filler (setf pointer (logior next-byte (ash next-byte 7)))
  :length 2
  :writer (write-bytes (logand pointer #x7f) (logand (ash pointer -7) #x7f)))

(define-midi-message song-select-message (common-message)
  :status-min #xf3 :status-max #xf3
  :slots ((song))
  :filler (setf song next-byte)
  :length 1
  :writer (write-bytes song))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; system real-time messages

(define-midi-message real-time-message (system-message))

(define-midi-message tune-request-message (real-time-message)
  :status-min #xf6 :status-max #xf6)

(define-midi-message timing-clock-message (real-time-message)
  :status-min #xf8 :status-max #xf8)

(define-midi-message start-sequence-message (real-time-message)
  :status-min #xfa :status-max #xfa)

(define-midi-message continue-sequence-message (real-time-message)
  :status-min #xfb :status-max #xfb)

(define-midi-message stop-sequence-message (real-time-message)
  :status-min #xfc :status-max #xfc)

(define-midi-message active-sensing-message (real-time-message)
  :status-min #xfe :status-max #xfe)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; system exclusive messages

(define-midi-message system-exclusive-message (system-message)
  :status-min #xf0 :status-max #xf0
  :slots ((data :initarg :data :reader message-data))
  :filler (loop :with len := (read-variable-length-quantity)
                  :initially (setf data (make-octet-vector len))
                :for i :from 0 :below len
                :do (setf (aref data i) next-byte))
  :length (+ (length-of-variables-length-quantity (length data))
             (length data))
  :writer (progn (write-variable-length-quantity (length data))
                 (loop for elem across data do (write-bytes elem))))

(define-midi-message authorization-system-exclusive-message (system-message)
  :status-min #xf7 :status-max #xf7
  :slots ((data :initarg :data :reader message-data))
  :filler (loop :with len := (read-variable-length-quantity)
                  :initially (setf data (make-octet-vector len))
                :for i :from 0 :below len
                :do (setf (aref data i) next-byte))
  :length (+ (length-of-variables-length-quantity (length data))
             (length data))
  :writer (progn (write-variable-length-quantity (length data))
                 (loop :for elem :across data :do (write-bytes elem))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; meta messages

(define-midi-message meta-message (message)
  :status-min #xff :status-max #xff
  :length 2 ; the first data byte and the length byte
  :filler next-byte ; the first data byte which gives the type of meta message
  :writer (write-bytes data-min))

(define-midi-message sequence-number-message (meta-message tempo-map-message)
  :data-min #x00 :data-max #x00
  :slots ((sequence :initarg :sequence :reader message-sequence))
  :filler (let ((data2 next-byte))
            (setf sequence (if (zerop data2)
                               0
                               (logior (ash next-byte 8) next-byte))))
  :length (if (zerop sequence) 0 2)
  :writer (unless (zerop sequence)
            (write-bytes (ash sequence -8) (logand sequence #xf))))

(define-midi-message text-message (meta-message)
  :slots ((text :initarg :text :reader message-text))
  :filler (setf text (loop with len = next-byte
                           with str = (make-string len)
                           for i from 0 below len
                           do (setf (aref str i)
                                    (code-char next-byte))
                           finally (return str)))
  :length (length text)
  :writer (progn (write-bytes (length text))
                 (loop for char across text do
                   (write-bytes (char-code char)))))


(define-midi-message general-text-message (text-message)
  :data-min #x01 :data-max #x01)

(define-midi-message copyright-message (text-message)
  :data-min #x02 :data-max #x02)

(define-midi-message sequence/track-name-message (text-message tempo-map-message)
  :data-min #x03 :data-max #x03)

(define-midi-message instrument-message (text-message)
  :data-min #x04 :data-max #x04)

(define-midi-message lyric-message (text-message)
  :data-min #x05 :data-max #x05)

(define-midi-message marker-message (text-message tempo-map-message)
  :data-min #x06 :data-max #x06)

(define-midi-message cue-point-message (text-message)
  :data-min #x07 :data-max #x07)

(define-midi-message program-name-message (text-message)
  :data-min #x08 :data-max #x08)

(define-midi-message device-name-message (text-message)
  :data-min #x09 :data-max #x09)

(define-midi-message channel-prefix-message (meta-message)
  :data-min #x20 :data-max #x20
  :slots ((channel :initarg :channel :reader message-channel))
  :length 1
  :filler (progn next-byte (setf channel next-byte))
  :writer (write-bytes 1 channel))

(define-midi-message midi-port-message (meta-message)
  :data-min #x21 :data-max #x21
  :slots ((port :initarg :port :reader message-port))
  :length 1
  :filler (progn next-byte (setf port next-byte))
  :writer (write-bytes 1 port))

(define-midi-message end-of-track-message (meta-message)
  :data-min #x2f :data-max #x2f
  :slots ((status :initform #xff))
  :filler next-byte
  :length 0
  :writer (write-bytes 0))

(define-midi-message tempo-message (meta-message tempo-map-message)
  :data-min #x51 :data-max #x51
  :slots ((tempo :initarg :tempo :reader message-tempo))
  :filler (progn next-byte (setf tempo (read-fixed-length-quantity 3)))
  :length 3
  :writer (progn (write-bytes 3) (write-fixed-length-quantity tempo 3)))

(define-midi-message smpte-offset-message (meta-message tempo-map-message)
  :data-min #x54 :data-max #x54
  :slots ((hr :initarg :hr :reader message-hr)
          (mn :initarg :mn :reader message-mn)
          (se :initarg :se :reader message-se)
          (fr :initarg :fr :reader message-fr)
          (ff :initarg :ff :reader message-ff))
  :filler (progn next-byte (setf hr next-byte mn next-byte se next-byte
                                 fr next-byte ff next-byte))
  :length 5
  :writer (write-bytes 5 hr mn se fr ff))

(define-midi-message time-signature-message (meta-message tempo-map-message)
  :data-min #x58 :data-max #x58
  :slots ((nn :reader message-numerator)
          (dd :reader message-denominator)
          (cc) (bb))
  :filler (progn next-byte (setf nn next-byte dd next-byte
                                 cc next-byte bb next-byte))
  :length 4
  :writer (write-bytes 4 nn dd cc bb))

(define-midi-message key-signature-message (meta-message)
  :data-min #x59 :data-max #x59
  :slots ((sf :initarg :sf :reader message-sf)
          (mi :initarg :mi :reader message-mi))
  :filler (progn next-byte (setf sf (let ((temp-sf next-byte))
                                      (if (> temp-sf 127)
                                          (- temp-sf 256)
                                          temp-sf))
                                 mi next-byte))
  :length 2
  :writer (write-bytes 2 (if (< sf 0) (+ sf 256) sf) mi))

(define-midi-message proprietary-event (meta-message)
  :data-min #x7f :data-max #x7f
  :slots ((data :initarg :data :reader message-data))
  :filler (setf data (loop :with len := (read-variable-length-quantity)
                           :with vec := (make-octet-vector len)
                           :for i :from 0 :below len
                           :do (setf (aref vec i) next-byte)
                           :finally (return vec)))
  :writer (map nil (lambda (byte) (write-bytes byte))
            data))                      ; FIXME



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;

(defgeneric read-midi-message (source)
  (:documentation "Reads a midi MESSAGE from the SOURCE.
RETURN: the MESSAGE read.")
  (:method (source)
    (let ((*midi-input* source)
          (*status*     nil))
      (read-message))))


(defgeneric write-midi-message (destination message)
  (:documentation "Writes a midi MESSAGE to the DESTINATION.
RETURN: the MESSAGE written.")
  (:method (destination (message message))
    (let ((*midi-output* destination))
      (write-message message)
      destination)))


;;;; THE END ;;;;
