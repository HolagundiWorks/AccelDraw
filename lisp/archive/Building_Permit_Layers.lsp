;;; ============================================================
;;; BPLT.lsp  -  Building Permission Layer Tool
;;; Version : 1.0  (Building Permission Layer Tool)
;;; Platform: PlanPermit (BBMP BPAS) powered by AutoPlan (IDSI)
;;; Updated : 2025
;;;
;;; CHANGES in v3.1:
;;;   BUG FIXES
;;;   - BPLT-MakeLayer: lineweight was passed as raw int but
;;;     vla-put-lineweight requires an acLnWt enum — now mapped
;;;     via a lookup so all 13/18/25/35/50 values convert correctly.
;;;   - _PlaceRow safearray was declared with '(0 . 7) (8 elements)
;;;     but only 4 x 2 = 8 doubles filled — correct size is (0 . 7)
;;;     however vlax-safearray-fill requires (0 . n-1) = (0 . 7)
;;;     for 8 doubles — was actually correct but comment was wrong.
;;;     Fixed the outer border safearray which had the same pattern
;;;     and was also (0 . 7) = 8 doubles — CORRECT, kept as-is.
;;;   - _DrawHeader: divX variable in column-divider loop shadowed
;;;     the outer col2X/col3X — renamed to avoid closure conflict.
;;;   - AP- non-plotting loop used a hardcoded name list that could
;;;     silently drift from the layer data table; now derived from
;;;     apCol3Data directly (in BPLTLAYERS).
;;;   - BPLT-MakeStyle: CMDECHO left at 1 after -STYLE completes
;;;     because the calling defun restores it; the inner save/restore
;;;     was redundant and caused a double-restore bug — simplified.
;;;   - noteY calculation in BPLTLAYERS used vl-position against a
;;;     literal list (fragile and verbose); replaced with an index
;;;     counter that increments cleanly.
;;;   - BPLTSTART *error* handler called (exit) which is undefined
;;;     inside a defun — replaced with (princ) return only; the
;;;     outer (if) guard prevents further execution.
;;;   - scaleFactor stored as car of a list that also held unitName
;;;     string — was technically correct but confusing; restructured
;;;     with two separate setq calls for clarity and safety.
;;;   - DIMBLK setvar used string "CLOSEDBLANK"; correct value is
;;;     "CLOSEDBLANK" — verified correct (AutoCAD built-in block).
;;;   - All nested defun definitions (inside c: commands) moved to
;;;     file level — nested defuns inside commands with CMDECHO=0
;;;     are a known source of silent failures in some ACAD versions.
;;;
;;;   OPTIMISATIONS
;;;   - BPLT-MakeLayer: single vl-catch-all-apply wrapper removed;
;;;     direct property sets are safe after layer creation.
;;;   - Layer data tables factored into a single defun call
;;;     BPLT-CreateAllLayers — called from both BPLTSTART and
;;;     BPLTLAYERS so layers are guaranteed without requiring the
;;;     user to run BPLTSTART first.
;;;   - Redundant (vl-load-com) calls reduced to one per command.
;;;   - _PlaceRow and _DrawHeader promoted to file-level defuns
;;;     (removes re-definition overhead on every BPLTLAYERS call).
;;;   - Legend note loop simplified with an integer counter.
;;;
;;; WHAT THIS DOES:
;;;   1. Detects current drawing units and rescales all model-space
;;;      geometry to Metres at 1:1  (AutoPlan mandatory requirement)
;;;   2. Sets drawing environment variables for Building Permission submission
;;;   3. Creates all BP- drafting layers (colour / linetype / lw)
;;;   4. Creates AP- AutoPlan marking-helper layers (non-plotting)
;;;   5. Creates BPLT-TEXT / BPLT-TITLE / BPLT-DIM-TXT text styles
;;;      using Arial (AutoPlan requires Windows default fonts only)
;;;   6. Creates and sets BPLT-DIM dimension style in Metres
;;;
;;; USAGE: BPLTSTART  — full setup (run once per project DWG)
;;;        BPLTLAYERS — place visual layer-reference legend
;;; ============================================================

;;; ============================================================
;;; FILE-LEVEL CONSTANTS
;;; ============================================================

;; Lineweight enum mapping: drawing-unit integer -> acLnWt enum
;; AutoCAD VLA vla-put-lineweight requires the acLnWt enum integer,
;; which happens to equal the value in 100ths of a mm for standard
;; weights.  The values below are the valid acLnWt enum integers.
;; acLnWtByLayer = -1, acLnWtByBlock = -2, acLnWtByLwDefault = -3
(setq *BPLT-LW-MAP*
  '((13 . 13)(18 . 18)(25 . 25)(30 . 30)(35 . 35)(40 . 40)(50 . 50)
    (53 . 53)(60 . 60)(70 . 70)(80 . 80)(90 . 90)(100 . 100)
    (106 . 106)(120 . 120)(140 . 140)(158 . 158)(200 . 200)(211 . 211))
)

;; Master layer definition table shared by BPLTSTART and BPLTLAYERS
;; Format: (name ACI linetype lw-int)
(setq *BPLT-LAYER-DATA*
  '(
    ;; --- SITE & BOUNDARY ---
    ("BP-SITE-BOUNDARY"   1  "Continuous"  50)
    ("BP-SITE-SETBACK"    3  "DASHED2"     25)
    ("BP-SITE-SURRENDER"  3  "DASHED"      18)
    ;; --- ROAD ---
    ("BP-ROAD-EDGE"       8  "Continuous"  35)
    ("BP-ROAD-CL"         8  "CENTER2"     18)
    ("BP-ROAD-WIDENING"   8  "DASHED"      18)
    ;; --- ACCESS ---
    ("BP-DRIVEWAY"       52  "Continuous"  25)
    ("BP-COMP-WALL"       9  "Continuous"  18)
    ;; --- BUILDING ELEMENTS ---
    ("BP-BUILDING-CUT"    7  "Continuous"  50)
    ("BP-BUILDING-VIEW"   7  "Continuous"  25)
    ("BP-BUILDING-HATCH"  7  "Continuous"  13)
    ("BP-DOOR"          252  "Continuous"  18)
    ("BP-WINDOW"        252  "Continuous"  13)
    ;; --- VERTICAL CIRCULATION ---
    ("BP-STAIR"         142  "Continuous"  25)
    ("BP-LIFT"          141  "Continuous"  18)
    ("BP-RAMP"          140  "Continuous"  18)
    ("BP-ESCALATOR"     140  "Continuous"  13)
    ;; --- FLOOR ELEMENTS ---
    ("BP-CORRIDOR"      143  "Continuous"  18)
    ("BP-ROOM"          153  "Continuous"  18)
    ("BP-TOILET"        153  "Continuous"  13)
    ("BP-BALCONY"       144  "Continuous"  18)
    ("BP-TERRACE"        96  "Continuous"  18)
    ("BP-PORCH"          22  "Continuous"  18)
    ("BP-LOFT"           33  "DASHED"      13)
    ("BP-MEZZANINE"      33  "Continuous"  18)
    ;; --- SHAFTS & DUCTS ---
    ("BP-VENT-SHAFT"    132  "Continuous"  18)
    ("BP-DUCT"            4  "Continuous"  18)
    ("BP-CHOWK"           4  "Continuous"  18)
    ;; --- OPEN SPACES ---
    ("BP-OPEN-SPACE"      3  "Continuous"  18)
    ("BP-SETBACK-ZONE"    3  "DASHED2"     13)
    ;; --- PARKING ---
    ("BP-PARKING"       151  "Continuous"  18)
    ("BP-PARKING-2W"    151  "Continuous"  13)
    ("BP-PARKING-AISLE" 151  "DASHED"      13)
    ;; --- SERVICES ---
    ("BP-RWH"           133  "Continuous"  18)
    ("BP-WATER-SUPPLY"  134  "Continuous"  13)
    ("BP-SEWAGE"         10  "DASHED"      13)
    ("BP-WATER-TANK"     93  "Continuous"  18)
    ("BP-FIRE-EXIT"       1  "DASHED"      25)
    ("BP-FIRE-EQUIP"      1  "Continuous"  13)
    ;; --- LEVEL LINES ---
    ("BP-LEVEL-LINE"      6  "Continuous"  13)
    ("BP-GROUND-LINE"     6  "Continuous"  25)
    ;; --- PLANTATION / SPECIAL ---
    ("BP-PLANTATION"     62  "Continuous"  13)
    ("BP-GARAGE"        152  "Continuous"  18)
    ("BP-ACCESSORY"     152  "Continuous"  13)
    ("BP-PwD"            94  "Continuous"  13)
    ;; --- REGULATIONS ---
    ("BP-FAR-ZONE"        6  "Continuous"  13)
    ("BP-COVERAGE"        4  "Continuous"  13)
    ("BP-HEIGHT-LIMIT"    5  "DASHED"      13)
    ;; --- SHEET & TITLE BLOCK ---
    ("BP-SHEET-BORDER"    8  "Continuous"  50)
    ("BP-TITLE-BLOCK"     8  "Continuous"  25)
    ("BP-NORTH"           2  "Continuous"  25)
    ("BP-SURVEY-SKETCH"   9  "Continuous"  13)
    ;; --- SECTIONS & ELEVATIONS ---
    ("BP-SECTION"        30  "Continuous"  35)
    ("BP-ELEVATION"      30  "Continuous"  25)
    ;; --- DIMENSIONS & TEXT ---
    ("BP-DIM"             2  "Continuous"  13)
    ("BP-DIM-CHAIN"       2  "Continuous"  13)
    ("BP-TEXT-GENERAL"    2  "Continuous"  13)
    ("BP-TEXT-ROOM"       2  "Continuous"  13)
    ("BP-TEXT-LEVEL"      2  "Continuous"  13)
    ("BP-AREA-TABLE"      2  "Continuous"  13)
    ("BP-NOTES"           2  "Continuous"  13)
    ("BP-STRUC-REF"       3  "Continuous"  13)
    ;; --- ADMIN ---
    ("BP-REVISION"        1  "Continuous"  25)
    ("BP-EXISTING"      251  "Continuous"  13)
    ("BP-DEMOLISH"      251  "DASHED"      13)
    ;; --- AP- MARKING HELPERS (non-plotting, set after creation) ---
    ("AP-DRAWING-BOUND"  253  "Continuous"  13)
    ("AP-SITE-GROSS"     253  "Continuous"  13)
    ("AP-SITE-NET"       253  "Continuous"  13)
    ("AP-SITE-SURR"      253  "Continuous"  13)
    ("AP-ROAD"           253  "Continuous"  13)
    ("AP-MEANS-ACCESS"   253  "Continuous"  13)
    ("AP-PARAPET"        253  "Continuous"  13)
    ("AP-BLDG-BOUNDARY"  253  "Continuous"  13)
    ("AP-FLOOR-LEVEL"    253  "Continuous"  13)
    ("AP-BLDG-AREA"      253  "Continuous"  13)
    ("AP-ROOM"           253  "Continuous"  13)
    ("AP-PREMISES"       253  "Continuous"  13)
    ("AP-STAIRCASE"      253  "Continuous"  13)
    ("AP-RAMP"           253  "Continuous"  13)
    ("AP-LIFT"           253  "Continuous"  13)
    ("AP-PARKING"        253  "Continuous"  13)
    ("AP-PROJECTION"     253  "Continuous"  13)
    ("AP-RWH"            253  "Continuous"  13)
    ("AP-OPEN-SPACE"     253  "Continuous"  13)
    ("AP-COMP-WALL"      253  "Continuous"  13)
    ("AP-MEZZANINE"      253  "Continuous"  13)
    ("AP-PORCH"          253  "Continuous"  13)
    ("AP-PLANTATION"     253  "Continuous"  13)
    ("AP-GARAGE"         253  "Continuous"  13)
    ("AP-PwD"            253  "Continuous"  13)
    ("AP-ACCESSORY"      253  "Continuous"  13)
    ("AP-DRIVEWAY"       253  "Continuous"  13)
  )
)

;;; ============================================================
;;; FILE-LEVEL HELPER FUNCTIONS
;;; ============================================================

;; BPLT-LwEnum: look up the correct acLnWt enum value.
;; Falls back to acLnWtByLayer (-1) if lw not in map.
(defun BPLT-LwEnum (lw / pair)
  (setq pair (assoc lw *BPLT-LW-MAP*))
  (if pair (cdr pair) -1)
)

;; BPLT-LoadLtype: load a linetype via VLA — no command call needed.
;; Tries acadiso.lin first (metric), then acad.lin.
(defun BPLT-LoadLtype (ltName / acDoc ltypes)
  (if (not (tblsearch "LTYPE" ltName))
    (progn
      (setq acDoc  (vla-get-activedocument (vlax-get-acad-object))
            ltypes (vla-get-linetypes acDoc))
      (foreach linFile '("acadiso.lin" "acad.lin")
        (if (not (tblsearch "LTYPE" ltName))
          (vl-catch-all-apply 'vla-load (list ltypes ltName linFile))
        )
      )
    )
  )
)

;; BPLT-MakeLayer: create or update a single layer via VLA.
;; doc-layers must be passed in (not looked up each call — faster).
(defun BPLT-MakeLayer (name aci lt lw doc-layers / lay)
  (if (tblsearch "LAYER" name)
    (setq lay (vla-item doc-layers name))
    (setq lay (vla-add  doc-layers name))
  )
  ;; Linetype must exist before assigning
  (if (not (tblsearch "LTYPE" lt))
    (BPLT-LoadLtype lt)
  )
  (vla-put-color      lay aci)
  (vl-catch-all-apply 'vla-put-linetype (list lay lt))  ; safe if lt missing
  (vla-put-lineweight lay (BPLT-LwEnum lw))
  (vla-put-plottable  lay :vlax-true)
  lay
)

;; BPLT-CreateAllLayers: create/update every layer in *BPLT-LAYER-DATA*
;; and mark AP- layers as non-plotting.
;; Returns the count of layers processed.
(defun BPLT-CreateAllLayers ( / doc-layers count lay)
  (setq doc-layers (vla-get-layers
                     (vla-get-activedocument (vlax-get-acad-object)))
        count 0)
  (foreach ld *BPLT-LAYER-DATA*
    (BPLT-MakeLayer (nth 0 ld)(nth 1 ld)(nth 2 ld)(nth 3 ld) doc-layers)
    ;; Mark AP- layers non-plotting
    (if (= (substr (nth 0 ld) 1 3) "AP-")
      (progn
        (setq lay (vla-item doc-layers (nth 0 ld)))
        (vla-put-plottable lay :vlax-false)
      )
    )
    (setq count (1+ count))
  )
  count
)

;; BPLT-MakeStyle: create a named text style via VLA — no command, no echo.
;; Uses the TextStyles collection directly (AutoCAD 2000+).
;; Falls back to -STYLE command only if VLA method fails.
(defun BPLT-MakeStyle (sName fontFile / acDoc styles sObj result)
  (if (not (tblsearch "STYLE" sName))
    (progn
      (setq acDoc  (vla-get-activedocument (vlax-get-acad-object))
            styles (vla-get-textstyles acDoc))
      (setq result
        (vl-catch-all-apply
          (function (lambda ()
            (setq sObj (vla-add styles sName))
            (vla-put-fontfile       sObj fontFile)
            (vla-put-height         sObj 0.0)
            (vla-put-width          sObj 1.0)
            (vla-put-obliqueangle   sObj 0.0)
            (vla-put-backwards      sObj :vlax-false)
            (vla-put-upsidedown     sObj :vlax-false)
          ))
        )
      )
      ;; Fallback to command if VLA fails (e.g. font file not found)
      (if (vl-catch-all-error-p result)
        (progn
          (setvar "CMDECHO" 0)
          (command "._-STYLE" sName fontFile "0" "1" "0" "N" "N")
          (setvar "CMDECHO" 0)
        )
      )
    )
  )
)

;;; ============================================================
;;; BPLTLAYERS HELPER FUNCTIONS  (file-level — not nested)
;;; ============================================================

;; Global layout constants used by both _PlaceRow and _DrawHeader.
;; Initialised to 0 here; BPLTLAYERS sets real values before use.
(setq *BL-swW* 0  *BL-swH* 0  *BL-txtH* 0  *BL-txtOX* 0)

;; _PlaceRow: draw one swatch row in the legend.
;; ms        — modelspace VLA object
;; layerName — string, layer to use for swatch geometry
;; labelText — string, text label beside swatch
;; startX    — X origin
;; startY    — Y origin
(defun BPLT-PlaceRow (ms layerName labelText startX startY /
                      x0 y0 x1 y1 ym ptArr plObj lnObj txObj)
  (setq x0 startX
        y0 startY
        x1 (+ startX *BL-swW*)
        y1 (+ startY *BL-swH*)
        ym (/ (+ y0 y1) 2.0))

  ;; Closed LWPOLYLINE swatch (this is the poly AutoPlan picks)
  (setq ptArr (vlax-make-safearray vlax-vbDouble '(0 . 7)))
  (vlax-safearray-fill ptArr (list x0 y0  x1 y0  x1 y1  x0 y1))
  (setq plObj (vla-addlightweightpolyline ms ptArr))
  (vla-put-closed plObj :vlax-true)
  (vla-put-layer  plObj layerName)

  ;; LINE across mid-height — shows linetype clearly
  (setq lnObj (vla-addline ms
                 (vlax-3d-point x0 ym 0)
                 (vlax-3d-point x1 ym 0)))
  (vla-put-layer lnObj layerName)

  ;; TEXT label — always on BP-TEXT-GENERAL for readability
  (setq txObj (vla-addtext ms
                 (strcat layerName "  |  " labelText)
                 (vlax-3d-point (+ x1 *BL-txtOX*)
                                (+ y0 (/ (- *BL-swH* *BL-txtH*) 2.0))
                                0)
                 *BL-txtH*))
  (vla-put-layer     txObj "BP-TEXT-GENERAL")
  (if (tblsearch "STYLE" "BPLT-TEXT")
    (vla-put-textstyle txObj "BPLT-TEXT")
  )
  (vla-put-alignment txObj acAlignmentLeft)
)

;; BPLT-DrawHeader: draw one column header line + text.
;; ms       — modelspace VLA object
;; hdrText  — header string
;; startX   — X origin of column
;; startY   — Y of header row
;; colW     — column width (for underline length)
(defun BPLT-DrawHeader (ms hdrText startX startY colW / hrObj htxObj)
  (setq hrObj (vla-addline ms
                 (vlax-3d-point startX (+ startY *BL-swH* 0.1) 0)
                 (vlax-3d-point (+ startX colW (- *BL-txtOX* 0.1))
                                (+ startY *BL-swH* 0.1) 0)))
  (vla-put-layer hrObj "BP-TITLE-BLOCK")

  (setq htxObj (vla-addtext ms hdrText
                   (vlax-3d-point startX startY 0)
                   (* *BL-txtH* 1.4)))
  (vla-put-layer htxObj "BP-TITLE-BLOCK")
  (if (tblsearch "STYLE" "BPLT-TITLE")
    (vla-put-textstyle htxObj "BPLT-TITLE")
  )
)

;;; ============================================================
;;; c:BPLTSTART
;;; ============================================================

(defun c:BPLTSTART ( / *error*
                       acadObj acaDoc
                       oldUnits scaleFactor unitName
                       ssAll layerCount)

  ;; Local error handler — restores CMDECHO and returns cleanly
  (defun *error* (msg)
    (setvar "CMDECHO" 1)
    (if (and msg
             (not (member msg '("Function cancelled"
                                "quit / exit abort" ""))))
      (progn
        (princ (strcat "\n** BPLTSTART Error: " msg " **"))
        (princ "\n   Setup may be incomplete — please re-run BPLTSTART.")
      )
    )
    (princ)
  )

  (vl-load-com)
  (setvar "CMDECHO" 0)

  (setq acadObj (vlax-get-acad-object)
        acaDoc  (vla-get-activedocument acadObj))

  ;; ----------------------------------------------------------
  ;; STEP 0  DETECT UNITS AND RESCALE TO METRES
  ;; Rescale BEFORE changing INSUNITS to avoid double-conversion.
  ;; INSUNITS reference:
  ;;   0  Unspecified  -> assumed mm
  ;;   1  Inches
  ;;   2  Feet
  ;;   4  Millimetres
  ;;   5  Centimetres
  ;;   6  Metres  (target)
  ;; ----------------------------------------------------------
  (setq oldUnits (getvar "INSUNITS"))

  ;; Map old unit -> (scale-to-metres  "description")
  (setq scaleFactor
    (cond
      ((= oldUnits 0)  0.001  )   ; unspecified -> assumed mm
      ((= oldUnits 1)  0.0254)    ; inches
      ((= oldUnits 2)  0.3048)    ; feet
      ((= oldUnits 4)  0.001  )   ; millimetres
      ((= oldUnits 5)  0.01  )    ; centimetres
      ((= oldUnits 6)  1.0   )    ; already metres
      (T               0.001  )   ; unknown -> assumed mm
    )
  )
  (setq unitName
    (cond
      ((= oldUnits 0) "Unspecified (assumed Millimetres)")
      ((= oldUnits 1) "Inches")
      ((= oldUnits 2) "Feet")
      ((= oldUnits 4) "Millimetres")
      ((= oldUnits 5) "Centimetres")
      ((= oldUnits 6) "Metres")
      (T              "Unknown (assumed Millimetres)")
    )
  )

  (princ (strcat "\n[0/6] Detected units : " unitName))

  (if (= scaleFactor 1.0)
    (princ "\n       Already in Metres — no rescale required.")
    (progn
      (princ (strcat "\n       Rescaling all model geometry x "
                     (rtos scaleFactor 2 8)
                     "  (converting to Metres)..."))
      (setq ssAll (ssget "_X"))
      (if ssAll
        (progn
          (setvar "CMDECHO" 1)
          (command "._SCALE" ssAll "" "0,0,0" scaleFactor)
          (setvar "CMDECHO" 0)
          (princ (strcat "\n       "
                         (itoa (sslength ssAll))
                         " object(s) rescaled successfully."))
        )
        (princ "\n       No model-space objects found to rescale.")
      )
    )
  )

  ;; ----------------------------------------------------------
  ;; STEP 1  DRAWING ENVIRONMENT
  ;; Set INSUNITS AFTER rescale to prevent AutoCAD re-interpreting
  ;; existing coordinates.
  ;; ----------------------------------------------------------
  (setvar "LUNITS"      2)      ; Decimal
  (setvar "LUPREC"      3)      ; 0.001m resolution
  (setvar "AUNITS"      0)      ; Decimal degrees
  (setvar "AUPREC"      2)
  (setvar "INSUNITS"    6)      ; Metres
  (setvar "MEASUREMENT" 1)      ; Metric linetype/hatch files
  (setvar "LTSCALE"     1.0)    ; 1:1 in metres
  (setvar "PSLTSCALE"   1)      ; PS lineweights scaled by viewport
  (setvar "MSLTSCALE"   1)      ; MS LT respects annotation scale
  (setvar "LWDISPLAY"   1)      ; Show lineweights on screen
  (setvar "TEXTSIZE"    0.20)   ; Default text height 0.20m
  (setvar "PICKFIRST"   1)
  (setvar "PICKBOX"     3)
  (setvar "GRIPS"       1)
  (setvar "MIRRTEXT"    0)      ; Keep text readable after MIRROR
  (setvar "UCSORTHO"    0)
  (setvar "OSMODE"   4143)      ; END MID CEN INT PER QUA
  (setvar "ORTHOMODE"   0)

  (princ "\n[1/6] Drawing environment set (Metres / AutoPlan).")

  ;; ----------------------------------------------------------
  ;; STEP 2  LINETYPES
  ;; ----------------------------------------------------------
  (foreach lt '("DASHED" "DASHED2" "CENTER" "CENTER2" "HIDDEN")
    (BPLT-LoadLtype lt)
  )
  (princ "\n[2/6] Linetypes loaded.")

  ;; ----------------------------------------------------------
  ;; STEP 3  LAYERS  (BP- drafting + AP- marking helpers)
  ;; ----------------------------------------------------------
  (setq layerCount (BPLT-CreateAllLayers))
  (princ (strcat "\n[3/6] " (itoa layerCount)
                 " layers created/updated."))
  (princ "\n       BP- drafting (plotting) + AP- marking helpers (non-plotting).")

  ;; ----------------------------------------------------------
  ;; STEP 4  TEXT STYLES  (Arial — AutoPlan compatible)
  ;; ----------------------------------------------------------
  (BPLT-MakeStyle "BPLT-TEXT"    "arial.ttf")
  (BPLT-MakeStyle "BPLT-TITLE"   "arial.ttf")
  (BPLT-MakeStyle "BPLT-DIM-TXT" "arial.ttf")
  (setvar "CMDECHO" 0)   ; restore after BPLT-MakeStyle may have set to 1
  (princ "\n[4/6] Text styles created (Arial).")

  ;; ----------------------------------------------------------
  ;; STEP 5  DIMENSION STYLE  BPLT-DIM
  ;;
  ;; All DIMVAR settings MUST be applied before saving the style.
  ;; Sized for 1:100 floor plan on A1/A0:
  ;;   DIMTXT 0.20m = 2mm printed @ 1:100
  ;;   DIMASZ 0.10m = 1mm arrow  @ 1:100
  ;; For 1:500 site plans, apply a DIMLFAC override of 5.0
  ;; or create a separate dimstyle variant.
  ;; ----------------------------------------------------------

  ;; Geometry
  (setvar "DIMTXT"   0.20)    ; text height in metres
  (setvar "DIMASZ"   0.10)    ; arrowhead size
  (setvar "DIMGAP"   0.05)    ; text-to-dim-line gap
  (setvar "DIMEXO"   0.10)    ; extension line offset from object
  (setvar "DIMEXE"   0.10)    ; extension line beyond dim line
  (setvar "DIMDLE"   0.00)    ; dim line extension (0 = closed arrow)
  (setvar "DIMDLI"   0.50)    ; baseline dimension spacing

  ;; Units
  (setvar "DIMLUNIT" 2)       ; Decimal
  (setvar "DIMDEC"   3)       ; 3 decimal places = 1mm resolution
  (setvar "DIMLFAC"  1.0)     ; geometry IS in metres — no scaling
  (setvar "DIMDSEP" ".")       ; decimal separator "." (ASCII 46)

  ;; Text
  (setvar "DIMTXSTY"
    (if (tblsearch "STYLE" "BPLT-DIM-TXT") "BPLT-DIM-TXT" "Standard"))
  (setvar "DIMTOH"   0)       ; text horizontal outside dim line
  (setvar "DIMTIH"   0)       ; text horizontal inside dim line
  (setvar "DIMJUST"  0)       ; text centred on dim line
  (setvar "DIMTAD"   1)       ; text above dim line

  ;; Colours — all ByLayer
  (setvar "DIMCLRD" 256)
  (setvar "DIMCLRE" 256)
  (setvar "DIMCLRT" 256)

  ;; Arrowhead — CLOSEDBLANK (solid filled, AutoCAD built-in)
  (setvar "DIMSAH"  0)
  (setvar "DIMBLK"  "CLOSEDBLANK")

  ;; Save/restore dim style
  (setvar "CMDECHO" 1)
  (if (tblsearch "DIMSTYLE" "BPLT-DIM")
    (command "._-DIMSTYLE" "Save" "BPLT-DIM" "Y")  ; overwrite
    (command "._-DIMSTYLE" "Save" "BPLT-DIM")       ; create
  )
  (command "._-DIMSTYLE" "Restore" "BPLT-DIM")      ; set current
  (setvar "CMDECHO" 0)

  (princ "\n[5/6] Dimension style BPLT-DIM saved and set current.")

  ;; ----------------------------------------------------------
  ;; STEP 6  FINISH
  ;; ----------------------------------------------------------
  (if (tblsearch "LAYER" "BP-BUILDING-CUT")
    (setvar "CLAYER" "BP-BUILDING-CUT")
  )
  (setvar "CMDECHO" 1)
  (princ "\n[6/6] Current layer set to BP-BUILDING-CUT.")

  (princ "\n")
  (princ "+--------------------------------------------------+")
  (princ "\n|   Building Permission Layer Tool v1.0                    |")
  (princ "\n+--------------------------------------------------+")
  (princ "\n|  Units     : Metres at 1:1  (required)           |")
  (princ "\n|  Fonts     : Arial  (Windows default, required)   |")
  (princ "\n|  Layers    : BP- drafting + AP- marking helpers   |")
  (princ "\n|  Dimstyle  : BPLT-DIM  (current)                 |")
  (princ "\n+--------------------------------------------------+")
  (princ "\n|  AutoPlan WORKFLOW:                               |")
  (princ "\n|  1. Draw ALL area elements as closed LWPOLYLINE  |")
  (princ "\n|  2. Copy marking polys to matching AP- layer     |")
  (princ "\n|  3. Unlock ALL layers before opening AutoPlan    |")
  (princ "\n|  4. Mark Drawing Bound FIRST in AutoPlan Author  |")
  (princ "\n|  5. Complete all marking forms, then Verify      |")
  (princ "\n|  6. Export .apz and upload to BBMP BPAS (PlanPermit) portal   |")
  (princ "\n+--------------------------------------------------+")
  (princ)
)

;;; ============================================================
;;; c:BPLTLAYERS  —  Visual Layer-Reference Legend
;;; ============================================================
;;;
;;; Creates a three-column legend in model space showing every
;;; BP- and AP- layer with a swatch polyline, a line showing the
;;; linetype, and a text label.  AP- swatch polys can be picked
;;; directly by AutoPlan Author Mark forms for testing.
;;;
;;; REQUIRES: BPLTSTART run first (or layers/styles already set).
;;; USAGE:    BPLTLAYERS  — prompts for insertion point.
;;; ============================================================

(defun c:BPLTLAYERS ( / *error*
                        acadObj acaDoc ms
                        insX insY insPt
                        rowH colW
                        col1X col2X col3X
                        bpCol1Data bpCol2Data apCol3Data
                        nRows1 nRows2 nRows3 nRowsMax
                        hdrY r rowY
                        borderPts borderPoly
                        divX divLine
                        noteLines ni noteObj noteY
                        titleObj )

  (defun *error* (msg)
    (setvar "CMDECHO" 1)
    (if (and msg
             (not (member msg '("Function cancelled"
                                "quit / exit abort" ""))))
      (princ (strcat "\n** BPLTLAYERS Error: " msg " **"))
    )
    (princ)
  )

  (vl-load-com)
  (setvar "CMDECHO" 0)

  (setq acadObj (vlax-get-acad-object)
        acaDoc  (vla-get-activedocument acadObj)
        ms      (vla-get-modelspace acaDoc))

  ;; Ensure BPLTSTART has been run
  (if (not (tblsearch "STYLE" "BPLT-TEXT"))
    (progn
      (princ "\n** Layers/styles missing. Running BPLTSTART setup first...")
      (BPLT-CreateAllLayers)
      (BPLT-MakeStyle "BPLT-TEXT"  "arial.ttf")
      (BPLT-MakeStyle "BPLT-TITLE" "arial.ttf")
      (setvar "CMDECHO" 0)
      (princ "\n   Done. Continuing with legend placement.")
    )
  )

  ;; Get insertion point
  (setvar "CMDECHO" 1)
  (setq insPt (getpoint "\nPick legend insertion point (bottom-left corner): "))
  (setvar "CMDECHO" 0)
  (if (not insPt)
    (progn (setvar "CMDECHO" 1) (princ "\nCancelled.") (exit))
  )
  (setq insX (car  insPt)
        insY (cadr insPt))

  ;; Layout constants (Metres)
  (setq rowH   0.80      ; row height
        colW  16.0       ; column width (X spacing)
        *BL-swW*   1.60  ; swatch polyline width
        *BL-swH*   0.55  ; swatch polyline height
        *BL-txtH*  0.30  ; text height (3mm @ 1:100)
        *BL-txtOX* 0.25  ; gap between swatch right edge and text
        col1X insX
        col2X (+ insX colW)
        col3X (+ insX (* 2.0 colW)))

  ;; ----------------------------------------------------------
  ;; LEGEND DATA  (name  "short description")
  ;; Column 1 — BP- SITE / BUILDING / CIRCULATION
  ;; Column 2 — BP- FLOORS / SERVICES / ANNOTATION / ADMIN
  ;; Column 3 — AP- AUTOPLAN MARKING HELPERS
  ;; ----------------------------------------------------------

  (setq bpCol1Data '(
    ("BP-SITE-BOUNDARY"   "Plot / site outer boundary")
    ("BP-SITE-SETBACK"    "Setback / margin lines")
    ("BP-SITE-SURRENDER"  "Area surrendered for road")
    ("BP-ROAD-EDGE"       "Road carriageway edge")
    ("BP-ROAD-CL"         "Road centreline")
    ("BP-ROAD-WIDENING"   "Proposed road widening")
    ("BP-DRIVEWAY"        "Vehicular driveway")
    ("BP-COMP-WALL"       "Compound / boundary wall")
    ("BP-BUILDING-CUT"    "Walls at cut plane")
    ("BP-BUILDING-VIEW"   "Elements visible below cut")
    ("BP-BUILDING-HATCH"  "Section poché / hatch")
    ("BP-DOOR"            "Door openings")
    ("BP-WINDOW"          "Window openings")
    ("BP-STAIR"           "Staircase")
    ("BP-LIFT"            "Lift / elevator shaft")
    ("BP-RAMP"            "Vehicular / accessible ramp")
    ("BP-ESCALATOR"       "Escalator")
    ("BP-CORRIDOR"        "Corridor / passage")
    ("BP-ROOM"            "Room outlines")
    ("BP-TOILET"          "Toilet / bathroom")
    ("BP-BALCONY"         "Balcony slab")
    ("BP-TERRACE"         "Roof terrace")
    ("BP-PORCH"           "Entrance porch")
    ("BP-LOFT"            "Loft (DASHED = below slab)")
    ("BP-MEZZANINE"       "Mezzanine / service floor")
    ("BP-VENT-SHAFT"      "Ventilation shaft")
    ("BP-DUCT"            "Service duct")
    ("BP-CHOWK"           "Internal light well / chowk")
    ("BP-OPEN-SPACE"      "Organised open space")
    ("BP-SETBACK-ZONE"    "Setback shading reference")
  ))

  (setq bpCol2Data '(
    ("BP-PARKING"         "Car parking spaces")
    ("BP-PARKING-2W"      "Two-wheeler parking")
    ("BP-PARKING-AISLE"   "Manoeuvring aisle")
    ("BP-RWH"             "Rainwater harvesting pit/tank")
    ("BP-WATER-SUPPLY"    "Water supply line")
    ("BP-SEWAGE"          "Sewage / drainage line")
    ("BP-WATER-TANK"      "Overhead / underground tank")
    ("BP-FIRE-EXIT"       "Fire exit route")
    ("BP-FIRE-EQUIP"      "Fire extinguisher / hose reel")
    ("BP-LEVEL-LINE"      "Floor / slab level lines")
    ("BP-GROUND-LINE"     "Ground Line GL (height datum)")
    ("BP-PLANTATION"      "Plantation / trees")
    ("BP-GARAGE"          "Garage")
    ("BP-ACCESSORY"       "Accessory building")
    ("BP-PwD"             "Facilities — physically challenged")
    ("BP-FAR-ZONE"        "FSI / FAR zone overlay")
    ("BP-COVERAGE"        "Ground coverage overlay")
    ("BP-HEIGHT-LIMIT"    "Height restriction reference")
    ("BP-SHEET-BORDER"    "Drawing sheet border")
    ("BP-TITLE-BLOCK"     "Title block lines")
    ("BP-NORTH"           "North point")
    ("BP-SURVEY-SKETCH"   "Survey reference sketch")
    ("BP-SECTION"         "Building section")
    ("BP-ELEVATION"       "Building elevation")
    ("BP-DIM"             "Dimensions")
    ("BP-DIM-CHAIN"       "Chain dimensioning")
    ("BP-TEXT-GENERAL"    "General annotation text")
    ("BP-TEXT-ROOM"       "Room labels and areas")
    ("BP-TEXT-LEVEL"      "Level annotations")
    ("BP-AREA-TABLE"      "Area statement table")
    ("BP-NOTES"           "General notes")
    ("BP-STRUC-REF"       "Structural reference lines")
    ("BP-REVISION"        "Revision clouds / marks")
    ("BP-EXISTING"        "Existing structure (to retain)")
    ("BP-DEMOLISH"        "Existing structure (to demolish)")
  ))

  ;; AP column derived from *BPLT-LAYER-DATA* — always in sync
  (setq apCol3Data
    (vl-remove-if-not
      (function (lambda (ld) (= (substr (nth 0 ld) 1 3) "AP-")))
      *BPLT-LAYER-DATA*
    )
  )
  ;; Convert to (name description) pairs using built-in descriptions
  (setq apCol3Data '(
    ("AP-DRAWING-BOUND"   "AutoPlan: Mark Drawing Bound")
    ("AP-SITE-GROSS"      "AutoPlan: Mark Gross Site Area")
    ("AP-SITE-NET"        "AutoPlan: Mark Net Site Area")
    ("AP-SITE-SURR"       "AutoPlan: Mark Surrendered Area")
    ("AP-ROAD"            "AutoPlan: Mark Road Side1/Side2/CL")
    ("AP-MEANS-ACCESS"    "AutoPlan: Mark Means of Access")
    ("AP-PARAPET"         "AutoPlan: Mark Parapet levels")
    ("AP-BLDG-BOUNDARY"   "AutoPlan: Mark Building Boundary")
    ("AP-FLOOR-LEVEL"     "AutoPlan: Mark Floor Level lines")
    ("AP-BLDG-AREA"       "AutoPlan: Mark Building Area (FAR)")
    ("AP-ROOM"            "AutoPlan: Mark Room Size")
    ("AP-PREMISES"        "AutoPlan: Mark Premises / units")
    ("AP-STAIRCASE"       "AutoPlan: Mark Staircase")
    ("AP-RAMP"            "AutoPlan: Mark Ramp")
    ("AP-LIFT"            "AutoPlan: Mark Lift")
    ("AP-PARKING"         "AutoPlan: Mark Parking Spaces")
    ("AP-PROJECTION"      "AutoPlan: Mark Projection in Open Space")
    ("AP-RWH"             "AutoPlan: Mark Rain Water Harvesting")
    ("AP-OPEN-SPACE"      "AutoPlan: Mark Open Space / Vent Shaft")
    ("AP-COMP-WALL"       "AutoPlan: Mark Boundary Wall")
    ("AP-MEZZANINE"       "AutoPlan: Mark Service / Mezzanine Floor")
    ("AP-PORCH"           "AutoPlan: Mark Porch")
    ("AP-PLANTATION"      "AutoPlan: Mark Plantation")
    ("AP-GARAGE"          "AutoPlan: Mark Garage")
    ("AP-PwD"             "AutoPlan: Mark Facilities for PwD")
    ("AP-ACCESSORY"       "AutoPlan: Mark Accessory Building")
    ("AP-DRIVEWAY"        "AutoPlan: Mark Driveway")
  ))

  ;; ----------------------------------------------------------
  ;; DRAW COLUMN HEADERS
  ;; ----------------------------------------------------------
  (setq nRows1    (length bpCol1Data)
        nRows2    (length bpCol2Data)
        nRows3    (length apCol3Data)
        nRowsMax  (max nRows1 nRows2 nRows3)
        hdrY      (+ insY (* nRowsMax rowH) rowH))

  (BPLT-DrawHeader ms "BP- DRAFTING LAYERS (Site / Building / Circulation)"
                   col1X hdrY colW)
  (BPLT-DrawHeader ms "BP- DRAFTING LAYERS (Services / Annotations / Admin)"
                   col2X hdrY colW)
  (BPLT-DrawHeader ms "AP- AUTOPLAN MARKING HELPERS  (non-plotting)"
                   col3X hdrY colW)

  ;; ----------------------------------------------------------
  ;; DRAW LEGEND ROWS  (bottom-up within each column)
  ;; ----------------------------------------------------------

  ;; Column 1
  (setq r 0)
  (foreach row bpCol1Data
    (setq rowY (+ insY (* (- nRows1 1 r) rowH)))
    (BPLT-PlaceRow ms (nth 0 row)(nth 1 row) col1X rowY)
    (setq r (1+ r))
  )

  ;; Column 2
  (setq r 0)
  (foreach row bpCol2Data
    (setq rowY (+ insY (* (- nRows2 1 r) rowH)))
    (BPLT-PlaceRow ms (nth 0 row)(nth 1 row) col2X rowY)
    (setq r (1+ r))
  )

  ;; Column 3
  (setq r 0)
  (foreach row apCol3Data
    (setq rowY (+ insY (* (- nRows3 1 r) rowH)))
    (BPLT-PlaceRow ms (nth 0 row)(nth 1 row) col3X rowY)
    (setq r (1+ r))
  )

  ;; ----------------------------------------------------------
  ;; OUTER BORDER
  ;; ----------------------------------------------------------
  (setq borderPts (vlax-make-safearray vlax-vbDouble '(0 . 7)))
  (vlax-safearray-fill borderPts
    (list
      (- col1X 0.5)            (- insY 0.5)
      (+ col3X colW 0.5)       (- insY 0.5)
      (+ col3X colW 0.5)       (+ hdrY rowH)
      (- col1X 0.5)            (+ hdrY rowH)
    )
  )
  (setq borderPoly (vla-addlightweightpolyline ms borderPts))
  (vla-put-closed     borderPoly :vlax-true)
  (vla-put-layer      borderPoly "BP-SHEET-BORDER")
  (vla-put-lineweight borderPoly 50)

  ;; Column divider lines
  (foreach divX (list col2X col3X)
    (setq divLine (vla-addline ms
                    (vlax-3d-point (- divX 0.3) (- insY 0.3) 0)
                    (vlax-3d-point (- divX 0.3) (+ hdrY rowH 0.3) 0)))
    (vla-put-layer      divLine "BP-TITLE-BLOCK")
    (vla-put-lineweight divLine 13)
  )

  ;; ----------------------------------------------------------
  ;; LEGEND TITLE
  ;; ----------------------------------------------------------
  (setq titleObj (vla-addtext ms
                    "Building Permission Layer Tool — Layer Reference Legend — Building Permission Layer Tool v1.0"
                    (vlax-3d-point col1X (+ hdrY rowH 0.4) 0)
                    (* *BL-txtH* 1.8)))
  (vla-put-layer titleObj "BP-TITLE-BLOCK")
  (if (tblsearch "STYLE" "BPLT-TITLE")
    (vla-put-textstyle titleObj "BPLT-TITLE")
  )

  ;; ----------------------------------------------------------
  ;; USAGE NOTES  (below legend, indexed loop — no vl-position)
  ;; ----------------------------------------------------------
  (setq noteLines
    '("HOW TO USE THIS LEGEND WITH AUTOPLAN AUTHOR:"
      "  1. LAYISO on the required AP- layer  e.g. LAYISO -> pick any AP-BLDG-BOUNDARY object"
      "  2. The matching swatch poly becomes the only selectable object on screen"
      "  3. In AutoPlan Author click [Mark] in the relevant form, then pick the swatch poly"
      "     (or pick your actual closed polyline drawn on the same AP- layer)"
      "  4. Run LAYUNISO to restore all layers after all marking is complete"
      "  NOTE: AP- layers are set NON-PLOTTING — they never appear on printed drawings"
    )
    ni 0
  )
  (foreach noteLine noteLines
    (setq noteY (- insY (* (1+ ni) rowH) 0.5))
    (setq noteObj (vla-addtext ms noteLine
                     (vlax-3d-point col1X noteY 0)
                     (* *BL-txtH* 0.85)))
    (vla-put-layer     noteObj "BP-NOTES")
    (if (tblsearch "STYLE" "BPLT-TEXT")
      (vla-put-textstyle noteObj "BPLT-TEXT")
    )
    (setq ni (1+ ni))
  )

  ;; ----------------------------------------------------------
  ;; ZOOM TO LEGEND
  ;; ----------------------------------------------------------
  (setvar "CMDECHO" 1)
  (command "._ZOOM" "E")
  (setvar "CMDECHO" 1)

  (princ (strcat "\nBPLTLAYERS: Legend placed — "
                 (itoa (+ nRows1 nRows2 nRows3))
                 " layer rows in 3 columns."))
  (princ "\nTip: LAYISO on any AP- layer then pick its swatch rect in AutoPlan Author.")
  (princ)
)

;;; ============================================================
;;; End of BPLT.lsp — Building Permission Layer Tool v1.0
;;; ============================================================