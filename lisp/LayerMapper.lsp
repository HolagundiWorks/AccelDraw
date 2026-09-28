;;; ============================================================
;;; LayerMapper.lsp — AccelDraw Layer Mapper  v1.0
;;;
;;; Command: LAYERMAP
;;;
;;; For drawings that arrive with someone else's ad-hoc layer names,
;;; this maps each existing layer onto one of the standard layers
;;; already created in this drawing (by VHLAYERS / HCWLAYERS / BPLTSTART
;;; or anything else) and moves every entity across — no re-drawing.
;;;
;;; Workflow:
;;;   1. Pick one or more layers in "Existing layer" (Ctrl/Shift-click for
;;;      several — e.g. map WALL-A, WALL-EXT and A-WALL-OLD all onto the
;;;      same standard "A-WALL" in one go), pick one layer in "Standard
;;;      layer (target)", click "Map ->". Repeat for other groups —
;;;      queued mappings show in the list below.
;;;   2. "Remove Selected Mapping" drops one queued mapping.
;;;   3. "Apply Mappings" moves every entity from each source layer to
;;;      its target layer (CHPROP-equivalent via the Layer property, not
;;;      a redraw), and — if the toggle is on — purges each source layer
;;;      afterwards (silently skipped if AutoCAD won't purge it, e.g. it
;;;      is the current layer or still referenced by a block definition).
;;;
;;; Nothing is moved until "Apply Mappings" is clicked; "Close" discards
;;; any queued-but-unapplied mappings.
;;; ============================================================

(vl-load-com)

;; All layer names currently in the drawing, alphabetically.
(defun layermap:all-layers ( / lst tbl)
  (setq lst '())
  (setq tbl (tblnext "LAYER" T))
  (while tbl
    (setq lst (cons (cdr (assoc 2 tbl)) lst))
    (setq tbl (tblnext "LAYER")))
  (vl-sort lst (function (lambda (a b) (< (strcase a) (strcase b))))))

;; Move every entity on srcLayer to dstLayer via the Layer property
;; (works for entities, block-inserted geometry stays as-is — only the
;; container's own layer changes, matching native CHPROP behaviour).
;; Returns the number of entities moved.
(defun layermap:move-entities (srcLayer dstLayer / ss n i ent moved)
  (setq moved 0)
  (setq ss (ssget "_X" (list (cons 8 srcLayer))))
  (if ss
    (progn
      (setq n (sslength ss)  i 0)
      (while (< i n)
        (setq ent (ssname ss i))
        (if (not (vl-catch-all-error-p
                   (vl-catch-all-apply 'vla-put-layer
                     (list (vlax-ename->vla-object ent) dstLayer))))
          (setq moved (1+ moved)))
        (setq i (1+ i)))))
  moved)

;; Write the mapping dialog's DCL to a temp file. Returns the path.
(defun layermap:write-dcl ( / path f)
  (setq path (strcat (getvar "TEMPPREFIX") "acceldraw_layermap.dcl"))
  (setq f (open path "w"))
  (write-line "layermap_dlg : dialog {" f)
  (write-line "  label = \"AccelDraw Layer Mapper\";" f)
  (write-line "  spacer;" f)
  (write-line "  : row {" f)
  (write-line "    : boxed_column { label = \"Existing layer(s) — Ctrl/Shift-click for several\";" f)
  (write-line "      : list_box { key = \"src_list\"; width = 26; height = 16; fixed_width = true; fixed_height = true; multiple_select = true; } }" f)
  (write-line "    : column { spacer; spacer; spacer; spacer; spacer; spacer;" f)
  (write-line "      : button { key = \"add_btn\"; label = \"Map ->\"; width = 10; fixed_width = true; }" f)
  (write-line "      spacer; }" f)
  (write-line "    : boxed_column { label = \"Standard layer (target)\";" f)
  (write-line "      : list_box { key = \"dst_list\"; width = 26; height = 16; fixed_width = true; fixed_height = true; } }" f)
  (write-line "  }" f)
  (write-line "  spacer;" f)
  (write-line "  : boxed_column { label = \"Mappings queued (not applied yet)\";" f)
  (write-line "    : list_box { key = \"map_list\"; width = 64; height = 8; fixed_width = true; fixed_height = true; } }" f)
  (write-line "  : row {" f)
  (write-line "    : button { key = \"remove_btn\"; label = \"Remove Selected Mapping\"; }" f)
  (write-line "    : toggle { key = \"purge_toggle\"; label = \"Purge empty source layers when applied\"; value = \"1\"; }" f)
  (write-line "  }" f)
  (write-line "  spacer;" f)
  (write-line "  errtile;" f)
  (write-line "  : row {" f)
  (write-line "    : button { key = \"apply_btn\"; label = \"Apply Mappings\"; is_default = true; width = 16; fixed_width = true; }" f)
  (write-line "    : button { key = \"cancel\"; label = \"Close\"; is_cancel = true; width = 16; fixed_width = true; }" f)
  (write-line "  }" f)
  (write-line "}" f)
  (close f)
  path)

;; Parse a DCL multi-select list_box's get_tile value ("0 2 5", or "" for
;; none selected) into a list of integer indices.
(defun layermap:parse-indices (s)
  (if (or (null s) (= s "")) '() (read (strcat "(" s ")"))))

;; Rebuild the "SRC  ->  DST" strings shown in map_list from *mappings*.
(defun layermap:refresh-map-list ( / )
  (start_list "map_list")
  (mapcar
    (function (lambda (p) (add_list (strcat (car p) "   ->   " (cdr p)))))
    *layermap:mappings*)
  (end_list))

(defun c:LAYERMAP ( / dcl-path dcl_id layers result
                      *layermap:mappings*
                      srcIdxList dstSel srcName dstName srcIdx
                      remSel existing pair
                      purge? total-moved total-mappings
                      moved layerObj)

  (setq layers (layermap:all-layers))
  (if (< (length layers) 2)
    (progn (princ "\nNeed at least two layers in the drawing to map between.") (exit)))

  (setq *layermap:mappings* '())
  (setq dcl-path (layermap:write-dcl))
  (setq dcl_id (load_dialog dcl-path))
  (if (not dcl_id)
    (progn (princ "\nCould not load LAYERMAP dialog.") (exit)))

  (if (not (new_dialog "layermap_dlg" dcl_id))
    (progn (unload_dialog dcl_id) (princ "\nCould not initialise LAYERMAP dialog.") (exit)))

  (start_list "src_list") (mapcar 'add_list layers) (end_list)
  (start_list "dst_list") (mapcar 'add_list layers) (end_list)
  (set_tile "src_list" "0")
  (set_tile "dst_list" "0")
  (layermap:refresh-map-list)

  (action_tile "add_btn"
    "(progn
       (setq srcIdxList (layermap:parse-indices (get_tile \"src_list\")))
       (setq dstSel (atoi (get_tile \"dst_list\")))
       (setq dstName (nth dstSel layers))
       (cond
         ((null srcIdxList)
          (set_tile \"error\" \"Select at least one existing layer first.\"))
         (T
          (set_tile \"error\" \"\")
          (foreach srcIdx srcIdxList
            (setq srcName (nth srcIdx layers))
            (if (/= srcName dstName)
              (progn
                (setq existing (assoc srcName *layermap:mappings*))
                (if existing
                  (setq *layermap:mappings*
                    (subst (cons srcName dstName) existing *layermap:mappings*))
                  (setq *layermap:mappings*
                    (append *layermap:mappings* (list (cons srcName dstName))))))))
          (layermap:refresh-map-list)))
     )")

  (action_tile "remove_btn"
    "(progn
       (setq remSel (atoi (get_tile \"map_list\")))
       (if (and (>= remSel 0) (< remSel (length *layermap:mappings*)))
         (progn
           (setq *layermap:mappings*
             (vl-remove (nth remSel *layermap:mappings*) *layermap:mappings*))
           (layermap:refresh-map-list)))
     )")

  (action_tile "apply_btn" "(done_dialog 1)")
  (action_tile "cancel"    "(done_dialog 0)")

  (setq purge? (= (get_tile "purge_toggle") "1"))
  (setq result (start_dialog))
  (setq purge? (= (get_tile "purge_toggle") "1"))
  (unload_dialog dcl_id)

  (if (and (= result 1) *layermap:mappings*)
    (progn
      (setq total-moved 0  total-mappings 0)
      (foreach pair *layermap:mappings*
        (setq moved (layermap:move-entities (car pair) (cdr pair)))
        (princ (strcat "\n  " (car pair) "  ->  " (cdr pair)
                       "   (" (itoa moved) " entit" (if (= moved 1) "y" "ies") ")"))
        (setq total-moved (+ total-moved moved))
        (setq total-mappings (1+ total-mappings)))
      (if purge?
        (progn
          (setvar "CMDECHO" 0)
          (foreach pair *layermap:mappings*
            (vl-catch-all-apply
              (function (lambda ()
                (command "._-PURGE" "_LA" (car pair) "_N"))))
          )
          (setvar "CMDECHO" 1)))
      (princ (strcat "\nLAYERMAP: " (itoa total-mappings) " layer(s) mapped, "
                     (itoa total-moved) " entit"
                     (if (= total-moved 1) "y" "ies") " moved."
                     (if purge? "  Empty source layers purged." "")))
    )
    (princ "\nLAYERMAP: cancelled — nothing changed."))
  (princ))

(princ "\n[LayerMapper] Loaded. Type LAYERMAP to map existing layers onto your standard layers.")
(princ)
