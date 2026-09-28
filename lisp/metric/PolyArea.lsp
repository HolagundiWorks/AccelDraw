;;; ============================================================
;;; POLYLINE AREA NUMBERING & TABLE GENERATOR  v1.5
;;; Changes from v1.4:
;;;   - Fixed (exit) calls → safe if/cond early-out structure
;;;   - Fixed text-height default: saved before getdist prompt
;;;   - Fixed getstring for prefix → T flag allows spaces
;;;   - Fixed ent-center → uses .Centroid with bbox fallback
;;;   - Fixed flag70 guard → safe if assoc 70 is missing
;;;   - Fixed total-area accumulation → single conversion path
;;;   - Fixed col-w → computed from longest label, not fixed multiple
;;;   - Added undo grouping (UNDO Begin / End)
;;;   - Added ensure-layer → thaws/unlocks AREA_TABLE if it exists
;;;   - Fixed sslength called once per loop → captured as (n)
;;;   - Improved unit-choice validation with re-prompt loop
;;; ============================================================

(defun C:POLYAREA ( / ss i n ent entdata area-list total-area
                     tbl-pt txt-h col-w row-h hdr-h
                     closed-count area pt
                     x0 y0 x1 x2 x3 ytop ybot
                     running-sum idx item flag70
                     insunits draw-unit-name answer
                     unit-label conv-factor converted-area
                     converted-total
                     prefix lbl active-layer
                     txt-h-default max-lbl-len)

  (vl-load-com)

  ;; ══════════════════════════════════════════════════════════
  ;; HELPERS
  ;; ══════════════════════════════════════════════════════════

  ;; Create layer if absent; thaw and unlock if it already exists
  (defun ensure-layer (lname lcolor / lo layers doc)
    (if (not (tblsearch "LAYER" lname))
      (entmakex (list '(0 . "LAYER")
                      '(100 . "AcDbSymbolTableRecord")
                      '(100 . "AcDbLayerTableRecord")
                      (cons 2 lname)
                      '(70 . 0)
                      (cons 62 lcolor)
                      '(6 . "Continuous")))
      ;; Layer exists – make sure it is usable
      (progn
        (setq doc    (vla-get-activedocument (vlax-get-acad-object))
              layers (vla-get-layers doc)
              lo     (vla-item layers lname))
        (vla-put-freeze lo :vlax-false)
        (vla-put-lock   lo :vlax-false))))

  ;; Centre point: prefer .Centroid (accurate); fall back to bbox midpoint
  ;; .Centroid is safe here because all polys are closed before this runs
  (defun ent-center (ename / obj cen mn mx)
    (setq obj (vlax-ename->vla-object ename))
    (setq cen (vl-catch-all-apply
                'vlax-get-property (list obj 'Centroid)))
    (if (vl-catch-all-error-p cen)
      (progn
        (vla-getboundingbox obj 'mn 'mx)
        (setq mn (vlax-safearray->list mn)
              mx (vlax-safearray->list mx))
        (list (/ (+ (car mn)  (car mx))  2.0)
              (/ (+ (cadr mn) (cadr mx)) 2.0)
              0.0))
      (list (car cen) (cadr cen) 0.0)))

  (defun draw-rect (rx1 ry1 rx2 ry2 lyr)
    (entmakex (list
      '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
      (cons 8 lyr) '(62 . 256)
      '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1)
      (cons 10 (list rx1 ry1)) (cons 10 (list rx2 ry1))
      (cons 10 (list rx2 ry2)) (cons 10 (list rx1 ry2)))))

  ;; col = ACI colour; 256 = ByLayer
  (defun place-text (txt cx cy ht lyr col)
    (entmakex (list
      '(0 . "TEXT") '(100 . "AcDbEntity")
      (cons 8 lyr) (cons 62 col)
      '(100 . "AcDbText")
      (cons 10 (list cx cy 0.0))
      (cons 40 ht) (cons 1 txt)
      '(72 . 1)
      (cons 11 (list cx cy 0.0))
      '(73 . 2))))

  ;; ══════════════════════════════════════════════════════════
  ;; STEP 1 – DRAWING UNITS
  ;; ══════════════════════════════════════════════════════════
  (setq insunits (getvar "INSUNITS"))
  (cond
    ((= insunits 1) (setq draw-unit-name "Inches"))
    ((= insunits 2) (setq draw-unit-name "Feet"))
    ((= insunits 4) (setq draw-unit-name "Millimetres"))
    ((= insunits 5) (setq draw-unit-name "Centimetres"))
    ((= insunits 6) (setq draw-unit-name "Metres"))
    ((= insunits 7) (setq draw-unit-name "Kilometres"))
    (T              (setq draw-unit-name "Unitless/Unknown")))
  (princ (strcat "\nDrawing units detected: " draw-unit-name
                 " (INSUNITS=" (itoa insunits) ")"))

  ;; ══════════════════════════════════════════════════════════
  ;; STEP 2 – OUTPUT UNIT  (re-prompts on bad input)
  ;; ══════════════════════════════════════════════════════════
  (princ "\nOutput area units:")
  (princ "\n  1 = Square Metres  (sq m)")
  (princ "\n  2 = Square Feet    (sq ft)")
  (setq answer nil)
  (while (not (or (= answer 1) (= answer 2)))
    (setq answer (getint "\nEnter choice [1/2] <1>: "))
    (if (null answer) (setq answer 1))
    (if (not (or (= answer 1) (= answer 2)))
      (princ "\nInvalid choice – please enter 1 or 2.")))

  (cond
    ((= answer 1)
     (setq unit-label "sq m")
     (cond
       ((= insunits 1) (setq conv-factor (* 0.0254 0.0254)))
       ((= insunits 2) (setq conv-factor (* 0.3048 0.3048)))
       ((= insunits 4) (setq conv-factor 1.0e-6))
       ((= insunits 5) (setq conv-factor 1.0e-4))
       ((= insunits 6) (setq conv-factor 1.0))
       ((= insunits 7) (setq conv-factor 1.0e6))
       (T              (setq conv-factor 1.0))))
    ((= answer 2)
     (setq unit-label "sq ft")
     (cond
       ((= insunits 1) (setq conv-factor (/ 1.0 144.0)))
       ((= insunits 2) (setq conv-factor 1.0))
       ((= insunits 4) (setq conv-factor 1.07639e-5))
       ((= insunits 5) (setq conv-factor 1.07639e-3))
       ((= insunits 6) (setq conv-factor 10.7639))
       ((= insunits 7) (setq conv-factor 1.07639e7))
       (T              (setq conv-factor 1.0)))))

  (princ (strcat "\nAreas will be reported in: " unit-label))

  ;; ══════════════════════════════════════════════════════════
  ;; STEP 3 – PREFIX  (T flag → allows spaces in the string)
  ;; ══════════════════════════════════════════════════════════
  (princ "\nEnter a prefix for polyline numbers (e.g. ROOM- or UNIT A-).")
  (setq prefix (getstring T "\nPrefix <none>: "))
  (if (null prefix) (setq prefix ""))
  (if (= prefix "")
    (princ "\nNo prefix – labels will be: 1, 2, 3 ...")
    (princ (strcat "\nPrefix set – labels will be: "
                   prefix "1, " prefix "2, " prefix "3 ...")))

  ;; ══════════════════════════════════════════════════════════
  ;; STEP 4 – TEXT HEIGHT  (default saved before getdist call)
  ;; ══════════════════════════════════════════════════════════
  (setq txt-h-default (getvar "TEXTSIZE"))
  (if (or (null txt-h-default) (< txt-h-default 1e-6))
    (setq txt-h-default 2.5))
  (setq txt-h
    (getdist (strcat "\nEnter text height <"
                     (rtos txt-h-default 2 4) ">: ")))
  (if (null txt-h) (setq txt-h txt-h-default))

  ;; ══════════════════════════════════════════════════════════
  ;; STEP 5 – CAPTURE ACTIVE LAYER, ENSURE TABLE LAYER EXISTS
  ;; ══════════════════════════════════════════════════════════
  (setq active-layer (getvar "CLAYER"))
  (princ (strcat "\nPoly number labels will be placed on layer: " active-layer))
  (ensure-layer "AREA_TABLE" 4)   ; cyan – table geometry only

  ;; ══════════════════════════════════════════════════════════
  ;; STEP 6 – SELECT POLYLINES
  ;; ══════════════════════════════════════════════════════════
  (princ "\nSelect polylines to number and measure: ")
  (setq ss (ssget '((0 . "LWPOLYLINE,POLYLINE"))))
  (if (null ss)
    ;; Safe early-out – no (exit)
    (princ "\nNo polylines selected. Command cancelled.")

    ;; ────────────────────────────────────────────────────────
    (progn

      ;; ════════════════════════════════════════════════════
      ;; STEP 7 – PROCESS POLYLINES
      ;; ════════════════════════════════════════════════════
      (setq area-list    '()
            total-area   0.0
            closed-count 0
            n            (sslength ss)   ; capture once
            i            0)

      (repeat n
        (setq ent     (ssname ss i)
              entdata (entget ent)
              flag70  (cdr (assoc 70 entdata)))

        ;; Close if open – guard against missing group 70
        (if (and flag70 (= (logand flag70 1) 0))
          (progn
            (setq entdata
              (subst (cons 70 (+ flag70 1))
                     (assoc 70 entdata) entdata))
            (entmod entdata)
            (entupd ent)
            (setq closed-count (1+ closed-count))))

        ;; Raw area in drawing units²
        (setq area
          (vl-catch-all-apply
            'vlax-get-property
            (list (vlax-ename->vla-object ent) 'Area)))
        (if (vl-catch-all-error-p area) (setq area 0.0))

        ;; Centroid (or bbox midpoint fallback)
        (setq pt (vl-catch-all-apply 'ent-center (list ent)))
        (if (vl-catch-all-error-p pt)
          (setq pt (list 0.0 0.0 0.0)))

        (setq area-list
          (append area-list (list (list (1+ i) area pt))))
        (setq total-area (+ total-area area))
        (setq i (1+ i)))

      ;; ════════════════════════════════════════════════════
      ;; STEP 8 – PLACE NUMBER LABELS (active layer, ByLayer)
      ;; ════════════════════════════════════════════════════
      (foreach item area-list
        (setq lbl (strcat prefix (itoa (nth 0 item))))
        (place-text
          lbl
          (car  (nth 2 item))
          (cadr (nth 2 item))
          txt-h active-layer 256))

      ;; ════════════════════════════════════════════════════
      ;; STEP 9 – TABLE INSERTION POINT
      ;; ════════════════════════════════════════════════════
      (princ "\nPick table insertion point: ")
      (setq tbl-pt (getpoint))

      (if (null tbl-pt)
        (princ "\nTable insertion cancelled.")

        ;; ──────────────────────────────────────────────────
        (progn
          (setq tbl-pt (list (car tbl-pt) (cadr tbl-pt) 0.0))

          ;; ══════════════════════════════════════════════
          ;; STEP 10 – DRAW TABLE  (wrapped in undo group)
          ;; ══════════════════════════════════════════════

          ;; Column width: at least txt-h×14, but grows for long labels
          (setq max-lbl-len
            (apply 'max
              (mapcar
                (function (lambda (item)
                  (strlen (strcat prefix (itoa (nth 0 item))))))
                area-list)))
          (setq col-w (max (* txt-h 14.0)
                           (* max-lbl-len txt-h 0.8)))

          (setq row-h (* txt-h  2.8)
                hdr-h (* txt-h  3.5)
                x0    (car  tbl-pt)
                y0    (cadr tbl-pt)
                x1    (+ x0 col-w)
                x2    (+ x0 (* col-w 2.0))
                x3    (+ x0 (* col-w 3.0)))

          (command "._UNDO" "_Begin")

          ;; Title row
          (setq ytop y0  ybot (- y0 hdr-h))
          (draw-rect x0 ytop x3 ybot "AREA_TABLE")
          (place-text "POLYLINE AREA TABLE"
            (/ (+ x0 x3) 2.0) (/ (+ ytop ybot) 2.0)
            (* txt-h 1.4) "AREA_TABLE" 4)

          ;; Subtitle row
          (setq ytop ybot  ybot (- ytop (* row-h 0.9)))
          (draw-rect x0 ytop x3 ybot "AREA_TABLE")
          (place-text
            (strcat "Drawing units: " draw-unit-name
                    "   |   Areas in: " unit-label
                    (if (= prefix "") "" (strcat "   |   Prefix: " prefix)))
            (/ (+ x0 x3) 2.0) (/ (+ ytop ybot) 2.0)
            (* txt-h 0.75) "AREA_TABLE" 3)

          ;; Column headers
          (setq ytop ybot  ybot (- ytop row-h))
          (draw-rect x0 ytop x1 ybot "AREA_TABLE")
          (draw-rect x1 ytop x2 ybot "AREA_TABLE")
          (draw-rect x2 ytop x3 ybot "AREA_TABLE")
          (place-text "LABEL"
            (/ (+ x0 x1) 2.0) (/ (+ ytop ybot) 2.0) txt-h "AREA_TABLE" 4)
          (place-text (strcat "AREA (" unit-label ")")
            (/ (+ x1 x2) 2.0) (/ (+ ytop ybot) 2.0) txt-h "AREA_TABLE" 4)
          (place-text (strcat "CUM. SUM (" unit-label ")")
            (/ (+ x2 x3) 2.0) (/ (+ ytop ybot) 2.0) txt-h "AREA_TABLE" 4)

          ;; Data rows – accumulate converted values directly
          (setq running-sum 0.0)
          (foreach item area-list
            (setq idx            (nth 0 item)
                  area           (nth 1 item)
                  converted-area (* area conv-factor)
                  lbl            (strcat prefix (itoa idx)))
            (setq running-sum (+ running-sum converted-area))
            (setq ytop ybot  ybot (- ytop row-h))
            (draw-rect x0 ytop x1 ybot "AREA_TABLE")
            (draw-rect x1 ytop x2 ybot "AREA_TABLE")
            (draw-rect x2 ytop x3 ybot "AREA_TABLE")
            (place-text lbl
              (/ (+ x0 x1) 2.0) (/ (+ ytop ybot) 2.0) txt-h "AREA_TABLE" 7)
            (place-text (rtos converted-area 2 4)
              (/ (+ x1 x2) 2.0) (/ (+ ytop ybot) 2.0) txt-h "AREA_TABLE" 7)
            (place-text (rtos running-sum 2 4)
              (/ (+ x2 x3) 2.0) (/ (+ ytop ybot) 2.0) txt-h "AREA_TABLE" 7))

          ;; Total row – use running-sum (= converted total) for consistency
          (setq converted-total running-sum)
          (setq ytop ybot  ybot (- ytop (* row-h 1.4)))
          (draw-rect x0 ytop x3 ybot "AREA_TABLE")
          (draw-rect x0 ytop x2 ybot "AREA_TABLE")
          (place-text "TOTAL AREA"
            (/ (+ x0 x2) 2.0) (/ (+ ytop ybot) 2.0)
            (* txt-h 1.1) "AREA_TABLE" 1)
          (place-text (strcat (rtos converted-total 2 4) " " unit-label)
            (/ (+ x2 x3) 2.0) (/ (+ ytop ybot) 2.0)
            (* txt-h 1.1) "AREA_TABLE" 1)

          (command "._UNDO" "_End")

          ;; ══════════════════════════════════════════════
          ;; STEP 11 – CONSOLE SUMMARY
          ;; ══════════════════════════════════════════════
          (princ (strcat
            "\n\n=== POLYAREA COMPLETE ==="
            "\n  Polylines processed : " (itoa n)
            "\n  Polylines closed    : " (itoa closed-count)
            "\n  Drawing units       : " draw-unit-name
            "\n  Output units        : " unit-label
            "\n  Total area          : " (rtos converted-total 2 4) " " unit-label
            "\n  Prefix used         : " (if (= prefix "") "(none)" prefix)
            "\n  Text height         : " (rtos txt-h 2 4)
            "\n  Label layer         : " active-layer " (your active layer)"
            "\n  Table layer         : AREA_TABLE (cyan)"
            "\n=========================\n"))

        ) ; end progn tbl-pt
      ) ; end if tbl-pt

    ) ; end progn ss
  ) ; end if ss

  (princ)
) ; end C:POLYAREA

(princ "\n[POLYAREA v1.5 loaded]  Type POLYAREA to run.")
(princ)