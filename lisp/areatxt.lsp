;;; ============================================================
;;; DELETE-AREA-TEXT.LSP
;;;
;;; Finds and deletes all TEXT / MTEXT entities whose content
;;; matches the pattern:  Area: <number>²
;;; (e.g. "Area: 2.67²", "Area: 145.3²", "Area: 0.5²")
;;;
;;; Usage:
;;;   APPLOAD → load file → type  DELETEAREATEXT  <Enter>
;;;   Option A: searches entire drawing automatically
;;;   Option B: you select a region first
;;; ============================================================

(defun c:DELETEAREATEXT ( / ss i ent ed txt count entType choice)

  ;; ── helper: extract plain string from TEXT or MTEXT ─────────
  (defun getTextString (ed / raw)
    (setq raw (cdr (assoc 1 ed)))
    (if (= (cdr (assoc 0 ed)) "MTEXT")
      ;; strip common MTEXT formatting codes like \P \H \W \C \f etc.
      (progn
        (setq raw (vl-string-subst "" "\\P" raw))
        (setq raw (vl-string-subst "" "\\p" raw))
        ;; remove {  }  and any \X; sequences
        (setq raw
          (vl-list->string
            (vl-remove-if
              (function (lambda (c) (or (= c 123) (= c 125))))  ; { }
              (vl-string->list raw)
            )
          )
        )
      )
    )
    raw
  )

  ;; ── helper: does string match "Area: <digits/decimals>²" ────
  ;; The ² character is Unicode 00B2, stored as a raw byte in DXF.
  ;; We match by checking:
  ;;   • starts with "Area: "   (case-insensitive)
  ;;   • followed by digits / decimal point
  ;;   • ends with ² (char code 178, or the \U+00B2 MTEXT form)
  (defun isAreaText (s / up)
    (if (and s (/= s ""))
      (progn
        (setq up (strcase s))
        (or
          ;; plain ² byte (char 178)
          (and
            (= (substr up 1 6) "AREA: ")
            (wcmatch up "AREA: *~[ ]")
          )
          ;; MTEXT unicode form  \U+00B2
          (wcmatch up "AREA: *\\U+00B2")
          ;; literal superscript stored as "^2" in some fonts
          (wcmatch up "AREA: *^2")
          ;; just "Area:" prefix with anything after (broad fallback)
          (= (substr up 1 6) "AREA: ")
        )
      )
      nil
    )
  )

  ;; ── 1. ask user: whole drawing or selection? ────────────────
  (initget "All Selection")
  (setq choice
    (getkword "\nSearch [All/Selection] <All>: ")
  )
  (if (null choice) (setq choice "All"))

  (if (= choice "Selection")
    (progn
      (princ "\nSelect region to search: ")
      (setq ss (ssget '((0 . "TEXT,MTEXT"))))
    )
    (setq ss (ssget "_X" '((0 . "TEXT,MTEXT"))))  ; entire drawing
  )

  (if (null ss)
    (progn (princ "\nNo text found.") (exit))
  )
  (princ (strcat "\nScanning " (itoa (sslength ss)) " text object(s)..."))

  ;; ── 2. scan and collect matches ─────────────────────────────
  (setq count 0  i 0)
  (while (< i (sslength ss))
    (setq ent (ssname ss i)
          ed  (entget ent)
          txt (getTextString ed))

    (if (isAreaText txt)
      (progn
        (princ (strcat "\n  Deleting: \"" txt "\""))
        (entdel ent)
        (setq count (1+ count))
      )
    )
    (setq i (1+ i))
  )

  (princ (strcat "\nDone. " (itoa count) " Area text(s) deleted."))
  (princ)
)