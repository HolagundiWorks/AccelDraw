(defun c:WinLabel ( / ss ent obj props paramVal insPt txtPt layerName i txtHeight basePt)

  ;; --- Setup ---
  (vl-load-com)
  (if (not *WinLabelHeight*)
    (setq *WinLabelHeight* 0.15)
  )
  (setq txtHeight *WinLabelHeight*)
  (setq layerName "WIN_LABELS")

  ;; Ensure layer exists
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (vl-catch-all-apply
    '(lambda ()
      (vla-add (vla-get-layers doc) layerName)
    )
  )

  ;; Select blocks first
  (princ "\nSelect Window block(s): ")
  (setq ss (ssget))
  (if (null ss)
    (progn (princ "\nNo objects selected.") (exit))
  )

  ;; Then pick text location
  (setq basePt (getpoint "\nPick text insertion point: "))
  (if (null basePt)
    (progn (princ "\nNo point selected.") (exit))
  )

  (setq i 0)
  (while (< i (sslength ss))
    (setq ent (ssname ss i))
    (setq obj (vlax-ename->vla-object ent))

    (setq paramVal nil)
    (vl-catch-all-apply
      '(lambda ()
        (setq props (vlax-invoke obj 'GetDynamicBlockProperties))
        (foreach prop props
          (if (= (vlax-get prop 'PropertyName) "WNAME")
            (setq paramVal (vlax-get prop 'Value))
          )
        )
      )
    )

    (if paramVal
      (progn
        ;; If multiple blocks selected, offset each label downward
        (setq txtPt (list
          (car basePt)
          (- (cadr basePt) (* i (* txtHeight 2.5)))
          0.0
        ))
        (entmake
          (list
            '(0 . "TEXT")
            (cons 8 layerName)
            (cons 10 txtPt)
            (cons 11 txtPt)
            (cons 40 txtHeight)
           (cons 1 (substr paramVal 1 2))
            '(72 . 1)
            '(73 . 0)
          )
        )
        (princ (strcat "\nLabelled: " paramVal))
      )
    )

    (setq i (1+ i))
  )

  (princ "\nDone.")
  (princ)
)

;;; Set text height for WinLabel - persists for the session
(defun c:WinLabelHeight ( / newHeight)
  (setq newHeight
    (getreal (strcat "\nEnter text height <"
      (rtos (if *WinLabelHeight* *WinLabelHeight* 0.15) 2 3)
      ">: "))
  )
  (if newHeight
    (progn
      (setq *WinLabelHeight* newHeight)
      (princ (strcat "\nText height set to: " (rtos *WinLabelHeight* 2 3)))
    )
    (princ "\nHeight unchanged.")
  )
  (princ)
)