;;; ============================================================
;;; FIX-TEXT-OVERLAP.LSP  (v3 – verified spacing)
;;;
;;; Center-Middle origin = geometric centre of text box
;;;   top  edge = originY + H/2
;;;   bot  edge = originY - H/2
;;;
;;; For two texts A (lower) and B (upper):
;;;   gap between edges = B_bottom - A_top
;;;                     = (B_centerY - H/2) - (A_centerY + H/2)
;;;                     = B_centerY - A_centerY - H
;;;
;;; We want that gap = 0.5 * H  →
;;;   B_centerY - A_centerY = H + 0.5*H = 1.5*H   ← c2c
;;;
;;; BUT: we only push B up if it is ALREADY overlapping A.
;;;      i.e. only when  (B_centerY - A_centerY) < 1.5*H
;;; ============================================================

(defun c:FIXTXT ( / ss i ent ed lst sorted
                            maxH c2cMin
                            prevCY curCY needCY dy
                            ip newip h72 h73)

  ;; ── 1. selection ────────────────────────────────────────────
  (princ "\nSelect TEXT objects: ")
  (setq ss (ssget '((0 . "TEXT,MTEXT"))))
  (if (null ss) (progn (princ "\nNothing selected.") (exit)))
  (princ (strcat "\n" (itoa (sslength ss)) " object(s) selected."))

  ;; ── 2. find max height ──────────────────────────────────────
  (setq maxH 0.0  i 0)
  (while (< i (sslength ss))
    (setq h (cdr (assoc 40 (entget (ssname ss i)))))
    (if (and h (> h maxH)) (setq maxH h))
    (setq i (1+ i))
  )
  (if (= maxH 0.0) (setq maxH 2.5))
  (princ (strcat "\nUniform height: " (rtos maxH 2 4)))

  ;; c2c = H + 0.5H = 1.5H  (gives exactly 0.5H gap between edges)
  (setq c2cMin (* maxH 1.5))
  (princ (strcat "  |  c2c min: " (rtos c2cMin 2 4)
                 "  |  edge gap: " (rtos (* maxH 0.5) 2 4)))

  ;; ── 3. apply height + Center/Middle, collect centre Y ───────
  (setq lst '()  i 0)
  (while (< i (sslength ss))
    (setq ent (ssname ss i)
          ed  (entget ent))

    (if (= (cdr (assoc 0 ed)) "TEXT")
      (progn
        ;; grab current visual centre:
        ;; if already centre/middle, code-11 holds it; else code-10
        (setq h72 (cdr (assoc 72 ed))
              h73 (cdr (assoc 73 ed)))
        (setq ip
          (if (and h72 h73 (= h72 4) (= h73 2))
            ;; already centre/middle – use code-11
            (cond ((cdr (assoc 11 ed))) ((cdr (assoc 10 ed))))
            ;; not centre/middle yet – use code-10 (raw insertion)
            (cdr (assoc 10 ed))
          )
        )

        ;; set height
        (setq ed (subst (cons 40 maxH) (assoc 40 ed) ed))

        ;; horizontal = 4 (Centre)
        (if (assoc 72 ed)
          (setq ed (subst (cons 72 4) (assoc 72 ed) ed))
          (setq ed (append ed (list (cons 72 4))))
        )
        ;; vertical = 2 (Middle)
        (if (assoc 73 ed)
          (setq ed (subst (cons 73 2) (assoc 73 ed) ed))
          (setq ed (append ed (list (cons 73 2))))
        )
        ;; both code-10 and code-11 = same centre point
        (setq ed (subst (cons 10 ip) (assoc 10 ed) ed))
        (if (assoc 11 ed)
          (setq ed (subst (cons 11 ip) (assoc 11 ed) ed))
          (setq ed (append ed (list (cons 11 ip))))
        )
      )
      (progn
        ;; MTEXT: height only
        (setq ed   (subst (cons 40 maxH) (assoc 40 ed) ed))
        (setq ip   (cdr (assoc 10 ed)))
      )
    )

    (entmod ed)
    (entupd ent)

    ;; store (centerY  ip  ent)
    (setq lst (cons (list (cadr ip) ip ent) lst))
    (setq i (1+ i))
  )

  ;; ── 4. sort ascending by Y ──────────────────────────────────
  (setq sorted
    (vl-sort lst (function (lambda (a b) (< (car a) (car b)))))
  )

  ;; ── 5. fix overlaps – only move when ACTUALLY overlapping ───
  (setq prevCY nil)

  (foreach item sorted
    (setq curCY (car   item)
          ip    (cadr  item)
          ent   (caddr item))

    (if prevCY
      (progn
        (setq needCY (+ prevCY c2cMin))

        ;; ONLY adjust if the texts are too close / overlapping
        (if (< curCY needCY)
          (progn
            (setq dy    (- needCY curCY)
                  ed    (entget ent)
                  newip (list (car ip)
                              (+ (cadr ip) dy)
                              (caddr ip)))
            (setq ed (subst (cons 10 newip) (assoc 10 ed) ed))
            (if (assoc 11 ed)
              (setq ed (subst (cons 11 newip) (assoc 11 ed) ed))
            )
            (entmod ed)
            (entupd ent)
            (setq curCY needCY)
            (setq ip    newip)
          )
        )
      )
    )
    (setq prevCY curCY)
  )

  (princ (strcat
    "\nDone.  height=" (rtos maxH 2 4)
    "  edge-gap=" (rtos (* maxH 0.5) 2 4)
    "  (= 0.5 x height between text edges)"))
  (princ)
)