; ============================================================================
; Text Increment Utility v1.0.0
; Developer: Holgundi Consulting Works
; Date: September 2025
; Description: AutoCAD LISP utility for copying and incrementing text objects
; Command: TextIncrement
; ============================================================================

;; Helper: find the last contiguous run of digits in a string
(defun hcw:last-num-span (s / i start end)
  (setq i (strlen s))
  ;; move left to the last digit
  (while (and (> i 0) (not (wcmatch (substr s i 1) "[0-9]")))
    (setq i (1- i))
  )
  (if (= i 0)
    nil
    (progn
      (setq end i)
      ;; move left until a non-digit
      (while (and (> i 0) (wcmatch (substr s i 1) "[0-9]"))
        (setq i (1- i))
      )
      (setq start (1+ i))
      (list start (1+ (- end start))) ; (start len)
    )
  )
)

(defun c:TextIncrement ( / ent entData txt base num prefix suffix pt newtxt span start len numstr newnumstr)
  (setq ent (car (entsel "\nSelect TEXT to copy and increment: ")))
  (if (and ent (= (cdr (assoc 0 (entget ent))) "TEXT"))
    (progn
      (setq entData (entget ent))
      (setq txt (cdr (assoc 1 entData)))

      ;; Find the last numeric run and preserve its width (handles leading zeros like 01)
      (setq span (hcw:last-num-span txt))
      (if span
        (progn
          (setq start  (car span))
          (setq len    (cadr span))
          (setq numstr (substr txt start len))
          (setq num    (atoi numstr))
          (setq prefix (substr txt 1 (- start 1)))
          (setq suffix (substr txt (+ start len)))

          ;; Start placing copies
          (while (setq pt (getpoint "\nClick to place incremented copy (Enter to finish): "))
            (setq num (1+ num))
            (setq newnumstr (itoa num))
            ;; zero-pad to original width
            (while (< (strlen newnumstr) len)
              (setq newnumstr (strcat "0" newnumstr))
            )
            (setq newtxt (strcat prefix newnumstr suffix))

            ;; Create new TEXT object with Middle Center justification
            (entmakex
              (list
                (cons 0 "TEXT")
                (cons 10 pt)                         ; insertion point (also set 11)
                (cons 11 pt)                         ; alignment point
                (cons 72 1)                          ; horizontal: Center
                (cons 73 2)                          ; vertical: Middle
                (cons 40 (cdr (assoc 40 entData)))   ; text height
                (cons 50 (cond ((assoc 50 entData) (cdr (assoc 50 entData))) (0.0))) ; rotation
                (cons 1 newtxt)
                (cons 7 (cdr (assoc 7 entData)))     ; text style
                (cons 8 (cdr (assoc 8 entData)))     ; layer
              )
            )
          )
        )
        (prompt "\nNo number found in selected text.")
      )
    )
    (prompt "\nYou didn't select a valid TEXT object.")
  )
  (princ)
)
