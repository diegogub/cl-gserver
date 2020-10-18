(defpackage :cl-gserver.gserver-mp-test
  (:use :cl :trivia :iterate :fiveam :cl-gserver.gserver)
  (:import-from #:system-api
                #:shutdown)
  (:import-from #:ac
                #:actor-of)
  (:export #:run!
           #:all-tests
           #:nil))

(in-package :cl-gserver.gserver-mp-test)

(def-suite gserver-mp-tests
  :description "gserver mp tests"
  :in cl-gserver.tests:test-suite)

(in-suite gserver-mp-tests)

(log:config :warn)

(def-fixture mp-setup (queue-size)
  (setf lparallel:*kernel* (lparallel:make-kernel 8))

  (defclass counter-server (gserver) ())
  (defmethod handle-cast ((server counter-server) message current-state)
    (declare (ignore message))
    (cons current-state current-state))
  (defmethod handle-call ((server counter-server) message current-state)
    (match message
      (:add
       (let ((new-state (1+ current-state)))
         (cons new-state new-state)))
      (:sub
       (let ((new-state (1- current-state)))
         (cons new-state new-state)))
      (:get (cons current-state current-state))))

  (format t "Running non-system tests...~%")
  (let* ((cut (make-instance 'counter-server :state 0 :max-queue-size queue-size))
         (max-loop 10000)
         (per-thread (/ max-loop 8)))
    (&body)
    (call cut :stop))
  (format t "Running non-system tests...done~%")
  (format t "Running system tests...~%")
  (let* ((system (system:make-system :num-workers 4))
         (cut (actor-of system (lambda ()
                                 (make-instance 'counter-server :state 0
                                                                :max-queue-size queue-size))))
         (max-loop 10000)
         (per-thread (/ max-loop 8)))
    (unwind-protect
         (&body)
    (call cut :stop)
    (shutdown system)))
  (format t "Running system tests...~%")
  
  (lparallel:end-kernel))


(test counter-mp-unbounded
  "Counter server - multi processors - unbounded queue"

  (with-fixture mp-setup (nil)
    ;; add
    (map nil #'lparallel:force
         (mapcar (lambda (x)
                   (declare (ignore x))
                   (lparallel:future
                     (dotimes (n (1+ per-thread))
                       (call cut :add))
                     (dotimes (n per-thread)
                       (call cut :sub))))
                 (loop repeat 8 collect "n")))
    (is (= 8 (call cut :get)))))

(test counter-mp-bounded
  "Counter server - multi processors - bounded queue"

  (with-fixture mp-setup (100)
    ;; add
    (map nil #'lparallel:force
         (mapcar (lambda (x)
                   (declare (ignore x))
                   (lparallel:future
                     (dotimes (n (1+ per-thread))
                       (call cut :add))
                     (dotimes (n per-thread)
                       (call cut :sub))))
                 (loop repeat 8 collect "n")))
    (is (= 8 (call cut :get)))))

(defun run-tests ()
  (time (run! 'counter-mp-unbounded))
  (time (run! 'counter-mp-bounded)))
