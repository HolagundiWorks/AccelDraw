;;; ============================================================
;;; HCW-TOOLS.lsp
;;; Holgundi Consulting Works — AutoCAD LISP Toolkit
;;; Version : 5.0  (consolidated + optimised)
;;; Updated : 2025
;;;
;;; COMMANDS IN THIS FILE:
;;; ── Text Tools ──────────────────────────────────────────────
;;;   FIXTXT          Fix overlapping text (uniform height + spacing)
;;;   TextIncrement   Copy and auto-increment numbered text
;;; ── Room Dimension Tool ─────────────────────────────────────
;;;   MROOM           Select room from dialog
;;;   MDO             Custom room name
;;;   MBR/MMB/MLI/MDI/MKI/MBA/MAT/MCT/MST/MSR/MPR
;;;   MBC/MTE/MSC/MCO/MEN/MUT/MGA/MGD/MCY/MLO/MOF
;;;   MGR/MPA/MLA/MWR/MDR/MHT/MGY
;;;   MAR             Area of selected polyline
;;;   MRECT           Toggle rectangle drawing
;;;   MHIDERECT       Freeze/thaw rectangle layer
;;;   MTH             Set text height
;;;   MLAYER          Set label layer name
;;;   MSET            Show settings
;;;   MRESET          Reset settings
;;;   MHELP           Help
;;; ── Window Label ────────────────────────────────────────────
;;;   WinLabel        Label window blocks from WNAME parameter
;;;   WinLabelHeight  Set WinLabel text height
;;; ── Building Permission Layer Tool (BBMP BPAS / AutoPlan) ───
;;;   BPLTSTART       Full drawing setup (run once per project)
;;;   BPLTLAYERS      Place visual layer-reference legend
;;; ── HCW Layer Standard ──────────────────────────────────────
;;;   HCWLAYERS       Create / update all HCW layers
;;;   HCWRESET        Repair / reapply all properties
;;;   HCWPURGE        Purge unused layers
;;;   HCWAUDIT        Run AUDIT on active drawing
;;;   HCWINFO         Print full layer table
;;;   HCWLOCK         Lock layers by prefix
;;;   HCWUNLOCK       Unlock layers by prefix
;;; ============================================================

(vl-load-com)  ; load once at file level — not repeated per function

;;; ============================================================
;;; SECTION 1 — SHARED UTILITIES
;;; ============================================================

;;; hcw:str-repeat — repeat a character string n times
(defun hcw:str-repeat (ch n / result)
  (setq result "")
  (repeat (max 0 n) (setq result (strcat result ch)))
  result)

;;; hcw:pad — left-justify str in a field of width chars
(defun hcw:pad (str width / s)
  (setq s (if str (vl-princ-to-string str) ""))
  (if (>= (strlen s) width)
    (substr s 1 width)
    (strcat s (hcw:str-repeat " " (- width (strlen s))))))

;;; hcw:load-lt — load a named linetype from acadiso.lin / acad.lin
;;; Uses session caches *HCW:LT-LOADED* and *HCW:LT-FAILED*
(defun hcw:load-lt (ltName / doc ltypes result)
  (cond
    ((or (null ltName)(= ltName "")
         (= "CONTINUOUS" (strcase ltName))) T)
    ((tblsearch "LTYPE" ltName) T)
    ((member ltName *HCW:LT-LOADED*) T)
    ((member ltName *HCW:LT-FAILED*)
     (princ (strcat "\n  [Warn] Linetype '" ltName "' unavailable (cached)")) nil)
    (T
     (setq doc    (vla-get-ActiveDocument (vlax-get-Acad-Object))
           ltypes (vla-get-Linetypes doc)
           result
             (or
               (not (vl-catch-all-error-p
                      (vl-catch-all-apply 'vla-Load (list ltypes ltName "acadiso.lin"))))
               (not (vl-catch-all-error-p
                      (vl-catch-all-apply 'vla-Load (list ltypes ltName "acad.lin"))))))
     (if result
       (setq *HCW:LT-LOADED* (cons ltName *HCW:LT-LOADED*))
       (progn
         (setq *HCW:LT-FAILED* (cons ltName *HCW:LT-FAILED*))
         (princ (strcat "\n  [Warn] Could not load linetype '" ltName "'"))))
     result)))

;;; hcw:dxf-prop — set a DXF group code on a layer via entmod
(defun hcw:dxf-prop (name grp val / en ed)
  (if (setq en (tblobjname "LAYER" name))
    (progn
      (setq ed (entget en))
      (setq ed (if (assoc grp ed)
                 (subst (cons grp val) (assoc grp ed) ed)
                 (append ed (list (cons grp val)))))
      (not (vl-catch-all-error-p (vl-catch-all-apply 'entmod (list ed)))))))

;;; hcw:set-prop — try VLA setter, fall back to DXF entmod
(defun hcw:set-prop (layObj name setter grp val)
  (or (not (vl-catch-all-error-p
             (vl-catch-all-apply setter (list layObj val))))
      (hcw:dxf-prop name grp val)))

;;; hcw:mm->lw — convert lineweight mm float to acLnWt enum integer
(defun hcw:mm->lw (mm / pair)
  (cond
    ((setq pair (assoc mm *HCW:LW-MAP*)) (cdr pair))
    (T
     (princ (strcat "\n  [Warn] Lineweight " (rtos mm 2 2)
                    " mm not in map — defaulting to 0.18 mm"))
     18)))

;;; hcw:make-layer — create or update one layer (used by both HCW and BPLT)
(defun hcw:make-layer (name aci lt lw layers / existed layObj lw-int ltOk)
  (setq existed (tblsearch "LAYER" name)
        lw-int  (hcw:mm->lw lw))
  (setq ltOk (hcw:load-lt lt))
  (if (not ltOk) (setq lt "Continuous"))
  (setq layObj
    (cond
      (existed (vla-Item layers name))
      ((not (vl-catch-all-error-p
              (vl-catch-all-apply 'vla-Add (list layers name))))
       (and (tblsearch "LAYER" name) (vla-Item layers name)))
      ((not (vl-catch-all-error-p
              (vl-catch-all-apply 'entmake
                (list (list (cons 0 "LAYER") (cons 2 name)
                            (cons 70 0)      (cons 62 aci)
                            (cons 6  lt)     (cons 370 lw-int))))))
       (and (tblsearch "LAYER" name) (vla-Item layers name)))
      ((not (vl-catch-all-error-p
              (vl-catch-all-apply 'entmake
                (list (list (cons 0 "LAYER") (cons 2 name))))))
       (and (tblsearch "LAYER" name) (vla-Item layers name)))
      (T nil)))
  (if layObj
    (progn
      (hcw:set-prop layObj name 'vla-put-Color      62  aci)
      (hcw:set-prop layObj name 'vla-put-Linetype   6   lt)
      (hcw:set-prop layObj name 'vla-put-Lineweight 370 lw-int)
      (if existed 'updated 'created))
    nil))

;;; hcw:make-style — create a named text style via VLA, fall back to -STYLE command
(defun hcw:make-style (sName fontFile / acDoc styles sObj result)
  (if (not (tblsearch "STYLE" sName))
    (progn
      (setq acDoc  (vla-get-activedocument (vlax-get-acad-object))
            styles (vla-get-textstyles acDoc))
      (setq result
        (vl-catch-all-apply
          (function (lambda ()
            (setq sObj (vla-add styles sName))
            (vla-put-fontfile     sObj fontFile)
            (vla-put-height       sObj 0.0)
            (vla-put-width        sObj 1.0)
            (vla-put-obliqueangle sObj 0.0)
            (vla-put-backwards    sObj :vlax-false)
            (vla-put-upsidedown   sObj :vlax-false)))))
      (if (vl-catch-all-error-p result)
        (progn
          (setvar "CMDECHO" 0)
          (command "._-STYLE" sName fontFile "0" "1" "0" "N" "N")
          (setvar "CMDECHO" 0))))))


;;; ============================================================
;;; SECTION 2 — SHARED CONSTANTS
;;; ============================================================

;;; ISO lineweight map: mm float -> acLnWt enum integer
(setq *HCW:LW-MAP*
  '((0.00 .   0)  (0.05 .   5)  (0.09 .   9)  (0.10 .  10)
    (0.13 .  13)  (0.15 .  15)  (0.18 .  18)  (0.20 .  20)
    (0.25 .  25)  (0.30 .  30)  (0.35 .  35)  (0.40 .  40)
    (0.50 .  50)  (0.53 .  53)  (0.60 .  60)  (0.70 .  70)
    (0.80 .  80)  (0.90 .  90)  (1.00 . 100)  (1.06 . 106)
    (1.20 . 120)  (1.40 . 140)  (1.58 . 158)  (2.00 . 200)
    (2.11 . 211)))

;;; Linetype load cache (populated at runtime)
(setq *HCW:LT-LOADED* nil
      *HCW:LT-FAILED* nil)


;;; ============================================================
;;; SECTION 3 — FIXTXT  (fix overlapping text)
;;;
;;; Command: FIXTXT
;;; Selects TEXT/MTEXT objects, sets uniform height (max of
;;; selected), applies Center-Middle justification, then pushes
;;; objects apart so edge gap = 0.5 × height.
;;;
;;; Math (Center-Middle origin = geometric centre of text box):
;;;   top edge  = centerY + H/2
;;;   bot edge  = centerY − H/2
;;;   gap = B_centerY − A_centerY − H
;;;   Target gap = 0.5H  →  c2c = 1.5H
;;;   Only moves B when it is already too close (< c2c apart).
;;; ============================================================

(defun c:FIXTXT ( / ss i ent ed lst sorted
                    maxH h c2cMin
                    prevCY curCY needCY dy
                    ip newip h72 h73)

  (princ "\nSelect TEXT objects: ")
  (setq ss (ssget '((0 . "TEXT,MTEXT"))))
  (if (null ss) (progn (princ "\nNothing selected.") (exit)))
  (princ (strcat "\n" (itoa (sslength ss)) " object(s) selected."))

  ;; Find max height among selection
  (setq maxH 0.0  i 0)
  (while (< i (sslength ss))
    (setq h (cdr (assoc 40 (entget (ssname ss i)))))
    (if (and h (> h maxH)) (setq maxH h))
    (setq i (1+ i)))
  (if (= maxH 0.0) (setq maxH 2.5))

  (setq c2cMin (* maxH 1.5))
  (princ (strcat "\nUniform height: " (rtos maxH 2 4)
                 "  |  c2c min: "     (rtos c2cMin 2 4)
                 "  |  edge gap: "    (rtos (* maxH 0.5) 2 4)))

  ;; Apply height + Centre/Middle justification; collect centre Y
  (setq lst '()  i 0)
  (while (< i (sslength ss))
    (setq ent (ssname ss i)
          ed  (entget ent))

    (if (= (cdr (assoc 0 ed)) "TEXT")
      (progn
        (setq h72 (cdr (assoc 72 ed))
              h73 (cdr (assoc 73 ed)))
        ;; Determine current visual centre point
        (setq ip
          (if (and h72 h73 (= h72 4) (= h73 2))
            (cond ((cdr (assoc 11 ed))) ((cdr (assoc 10 ed))))
            (cdr (assoc 10 ed))))
        ;; Set uniform height
        (setq ed (subst (cons 40 maxH) (assoc 40 ed) ed))
        ;; Horizontal = 4 (Centre)
        (setq ed (if (assoc 72 ed)
                   (subst (cons 72 4) (assoc 72 ed) ed)
                   (append ed (list (cons 72 4)))))
        ;; Vertical = 2 (Middle)
        (setq ed (if (assoc 73 ed)
                   (subst (cons 73 2) (assoc 73 ed) ed)
                   (append ed (list (cons 73 2)))))
        ;; Sync code-10 and code-11 to the same centre point
        (setq ed (subst (cons 10 ip) (assoc 10 ed) ed))
        (setq ed (if (assoc 11 ed)
                   (subst (cons 11 ip) (assoc 11 ed) ed)
                   (append ed (list (cons 11 ip))))))
      (progn
        ;; MTEXT: height only
        (setq ed (subst (cons 40 maxH) (assoc 40 ed) ed))
        (setq ip (cdr (assoc 10 ed)))))

    (entmod ed)
    (entupd ent)
    (setq lst (cons (list (cadr ip) ip ent) lst))
    (setq i (1+ i)))

  ;; Sort ascending by Y
  (setq sorted
    (vl-sort lst (function (lambda (a b) (< (car a) (car b))))))

  ;; Push apart only where actually overlapping
  (setq prevCY nil)
  (foreach item sorted
    (setq curCY (car   item)
          ip    (cadr  item)
          ent   (caddr item))
    (if prevCY
      (progn
        (setq needCY (+ prevCY c2cMin))
        (if (< curCY needCY)
          (progn
            (setq dy    (- needCY curCY)
                  ed    (entget ent)
                  newip (list (car ip) (+ (cadr ip) dy) (caddr ip)))
            (setq ed (subst (cons 10 newip) (assoc 10 ed) ed))
            (if (assoc 11 ed)
              (setq ed (subst (cons 11 newip) (assoc 11 ed) ed)))
            (entmod ed)
            (entupd ent)
            (setq curCY needCY
                  ip    newip)))))
    (setq prevCY curCY))

  (princ (strcat "\nDone.  height=" (rtos maxH 2 4)
                 "  edge-gap=" (rtos (* maxH 0.5) 2 4)
                 "  (= 0.5 × height between text edges)"))
  (princ))


;;; ============================================================
;;; SECTION 4 — TextIncrement
;;;
;;; Command: TextIncrement
;;; Copies a TEXT object to clicked points, incrementing the
;;; last numeric run in the string.  Preserves leading zeros.
;;; ============================================================

;;; hcw:last-num-span — return (start len) of last digit run in s
(defun hcw:last-num-span (s / i start end)
  (setq i (strlen s))
  (while (and (> i 0) (not (wcmatch (substr s i 1) "[0-9]")))
    (setq i (1- i)))
  (if (= i 0)
    nil
    (progn
      (setq end i)
      (while (and (> i 0) (wcmatch (substr s i 1) "[0-9]"))
        (setq i (1- i)))
      (list (1+ i) (1+ (- end i 1))))))

(defun c:TextIncrement ( / ent entData txt num prefix suffix pt span
                           start len numstr newnumstr newtxt)
  (setq ent (car (entsel "\nSelect TEXT to copy and increment: ")))
  (if (and ent (= (cdr (assoc 0 (entget ent))) "TEXT"))
    (progn
      (setq entData (entget ent)
            txt     (cdr (assoc 1 entData))
            span    (hcw:last-num-span txt))
      (if span
        (progn
          (setq start  (car span)
                len    (cadr span)
                numstr (substr txt start len)
                num    (atoi numstr)
                prefix (substr txt 1 (- start 1))
                suffix (substr txt (+ start len)))
          (while (setq pt (getpoint "\nClick to place incremented copy (Enter to finish): "))
            (setq num       (1+ num)
                  newnumstr (itoa num))
            (while (< (strlen newnumstr) len)
              (setq newnumstr (strcat "0" newnumstr)))
            (setq newtxt (strcat prefix newnumstr suffix))
            (entmakex
              (list
                (cons 0  "TEXT")
                (cons 10 pt)
                (cons 11 pt)
                (cons 72 1)
                (cons 73 2)
                (cons 40 (cdr (assoc 40 entData)))
                (cons 50 (cond ((assoc 50 entData)(cdr (assoc 50 entData)))(0.0)))
                (cons 1  newtxt)
                (cons 7  (cdr (assoc 7  entData)))
                (cons 8  (cdr (assoc 8  entData)))))))
        (prompt "\nNo number found in selected text.")))
    (prompt "\nSelect a valid TEXT object."))
  (princ))


;;; ============================================================
;;; SECTION 5 — WinLabel
;;;
;;; Commands: WinLabel / WinLabelHeight
;;; Labels window blocks using the WNAME dynamic block parameter.
;;; ============================================================

(if (not *WinLabelHeight*) (setq *WinLabelHeight* 0.15))

(defun c:WinLabel ( / ss ent obj props paramVal basePt txtPt i doc)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))

  ;; Ensure WIN_LABELS layer exists
  (vl-catch-all-apply
    '(lambda () (vla-add (vla-get-layers doc) "WIN_LABELS")))

  (princ "\nSelect Window block(s): ")
  (setq ss (ssget))
  (if (null ss) (progn (princ "\nNo objects selected.") (exit)))

  (setq basePt (getpoint "\nPick text insertion point: "))
  (if (null basePt) (progn (princ "\nNo point selected.") (exit)))

  (setq i 0)
  (while (< i (sslength ss))
    (setq ent (ssname ss i)
          obj (vlax-ename->vla-object ent)
          paramVal nil)
    (vl-catch-all-apply
      '(lambda ()
        (setq props (vlax-invoke obj 'GetDynamicBlockProperties))
        (foreach prop props
          (if (= (vlax-get prop 'PropertyName) "WNAME")
            (setq paramVal (vlax-get prop 'Value))))))
    (if paramVal
      (progn
        (setq txtPt (list (car basePt)
                          (- (cadr basePt) (* i (* *WinLabelHeight* 2.5)))
                          0.0))
        (entmake
          (list '(0 . "TEXT")
                (cons 8  "WIN_LABELS")
                (cons 10 txtPt)
                (cons 11 txtPt)
                (cons 40 *WinLabelHeight*)
                (cons 1  (substr paramVal 1 2))
                '(72 . 1)
                '(73 . 0)))
        (princ (strcat "\nLabelled: " paramVal))))
    (setq i (1+ i)))
  (princ "\nDone.")
  (princ))

(defun c:WinLabelHeight ( / newHeight)
  (setq newHeight
    (getreal (strcat "\nEnter text height <"
                     (rtos *WinLabelHeight* 2 3) ">: ")))
  (if newHeight
    (progn
      (setq *WinLabelHeight* newHeight)
      (princ (strcat "\nText height set to: " (rtos *WinLabelHeight* 2 3))))
    (princ "\nHeight unchanged."))
  (princ))


;;; ============================================================
;;; SECTION 6 — BPLT  (Building Permission Layer Tool)
;;;
;;; Commands: BPLTSTART / BPLTLAYERS
;;; Platform : PlanPermit (BBMP BPAS) via AutoPlan (IDSI)
;;; Units    : Metres at 1:1 (mandatory)
;;; Fonts    : Arial (Windows default, AutoPlan required)
;;; ============================================================

;;; ── 6a. BPLT layer data table ──────────────────────────────
;;; Format: ("Name"  ACI  "Linetype"  lw-int)
;;; lw-int values are acLnWt enum integers (= 100ths of a mm)

(setq *BPLT:LAYER-DATA*
  '(
    ;; SITE & BOUNDARY
    ("BP-SITE-BOUNDARY"   1  "Continuous"  50)
    ("BP-SITE-SETBACK"    3  "DASHED2"     25)
    ("BP-SITE-SURRENDER"  3  "DASHED"      18)
    ;; ROAD
    ("BP-ROAD-EDGE"       8  "Continuous"  35)
    ("BP-ROAD-CL"         8  "CENTER2"     18)
    ("BP-ROAD-WIDENING"   8  "DASHED"      18)
    ;; ACCESS
    ("BP-DRIVEWAY"       52  "Continuous"  25)
    ("BP-COMP-WALL"       9  "Continuous"  18)
    ;; BUILDING ELEMENTS
    ("BP-BUILDING-CUT"    7  "Continuous"  50)
    ("BP-BUILDING-VIEW"   7  "Continuous"  25)
    ("BP-BUILDING-HATCH"  7  "Continuous"  13)
    ("BP-DOOR"          252  "Continuous"  18)
    ("BP-WINDOW"        252  "Continuous"  13)
    ;; VERTICAL CIRCULATION
    ("BP-STAIR"         142  "Continuous"  25)
    ("BP-LIFT"          141  "Continuous"  18)
    ("BP-RAMP"          140  "Continuous"  18)
    ("BP-ESCALATOR"     140  "Continuous"  13)
    ;; FLOOR ELEMENTS
    ("BP-CORRIDOR"      143  "Continuous"  18)
    ("BP-ROOM"          153  "Continuous"  18)
    ("BP-TOILET"        153  "Continuous"  13)
    ("BP-BALCONY"       144  "Continuous"  18)
    ("BP-TERRACE"        96  "Continuous"  18)
    ("BP-PORCH"          22  "Continuous"  18)
    ("BP-LOFT"           33  "DASHED"      13)
    ("BP-MEZZANINE"      33  "Continuous"  18)
    ;; SHAFTS & DUCTS
    ("BP-VENT-SHAFT"    132  "Continuous"  18)
    ("BP-DUCT"            4  "Continuous"  18)
    ("BP-CHOWK"           4  "Continuous"  18)
    ;; OPEN SPACES
    ("BP-OPEN-SPACE"      3  "Continuous"  18)
    ("BP-SETBACK-ZONE"    3  "DASHED2"     13)
    ;; PARKING
    ("BP-PARKING"       151  "Continuous"  18)
    ("BP-PARKING-2W"    151  "Continuous"  13)
    ("BP-PARKING-AISLE" 151  "DASHED"      13)
    ;; SERVICES
    ("BP-RWH"           133  "Continuous"  18)
    ("BP-WATER-SUPPLY"  134  "Continuous"  13)
    ("BP-SEWAGE"         10  "DASHED"      13)
    ("BP-WATER-TANK"     93  "Continuous"  18)
    ("BP-FIRE-EXIT"       1  "DASHED"      25)
    ("BP-FIRE-EQUIP"      1  "Continuous"  13)
    ;; LEVEL LINES
    ("BP-LEVEL-LINE"      6  "Continuous"  13)
    ("BP-GROUND-LINE"     6  "Continuous"  25)
    ;; PLANTATION / SPECIAL
    ("BP-PLANTATION"     62  "Continuous"  13)
    ("BP-GARAGE"        152  "Continuous"  18)
    ("BP-ACCESSORY"     152  "Continuous"  13)
    ("BP-PwD"            94  "Continuous"  13)
    ;; REGULATIONS
    ("BP-FAR-ZONE"        6  "Continuous"  13)
    ("BP-COVERAGE"        4  "Continuous"  13)
    ("BP-HEIGHT-LIMIT"    5  "DASHED"      13)
    ;; SHEET & TITLE BLOCK
    ("BP-SHEET-BORDER"    8  "Continuous"  50)
    ("BP-TITLE-BLOCK"     8  "Continuous"  25)
    ("BP-NORTH"           2  "Continuous"  25)
    ("BP-SURVEY-SKETCH"   9  "Continuous"  13)
    ;; SECTIONS & ELEVATIONS
    ("BP-SECTION"        30  "Continuous"  35)
    ("BP-ELEVATION"      30  "Continuous"  25)
    ;; DIMENSIONS & TEXT
    ("BP-DIM"             2  "Continuous"  13)
    ("BP-DIM-CHAIN"       2  "Continuous"  13)
    ("BP-TEXT-GENERAL"    2  "Continuous"  13)
    ("BP-TEXT-ROOM"       2  "Continuous"  13)
    ("BP-TEXT-LEVEL"      2  "Continuous"  13)
    ("BP-AREA-TABLE"      2  "Continuous"  13)
    ("BP-NOTES"           2  "Continuous"  13)
    ("BP-STRUC-REF"       3  "Continuous"  13)
    ;; ADMIN
    ("BP-REVISION"        1  "Continuous"  25)
    ("BP-EXISTING"      251  "Continuous"  13)
    ("BP-DEMOLISH"      251  "DASHED"      13)
    ;; AP- AUTOPLAN MARKING HELPERS (non-plotting — set after creation)
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
  ))

;;; ── 6b. BPLT shared helpers ────────────────────────────────

;;; bplt:lw-enum — map raw int to acLnWt enum (BPLT tables store ints directly)
(defun bplt:lw-enum (lw / pair)
  (setq pair (assoc lw *HCW:LW-MAP*))
  ;; *HCW:LW-MAP* stores mm floats; BPLT table stores ints.
  ;; Direct lookup by int works because the enum == int for standard weights.
  (if pair (cdr pair) lw))

;;; bplt:make-layer — create/update one BPLT layer (uses hcw:load-lt)
;;; lw parameter is an acLnWt integer, not mm float
(defun bplt:make-layer (name aci lt lw doc-layers / lay)
  (setq lay
    (if (tblsearch "LAYER" name)
      (vla-item doc-layers name)
      (vla-add  doc-layers name)))
  (if (not (tblsearch "LTYPE" lt)) (hcw:load-lt lt))
  (vla-put-color      lay aci)
  (vl-catch-all-apply 'vla-put-linetype   (list lay lt))
  (vla-put-lineweight lay lw)
  (vla-put-plottable  lay :vlax-true)
  lay)

;;; bplt:create-all-layers — create / update every layer in *BPLT:LAYER-DATA*
;;; and mark AP- layers as non-plotting.  Returns count processed.
(defun bplt:create-all-layers ( / doc-layers count lay)
  (setq doc-layers (vla-get-layers
                     (vla-get-activedocument (vlax-get-acad-object)))
        count 0)
  (foreach ld *BPLT:LAYER-DATA*
    (bplt:make-layer (nth 0 ld)(nth 1 ld)(nth 2 ld)(nth 3 ld) doc-layers)
    (if (= (substr (nth 0 ld) 1 3) "AP-")
      (progn
        (setq lay (vla-item doc-layers (nth 0 ld)))
        (vla-put-plottable lay :vlax-false)))
    (setq count (1+ count)))
  count)

;;; ── 6c. BPLTLAYERS legend helpers ──────────────────────────

(setq *BL-swW* 0  *BL-swH* 0  *BL-txtH* 0  *BL-txtOX* 0)

;;; bplt:place-row — draw one swatch row in the legend
(defun bplt:place-row (ms layerName labelText startX startY /
                       x0 y0 x1 y1 ym ptArr plObj lnObj txObj)
  (setq x0 startX  y0 startY
        x1 (+ startX *BL-swW*)
        y1 (+ startY *BL-swH*)
        ym (/ (+ y0 y1) 2.0))
  ;; Swatch LWPOLYLINE
  (setq ptArr (vlax-make-safearray vlax-vbDouble '(0 . 7)))
  (vlax-safearray-fill ptArr (list x0 y0  x1 y0  x1 y1  x0 y1))
  (setq plObj (vla-addlightweightpolyline ms ptArr))
  (vla-put-closed plObj :vlax-true)
  (vla-put-layer  plObj layerName)
  ;; Mid-height line showing linetype
  (setq lnObj (vla-addline ms
                 (vlax-3d-point x0 ym 0)
                 (vlax-3d-point x1 ym 0)))
  (vla-put-layer lnObj layerName)
  ;; Label text
  (setq txObj (vla-addtext ms
                 (strcat layerName "  |  " labelText)
                 (vlax-3d-point (+ x1 *BL-txtOX*)
                                (+ y0 (/ (- *BL-swH* *BL-txtH*) 2.0)) 0)
                 *BL-txtH*))
  (vla-put-layer txObj "BP-TEXT-GENERAL")
  (if (tblsearch "STYLE" "BPLT-TEXT")
    (vla-put-textstyle txObj "BPLT-TEXT"))
  (vla-put-alignment txObj acAlignmentLeft))

;;; bplt:draw-header — draw column header underline + text
(defun bplt:draw-header (ms hdrText startX startY colW / hrObj htxObj)
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
    (vla-put-textstyle htxObj "BPLT-TITLE")))

;;; ── 6d. c:BPLTSTART ────────────────────────────────────────

(defun c:BPLTSTART ( / *error*
                       acadObj acaDoc
                       oldUnits scaleFactor unitName
                       ssAll layerCount)

  (defun *error* (msg)
    (setvar "CMDECHO" 1)
    (if (and msg (not (member msg '("Function cancelled" "quit / exit abort" ""))))
      (progn
        (princ (strcat "\n** BPLTSTART Error: " msg " **"))
        (princ "\n   Setup may be incomplete — please re-run BPLTSTART.")))
    (princ))

  (setvar "CMDECHO" 0)
  (setq acadObj (vlax-get-acad-object)
        acaDoc  (vla-get-activedocument acadObj))

  ;; ── STEP 0: detect units, rescale to metres ──────────────
  (setq oldUnits (getvar "INSUNITS"))
  (setq scaleFactor
    (cond ((= oldUnits 1) 0.0254) ((= oldUnits 2) 0.3048)
          ((= oldUnits 5) 0.01)   ((= oldUnits 6) 1.0)
          (T 0.001)))  ; 0 / 4 / unknown -> mm
  (setq unitName
    (cond ((= oldUnits 1) "Inches")      ((= oldUnits 2) "Feet")
          ((= oldUnits 4) "Millimetres") ((= oldUnits 5) "Centimetres")
          ((= oldUnits 6) "Metres")      ((= oldUnits 0) "Unspecified (assumed mm)")
          (T "Unknown (assumed mm)")))
  (princ (strcat "\n[0/6] Detected units: " unitName))
  (if (= scaleFactor 1.0)
    (princ "\n       Already in Metres — no rescale required.")
    (progn
      (princ (strcat "\n       Rescaling all model geometry × "
                     (rtos scaleFactor 2 8) " (converting to Metres)..."))
      (setq ssAll (ssget "_X"))
      (if ssAll
        (progn
          (setvar "CMDECHO" 1)
          (command "._SCALE" ssAll "" "0,0,0" scaleFactor)
          (setvar "CMDECHO" 0)
          (princ (strcat "\n       " (itoa (sslength ssAll))
                         " object(s) rescaled.")))
        (princ "\n       No model-space objects found."))))

  ;; ── STEP 1: drawing environment ──────────────────────────
  (setvar "LUNITS"    2)    (setvar "LUPREC"    3)
  (setvar "AUNITS"    0)    (setvar "AUPREC"    2)
  (setvar "INSUNITS"  6)    (setvar "MEASUREMENT" 1)
  (setvar "LTSCALE"   1.0)  (setvar "PSLTSCALE"   1)
  (setvar "MSLTSCALE" 1)    (setvar "LWDISPLAY"   1)
  (setvar "TEXTSIZE"  0.20) (setvar "PICKFIRST"   1)
  (setvar "PICKBOX"   3)    (setvar "GRIPS"       1)
  (setvar "MIRRTEXT"  0)    (setvar "UCSORTHO"    0)
  (setvar "OSMODE" 4143)    (setvar "ORTHOMODE"   0)
  (princ "\n[1/6] Drawing environment set (Metres / AutoPlan).")

  ;; ── STEP 2: linetypes ────────────────────────────────────
  (foreach lt '("DASHED" "DASHED2" "CENTER" "CENTER2" "HIDDEN")
    (hcw:load-lt lt))
  (princ "\n[2/6] Linetypes loaded.")

  ;; ── STEP 3: layers ───────────────────────────────────────
  (setq layerCount (bplt:create-all-layers))
  (princ (strcat "\n[3/6] " (itoa layerCount) " layers created/updated."))
  (princ "\n       BP- drafting (plotting) + AP- marking helpers (non-plotting).")

  ;; ── STEP 4: text styles ──────────────────────────────────
  (foreach s '("BPLT-TEXT" "BPLT-TITLE" "BPLT-DIM-TXT")
    (hcw:make-style s "arial.ttf"))
  (setvar "CMDECHO" 0)
  (princ "\n[4/6] Text styles created (Arial).")

  ;; ── STEP 5: dimension style BPLT-DIM ─────────────────────
  (setvar "DIMTXT"   0.20)  (setvar "DIMASZ"  0.10)
  (setvar "DIMGAP"   0.05)  (setvar "DIMEXO"  0.10)
  (setvar "DIMEXE"   0.10)  (setvar "DIMDLE"  0.00)
  (setvar "DIMDLI"   0.50)  (setvar "DIMLUNIT"    2)
  (setvar "DIMDEC"       3) (setvar "DIMLFAC"  1.0)
  (setvar "DIMDSEP"  ".")   (setvar "DIMTOH"       0)
  (setvar "DIMTIH"       0) (setvar "DIMJUST"      0)
  (setvar "DIMTAD"       1) (setvar "DIMCLRD"    256)
  (setvar "DIMCLRE"    256) (setvar "DIMCLRT"    256)
  (setvar "DIMSAH"       0) (setvar "DIMBLK" "CLOSEDBLANK")
  (setvar "DIMTXSTY"
    (if (tblsearch "STYLE" "BPLT-DIM-TXT") "BPLT-DIM-TXT" "Standard"))
  (setvar "CMDECHO" 1)
  (if (tblsearch "DIMSTYLE" "BPLT-DIM")
    (command "._-DIMSTYLE" "Save"    "BPLT-DIM" "Y")
    (command "._-DIMSTYLE" "Save"    "BPLT-DIM"))
  (command "._-DIMSTYLE" "Restore" "BPLT-DIM")
  (setvar "CMDECHO" 0)
  (princ "\n[5/6] Dimension style BPLT-DIM saved and set current.")

  ;; ── STEP 6: finish ───────────────────────────────────────
  (if (tblsearch "LAYER" "BP-BUILDING-CUT")
    (setvar "CLAYER" "BP-BUILDING-CUT"))
  (setvar "CMDECHO" 1)
  (princ "\n[6/6] Current layer set to BP-BUILDING-CUT.")
  (princ "\n")
  (princ "+--------------------------------------------------+")
  (princ "\n|   Building Permission Layer Tool v1.0            |")
  (princ "\n+--------------------------------------------------+")
  (princ "\n|  Units    : Metres at 1:1  (required)            |")
  (princ "\n|  Fonts    : Arial  (Windows default, required)   |")
  (princ "\n|  Layers   : BP- drafting + AP- marking helpers   |")
  (princ "\n|  Dimstyle : BPLT-DIM  (current)                  |")
  (princ "\n+--------------------------------------------------+")
  (princ "\n|  AutoPlan WORKFLOW:                              |")
  (princ "\n|  1. Draw ALL area elements as closed LWPOLYLINE  |")
  (princ "\n|  2. Copy marking polys to matching AP- layer     |")
  (princ "\n|  3. Unlock ALL layers before opening AutoPlan    |")
  (princ "\n|  4. Mark Drawing Bound FIRST in AutoPlan Author  |")
  (princ "\n|  5. Complete all marking forms, then Verify      |")
  (princ "\n|  6. Export .apz and upload to BBMP BPAS portal   |")
  (princ "\n+--------------------------------------------------+")
  (princ))

;;; ── 6e. c:BPLTLAYERS ───────────────────────────────────────

(defun c:BPLTLAYERS ( / *error*
                        acaDoc ms
                        insX insY insPt
                        rowH colW col1X col2X col3X
                        bpCol1Data bpCol2Data apCol3Data
                        nRows1 nRows2 nRows3 nRowsMax
                        hdrY r rowY
                        borderPts borderPoly divLine
                        noteLines ni noteObj noteY titleObj)

  (defun *error* (msg)
    (setvar "CMDECHO" 1)
    (if (and msg (not (member msg '("Function cancelled" "quit / exit abort" ""))))
      (princ (strcat "\n** BPLTLAYERS Error: " msg " **")))
    (princ))

  (setvar "CMDECHO" 0)
  (setq acaDoc (vla-get-activedocument (vlax-get-acad-object))
        ms     (vla-get-modelspace acaDoc))

  ;; Guard: ensure styles and layers exist
  (if (not (tblsearch "STYLE" "BPLT-TEXT"))
    (progn
      (princ "\n** Styles/layers missing — running setup...")
      (bplt:create-all-layers)
      (foreach s '("BPLT-TEXT" "BPLT-TITLE") (hcw:make-style s "arial.ttf"))
      (setvar "CMDECHO" 0)
      (princ "\n   Done.")))

  (setvar "CMDECHO" 1)
  (setq insPt (getpoint "\nPick legend insertion point (bottom-left corner): "))
  (setvar "CMDECHO" 0)
  (if (not insPt) (progn (setvar "CMDECHO" 1)(princ "\nCancelled.")(exit)))
  (setq insX (car insPt)  insY (cadr insPt))

  ;; Layout constants (Metres)
  (setq rowH      0.80
        colW     16.0
        *BL-swW*  1.60
        *BL-swH*  0.55
        *BL-txtH* 0.30
        *BL-txtOX* 0.25
        col1X insX
        col2X (+ insX colW)
        col3X (+ insX (* 2.0 colW)))

  ;; Legend data
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
    ("BP-SETBACK-ZONE"    "Setback shading reference")))

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
    ("BP-DEMOLISH"        "Existing structure (to demolish)")))

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
    ("AP-DRIVEWAY"        "AutoPlan: Mark Driveway")))

  ;; Draw headers
  (setq nRows1   (length bpCol1Data)
        nRows2   (length bpCol2Data)
        nRows3   (length apCol3Data)
        nRowsMax (max nRows1 nRows2 nRows3)
        hdrY     (+ insY (* nRowsMax rowH) rowH))

  (bplt:draw-header ms "BP- DRAFTING LAYERS (Site / Building / Circulation)"   col1X hdrY colW)
  (bplt:draw-header ms "BP- DRAFTING LAYERS (Services / Annotations / Admin)"  col2X hdrY colW)
  (bplt:draw-header ms "AP- AUTOPLAN MARKING HELPERS  (non-plotting)"          col3X hdrY colW)

  ;; Draw legend rows (bottom-up within each column)
  (setq r 0)
  (foreach row bpCol1Data
    (bplt:place-row ms (nth 0 row)(nth 1 row) col1X (+ insY (* (- nRows1 1 r) rowH)))
    (setq r (1+ r)))

  (setq r 0)
  (foreach row bpCol2Data
    (bplt:place-row ms (nth 0 row)(nth 1 row) col2X (+ insY (* (- nRows2 1 r) rowH)))
    (setq r (1+ r)))

  (setq r 0)
  (foreach row apCol3Data
    (bplt:place-row ms (nth 0 row)(nth 1 row) col3X (+ insY (* (- nRows3 1 r) rowH)))
    (setq r (1+ r)))

  ;; Outer border
  (setq borderPts (vlax-make-safearray vlax-vbDouble '(0 . 7)))
  (vlax-safearray-fill borderPts
    (list (- col1X 0.5)          (- insY 0.5)
          (+ col3X colW 0.5)     (- insY 0.5)
          (+ col3X colW 0.5)     (+ hdrY rowH)
          (- col1X 0.5)          (+ hdrY rowH)))
  (setq borderPoly (vla-addlightweightpolyline ms borderPts))
  (vla-put-closed     borderPoly :vlax-true)
  (vla-put-layer      borderPoly "BP-SHEET-BORDER")
  (vla-put-lineweight borderPoly 50)

  ;; Column dividers
  (foreach divX (list col2X col3X)
    (setq divLine (vla-addline ms
                    (vlax-3d-point (- divX 0.3) (- insY 0.3) 0)
                    (vlax-3d-point (- divX 0.3) (+ hdrY rowH 0.3) 0)))
    (vla-put-layer      divLine "BP-TITLE-BLOCK")
    (vla-put-lineweight divLine 13))

  ;; Legend title
  (setq titleObj (vla-addtext ms
                    "Building Permission Layer Tool — Layer Reference Legend v1.0"
                    (vlax-3d-point col1X (+ hdrY rowH 0.4) 0)
                    (* *BL-txtH* 1.8)))
  (vla-put-layer titleObj "BP-TITLE-BLOCK")
  (if (tblsearch "STYLE" "BPLT-TITLE")
    (vla-put-textstyle titleObj "BPLT-TITLE"))

  ;; Usage notes below legend
  (setq noteLines
    '("HOW TO USE WITH AUTOPLAN AUTHOR:"
      "  1. LAYISO on the required AP- layer  e.g. LAYISO -> pick any AP-BLDG-BOUNDARY object"
      "  2. The matching swatch poly becomes the only selectable object on screen"
      "  3. In AutoPlan Author click [Mark], then pick the swatch poly (or your actual closed poly on the same AP- layer)"
      "  4. Run LAYUNISO to restore all layers after marking is complete"
      "  NOTE: AP- layers are NON-PLOTTING — they never appear on printed drawings")
    ni 0)
  (foreach noteLine noteLines
    (setq noteObj (vla-addtext ms noteLine
                     (vlax-3d-point col1X (- insY (* (1+ ni) rowH) 0.5) 0)
                     (* *BL-txtH* 0.85)))
    (vla-put-layer noteObj "BP-NOTES")
    (if (tblsearch "STYLE" "BPLT-TEXT")
      (vla-put-textstyle noteObj "BPLT-TEXT"))
    (setq ni (1+ ni)))

  (setvar "CMDECHO" 1)
  (command "._ZOOM" "E")
  (princ (strcat "\nBPLTLAYERS: Legend placed — "
                 (itoa (+ nRows1 nRows2 nRows3))
                 " layer rows in 3 columns."))
  (princ "\nTip: LAYISO on any AP- layer then pick its swatch rect in AutoPlan Author.")
  (princ))


;;; ============================================================
;;; SECTION 7 — HCW Layer Standard  v4.0
;;;
;;; Commands: HCWLAYERS / HCWRESET / HCWPURGE / HCWAUDIT
;;;           HCWINFO / HCWLOCK / HCWUNLOCK
;;;
;;; 35 layers  |  AN  A  I  E  P  S  PR
;;; All weights in mm (float) — converted via hcw:mm->lw
;;; ============================================================

(setq *HCW:VERSION* "4.0")

;;; Linetypes to pre-load
(setq *HCW:LINETYPES* '("CENTER2" "HIDDEN" "PHANTOM2" "DASHED2"))

;;; Layer data table
;;; Format: ("Name"  ACI  "Linetype"  lw-mm  "Description")
(setq *HCW:LAYERDATA*
  '(
    ;; ── AN  ANNOTATION ───────────────────────────────────────
    ("AN-REF"    250 "Continuous" 0.09 "Construction lines / viewport borders")
    ("AN-GRID"     8 "CENTER2"    0.13 "Grid and centre lines")
    ("AN-SYMB"     7 "Continuous" 0.18 "North point / symbols / logos")
    ("AN-TEXT"     7 "Continuous" 0.18 "All text — general, title block, keynotes")
    ("AN-DIMS"     8 "Continuous" 0.18 "Dimensions and leaders")
    ("AN-HATCH"    9 "Continuous" 0.10 "Hatching and fill patterns")
    ;; ── A   ARCHITECTURE ─────────────────────────────────────
    ("A-WALL"      1 "Continuous" 0.35 "Walls — new and existing (cut)")
    ("A-DEMO"      1 "DASHED2"    0.25 "Elements to be demolished")
    ("A-COL"       1 "Continuous" 0.35 "Columns (cut)")
    ("A-DOOR"      2 "Continuous" 0.25 "Doors — frame and swing arc")
    ("A-WIND"      4 "Continuous" 0.25 "Windows — frame and sill")
    ("A-GLAZ"      4 "HIDDEN"     0.18 "Glazing / glass line")
    ("A-STAIR"     2 "Continuous" 0.25 "Stairs — treads, stringers, ramps")
    ("A-RAIL"      6 "Continuous" 0.20 "Handrails and balustrades")
    ("A-ROOF"      1 "Continuous" 0.25 "Roof outline and edge")
    ("A-FLR"       3 "Continuous" 0.18 "Floor finish / slab outline")
    ("A-CLNG"      3 "Continuous" 0.18 "Ceiling outline and features")
    ("A-DETAIL"    1 "Continuous" 0.25 "Detail bubbles and reference marks")
    ;; ── I   INTERIORS ────────────────────────────────────────
    ("I-FURN"      3 "Continuous" 0.20 "Loose furniture")
    ("I-JOIN"      5 "Continuous" 0.20 "Fixed joinery — kitchen, wardrobes, built-ins")
    ("I-FINISH"   30 "Continuous" 0.18 "Finish zones and material areas")
    ("I-DECOR"   140 "Continuous" 0.15 "Decorative and soft furnishing elements")
    ;; ── E   ELECTRICAL ───────────────────────────────────────
    ("E-CEIL"    6 "Continuous" 0.18 "Ceiling fittings — lights, fans, AC, sensors")
    ("E-POINT"   2 "Continuous" 0.18 "Wall points — power, data, switches, GPOs")
    ("E-WIRE"   30 "Continuous" 0.15 "Wiring runs and conduit schematic")
    ;; ── P   PLUMBING ─────────────────────────────────────────
    ("P-FIXT"    6 "Continuous" 0.18 "Plumbing fixtures — basin, WC, shower, bath")
    ("P-PIPE"    4 "Continuous" 0.18 "Pipes — supply, drain and vent")
    ;; ── S   SITE ─────────────────────────────────────────────
    ("S-BOUND"   1 "PHANTOM2"   0.35 "Site and property boundary")
    ("S-ROAD"    8 "Continuous" 0.25 "Road edge and carriageway")
    ("S-LAND"    3 "Continuous" 0.18 "Landscaping and planting")
    ("S-TREE"  140 "Continuous" 0.18 "Trees — canopy and trunk")
    ("S-LEVEL"   2 "Continuous" 0.18 "Spot levels and contours")
    ("S-DRAIN"   4 "Continuous" 0.18 "Site drainage and channels")
    ("S-FENCE"   8 "Continuous" 0.20 "Fences and boundary walls")
    ;; ── PR  PRESENTATION ─────────────────────────────────────
    ("PR-TONE"   9 "Continuous" 0.10 "Presentation tone — shadow, fill, material")
    ("PR-CLOUD"  2 "Continuous" 0.25 "Revision clouds")
  ))

;;; ── c:HCWLAYERS ─────────────────────────────────────────────

(defun c:HCWLAYERS ( / *error* doc layers
                       created updated errors total
                       start elapsed
                       origCmdecho origClayer
                       lname laci llt llw result)

  (defun *error* (msg)
    (setvar "CMDECHO" origCmdecho)
    (if (and origClayer (tblsearch "LAYER" origClayer))
      (setvar "CLAYER" origClayer))
    (if (and msg (/= msg "Function cancelled")(/= msg "quit / exit abort"))
      (princ (strcat "\n  [Error] " msg)))
    (princ))

  (setq origCmdecho (getvar "CMDECHO")
        origClayer  (getvar "CLAYER"))
  (setvar "CMDECHO" 0)
  (setq *HCW:LT-LOADED* nil  *HCW:LT-FAILED* nil)

  (setq doc    (vla-get-ActiveDocument (vlax-get-Acad-Object))
        layers (vla-get-Layers doc)
        created 0  updated 0  errors 0
        total   (length *HCW:LAYERDATA*)
        start   (getvar "MILLISECS"))

  (foreach lt *HCW:LINETYPES* (hcw:load-lt lt))

  (princ "\n")
  (princ "\n╔══════════════════════════════════════════════════╗")
  (princ (strcat "\n║   HCW Layer Standard  v" *HCW:VERSION* "                        ║"))
  (princ "\n╠══════════════════════════════════════════════════╣")
  (princ (strcat "\n║  Processing " (hcw:pad (itoa total) 3) " layers...                            ║"))
  (princ "\n╚══════════════════════════════════════════════════╝")

  (foreach ld *HCW:LAYERDATA*
    (if (= 5 (length ld))
      (progn
        (setq lname  (nth 0 ld)  laci  (nth 1 ld)
              llt    (nth 2 ld)  llw   (nth 3 ld)
              result (hcw:make-layer lname laci llt llw layers))
        (cond
          ((eq result 'created) (setq created (1+ created)))
          ((eq result 'updated) (setq updated (1+ updated)))
          (T (princ (strcat "\n  [Error] Failed: " lname))
             (setq errors (1+ errors)))))
      (progn
        (princ (strcat "\n  [Skip] Bad record: " (vl-princ-to-string ld)))
        (setq errors (1+ errors)))))

  (setq elapsed (/ (- (getvar "MILLISECS") start) 1000.0))
  (princ "\n")
  (princ "\n╔══════════════════════════════════════════════════╗")
  (princ "\n║   COMPLETE                                       ║")
  (princ "\n╠══════════════════════════════════════════════════╣")
  (princ (strcat "\n║  Created  : " (hcw:pad (itoa created) 37) "║"))
  (princ (strcat "\n║  Updated  : " (hcw:pad (itoa updated) 37) "║"))
  (if (> errors 0)
    (princ (strcat "\n║  Errors   : " (hcw:pad (strcat (itoa errors) "  <-- see above") 37) "║"))
    (princ "\n║  All layers OK                                   ║"))
  (princ (strcat "\n║  Time     : " (hcw:pad (strcat (rtos elapsed 2 3) "s") 37) "║"))
  (princ "\n╠══════════════════════════════════════════════════╣")
  (princ "\n║  RULES:                                          ║")
  (princ "\n║  - Never draw on layer 0                         ║")
  (princ "\n║  - All properties = ByLayer                      ║")
  (princ "\n║  - Purge unused layers weekly  (HCWPURGE)        ║")
  (princ "\n║  - No ad-hoc layers outside this list            ║")
  (princ "\n╠══════════════════════════════════════════════════╣")
  (princ "\n║  CTB WEIGHTS (all print black):                  ║")
  (princ "\n║  Col  1->0.35  Col  2->0.25  Col  3->0.20       ║")
  (princ "\n║  Col  4->0.18  Col  5->0.18  Col  6->0.18       ║")
  (princ "\n║  Col  7->0.18  Col  8->0.13  Col  9->0.10       ║")
  (princ "\n║  Col 30->0.18  Col140->0.18  Col250->0.09       ║")
  (princ "\n╠══════════════════════════════════════════════════╣")
  (princ "\n║  COMMANDS:                                       ║")
  (princ "\n║  HCWLAYERS  HCWRESET   HCWPURGE  HCWAUDIT       ║")
  (princ "\n║  HCWINFO    HCWLOCK    HCWUNLOCK                 ║")
  (princ "\n╚══════════════════════════════════════════════════╝")
  (setvar "CMDECHO" origCmdecho)
  (princ))

(defun c:HCWRESET ( / )
  (princ "\n  [HCW] Resetting / repairing all layers...")
  (c:HCWLAYERS)
  (princ))

(defun c:HCWPURGE ( / doc layers before after)
  (setvar "CMDECHO" 0)
  (setq doc    (vla-get-ActiveDocument (vlax-get-Acad-Object))
        layers (vla-get-Layers doc)
        before (vla-get-Count layers))
  (command "-purge" "LA" "*" "N")
  (setq after (vla-get-Count layers))
  (princ (strcat "\n  [HCW] Purge complete."
                 "\n  Layers before : " (itoa before)
                 "\n  Layers after  : " (itoa after)
                 "\n  Removed       : " (itoa (- before after))))
  (setvar "CMDECHO" 1)
  (princ))

(defun c:HCWAUDIT ( / )
  (setvar "CMDECHO" 0)
  (princ "\n  [HCW] Running AUDIT...")
  (command "AUDIT" "Y")
  (princ "\n  [HCW] AUDIT complete.")
  (setvar "CMDECHO" 1)
  (princ))

(defun c:HCWINFO ( / )
  (princ "\n")
  (princ "\n╔══════════════════════════════════════════════════════════════════════╗")
  (princ (strcat "\n║  HCW Layer Standard v" *HCW:VERSION* "  —  Layer Table                           ║"))
  (princ "\n╠═══════════════╦═══════╦════════════╦════════╦══════════════════════╣")
  (princ "\n║ Name          ║  ACI  ║ Linetype   ║ LW mm  ║ Description          ║")
  (princ "\n╠═══════════════╩═══════╩════════════╩════════╩══════════════════════╣")
  (foreach ld *HCW:LAYERDATA*
    (princ
      (strcat "\n║ "
              (hcw:pad (nth 0 ld) 14) " "
              (hcw:pad (itoa (nth 1 ld)) 6) " "
              (hcw:pad (nth 2 ld) 11) " "
              (hcw:pad (rtos (nth 3 ld) 2 2) 7) " "
              (hcw:pad (nth 4 ld) 21) "║")))
  (princ "\n╚══════════════════════════════════════════════════════════════════════╝")
  (princ (strcat "\n  Total: " (itoa (length *HCW:LAYERDATA*)) " layers."))
  (princ))

(defun c:HCWLOCK ( / prefix doc layers n)
  (setq prefix (getstring "\n  Prefix to lock (e.g. E-): "))
  (if (= prefix "")
    (princ "\n  [HCW] Cancelled — no prefix entered.")
    (progn
      (setq doc    (vla-get-ActiveDocument (vlax-get-Acad-Object))
            layers (vla-get-Layers doc)
            n 0)
      (vlax-for lay layers
        (if (= prefix (substr (vla-get-Name lay) 1 (strlen prefix)))
          (progn (vla-put-Lock lay :vlax-true)(setq n (1+ n)))))
      (princ (strcat "\n  [HCW] Locked " (itoa n)
                     " layer(s) with prefix '" prefix "'."))))
  (princ))

(defun c:HCWUNLOCK ( / prefix doc layers n)
  (setq prefix (getstring "\n  Prefix to unlock (e.g. E-): "))
  (if (= prefix "")
    (princ "\n  [HCW] Cancelled — no prefix entered.")
    (progn
      (setq doc    (vla-get-ActiveDocument (vlax-get-Acad-Object))
            layers (vla-get-Layers doc)
            n 0)
      (vlax-for lay layers
        (if (= prefix (substr (vla-get-Name lay) 1 (strlen prefix)))
          (progn (vla-put-Lock lay :vlax-false)(setq n (1+ n)))))
      (princ (strcat "\n  [HCW] Unlocked " (itoa n)
                     " layer(s) with prefix '" prefix "'."))))
  (princ))


;;; ============================================================
;;; SECTION 8 — Room Dimension Tool  v2.0
;;;
;;; Pick two corners → room label + dimensions + area centred.
;;; Rectangle drawn on a separate layer (freeze to hide boxes).
;;; ============================================================

;;; ── 8a. Settings ─────────────────────────────────────────────
(setq *room-text-height*     0.15)
(setq *room-draw-rectangle*  T)
(setq *room-layer-name*      "ROOM-LABELS")
(setq *room-rect-layer*      "ROOM-RECTANGLES")
(setq *room-layers-created*  nil)
(setq *room-text-height-units* nil)   ; in drawing units; nil = ask on first use

;;; ── 8b. Unit helpers ─────────────────────────────────────────

;;; room:units->m — convert drawing units to metres
(defun room:units->m (value / scale)
  (setq scale
    (cond ((= (getvar "INSUNITS") 4) 0.001)
          ((= (getvar "INSUNITS") 5) 0.01)
          ((= (getvar "INSUNITS") 6) 1.0)
          (T 0.001)))
  (* value scale))

;;; room:format-dim — "W m × H m"
(defun room:format-dim (w h)
  (strcat (rtos (room:units->m w) 2 2) " m × "
          (rtos (room:units->m h) 2 2) " m"))

;;; room:format-area — "Area: X.XX m²"
(defun room:format-area (w h)
  (strcat "Area: "
          (rtos (* (room:units->m w)(room:units->m h)) 2 2)
          " m\u00B2"))

;;; room:ensure-layers — create label + rectangle layers once per session
(defun room:ensure-layers ( / doc layers)
  (if (not *room-layers-created*)
    (progn
      (setq doc    (vla-get-activedocument (vlax-get-acad-object))
            layers (vla-get-layers doc))
      (if (not (tblsearch "LAYER" *room-layer-name*))
        (vla-put-color (vla-add layers *room-layer-name*) 3))
      (if (not (tblsearch "LAYER" *room-rect-layer*))
        (vla-put-color (vla-add layers *room-rect-layer*) 8))
      (setq *room-layers-created* T))))

;;; room:ask-height — prompt once, persist in *room-text-height-units*
(defun room:ask-height ( / input scale)
  (setq input (getreal (strcat "\nEnter text height in metres <"
                               (rtos *room-text-height* 2 2) ">: ")))
  (if input (setq *room-text-height* input))
  (setq scale
    (cond ((= (getvar "INSUNITS") 4) 1000.0)
          ((= (getvar "INSUNITS") 5) 100.0)
          ((= (getvar "INSUNITS") 6) 1.0)
          (T 1000.0)))
  (setq *room-text-height-units* (* *room-text-height* scale))
  *room-text-height-units*)

;;; room:draw-rect — draw a closed LWPOLYLINE for the room outline
(defun room:draw-rect (ms pt1 pt2 / x1 y1 x2 y2 pts pline)
  (setq x1 (car pt1) y1 (cadr pt1)
        x2 (car pt2) y2 (cadr pt2)
        pts (vlax-make-safearray vlax-vbDouble '(0 . 7)))
  (vlax-safearray-fill pts (list x1 y1  x2 y1  x2 y2  x1 y2))
  (setq pline (vla-addLightweightPolyline ms pts))
  (vla-put-closed pline :vlax-true)
  (vla-put-layer  pline *room-rect-layer*)
  pline)

;;; ── 8c. Core labelling function ──────────────────────────────

(defun room:create-label (room-type / pt1 pt2 cx cy w h th
                          ms doc old-layer txt1 txt2 txt3)
  (room:ensure-layers)
  (setq old-layer (getvar "CLAYER"))

  (setq pt1 (getpoint "\n│ Select FIRST corner of room: "))
  (if (not pt1) (progn (princ "\nCancelled.") (exit)))
  (setq pt2 (getcorner pt1 "\n│ Select OPPOSITE corner of room: "))
  (if (not pt2) (progn (princ "\nCancelled.") (exit)))

  (setq cx (/ (+ (car pt1)(car pt2)) 2.0)
        cy (/ (+ (cadr pt1)(cadr pt2)) 2.0)
        w  (abs (- (car pt2)(car pt1)))
        h  (abs (- (cadr pt2)(cadr pt1))))

  (if (not *room-text-height-units*) (room:ask-height))
  (setq th *room-text-height-units*)

  (setq doc (vla-get-activedocument (vlax-get-acad-object))
        ms  (vla-get-modelspace doc))

  (if *room-draw-rectangle* (room:draw-rect ms pt1 pt2))

  (setvar "CLAYER" *room-layer-name*)

  ;; Room type text
  (setq txt1 (vla-addtext ms (strcase room-type) (vlax-3d-point cx cy 0) th))
  (vla-put-alignment txt1 acAlignmentMiddleCenter)
  (vla-put-textalignmentpoint txt1 (vlax-3d-point cx cy 0))

  ;; Dimension text
  (setq txt2 (vla-addtext ms (room:format-dim w h)
                 (vlax-3d-point cx (- cy (* th 1.5)) 0) (* th 0.8)))
  (vla-put-alignment txt2 acAlignmentMiddleCenter)
  (vla-put-textalignmentpoint txt2 (vlax-3d-point cx (- cy (* th 1.5)) 0))

  ;; Area text
  (setq txt3 (vla-addtext ms (room:format-area w h)
                 (vlax-3d-point cx (- cy (* th 2.8)) 0) (* th 0.7)))
  (vla-put-alignment txt3 acAlignmentMiddleCenter)
  (vla-put-textalignmentpoint txt3 (vlax-3d-point cx (- cy (* th 2.8)) 0))

  (setvar "CLAYER" old-layer)
  (princ (strcat "\n┌────────────────────────────────────"
                 "\n│ " (strcase room-type)
                 "\n│ " (room:format-dim w h)
                 "\n│ " (room:format-area w h)
                 "\n└────────────────────────────────────"))
  (princ))

;;; ── 8d. Room type commands ───────────────────────────────────

(defun c:mbr () (room:create-label "Bedroom")         (princ))
(defun c:mmb () (room:create-label "Master Bedroom")  (princ))
(defun c:mgr () (room:create-label "Guest Room")      (princ))
(defun c:mli () (room:create-label "Living Room")     (princ))
(defun c:mdi () (room:create-label "Dining Room")     (princ))
(defun c:mki () (room:create-label "Kitchen")         (princ))
(defun c:mpa () (room:create-label "Pantry")          (princ))
(defun c:mba () (room:create-label "Bathroom")        (princ))
(defun c:mat () (room:create-label "Attached Toilet") (princ))
(defun c:mct () (room:create-label "Common Toilet")   (princ))
(defun c:mst () (room:create-label "Study Room")      (princ))
(defun c:mof () (room:create-label "Office")          (princ))
(defun c:msr () (room:create-label "Store Room")      (princ))
(defun c:mpr () (room:create-label "Pooja Room")      (princ))
(defun c:mbc () (room:create-label "Balcony")         (princ))
(defun c:mte () (room:create-label "Terrace")         (princ))
(defun c:msc () (room:create-label "Staircase")       (princ))
(defun c:mco () (room:create-label "Corridor")        (princ))
(defun c:men () (room:create-label "Entrance")        (princ))
(defun c:mlo () (room:create-label "Lobby")           (princ))
(defun c:mut () (room:create-label "Utility")         (princ))
(defun c:mla () (room:create-label "Laundry")         (princ))
(defun c:mga () (room:create-label "Garage")          (princ))
(defun c:mgd () (room:create-label "Garden")          (princ))
(defun c:mcy () (room:create-label "Courtyard")       (princ))
(defun c:mwr () (room:create-label "Wardrobe")        (princ))
(defun c:mdr () (room:create-label "Dressing Room")   (princ))
(defun c:mht () (room:create-label "Home Theater")    (princ))
(defun c:mgy () (room:create-label "Gym")             (princ))

(defun c:mdo ( / room-type)
  (setq room-type (getstring T "\n│ Enter room type: "))
  (if (and room-type (/= room-type ""))
    (room:create-label room-type)
    (princ "\nCancelled."))
  (princ))

;;; ── 8e. MROOM dialog ─────────────────────────────────────────

(defun room:create-dcl ( / path f)
  (setq path (strcat (getvar "TEMPPREFIX") "room_selector.dcl")
        f    (open path "w"))
  (if f
    (progn
      (foreach line
        '("room_selector : dialog {"
          "  label = \"Select Room Type\";"
          "  : boxed_column { label = \"Room Types\";"
          "    : list_box { key = \"room_list\"; width = 40; height = 20;"
          "      fixed_width = true; fixed_height = true; } }"
          "  : row { fixed_width = true; alignment = centered;"
          "    : button { key = \"accept\"; label = \"OK\";"
          "      is_default = true; width = 12; fixed_width = true; }"
          "    : button { key = \"cancel\"; label = \"Cancel\";"
          "      is_cancel = true; width = 12; fixed_width = true; } }"
          "}")
        (write-line line f))
      (close f)
      path)
    nil))

(defun c:mroom ( / dcl-path dcl_id room-types room-choice result selected custom)
  (setq room-types
    '("Bedroom" "Master Bedroom" "Guest Room" "Living Room" "Dining Room"
      "Kitchen" "Pantry" "Bathroom" "Attached Toilet" "Common Toilet"
      "Study Room" "Office" "Store Room" "Pooja Room" "Balcony" "Terrace"
      "Staircase" "Corridor" "Entrance" "Lobby" "Utility" "Laundry"
      "Garage" "Garden" "Courtyard" "Wardrobe" "Dressing Room"
      "Home Theater" "Gym" "Custom..."))
  (setq dcl-path (room:create-dcl))
  (if (not dcl-path)
    (c:mdo)
    (progn
      (setq dcl_id (load_dialog dcl-path))
      (if (not dcl_id)
        (c:mdo)
        (progn
          (if (not (new_dialog "room_selector" dcl_id))
            (progn (unload_dialog dcl_id) (c:mdo))
            (progn
              (start_list "room_list")
              (mapcar 'add_list room-types)
              (end_list)
              (set_tile "room_list" "0")
              (action_tile "accept"
                "(progn (setq room-choice (atoi (get_tile \"room_list\"))) (done_dialog 1))")
              (action_tile "cancel" "(done_dialog 0)")
              (setq result (start_dialog))
              (unload_dialog dcl_id)
              (if (= result 1)
                (progn
                  (setq selected (nth room-choice room-types))
                  (if (= selected "Custom...")
                    (progn
                      (setq custom (getstring T "\n│ Enter custom room type: "))
                      (if (and custom (/= custom ""))
                        (room:create-label custom)
                        (princ "\n│ Cancelled.")))
                    (room:create-label selected)))
                (princ "\n│ Room selection cancelled."))))))))
  (princ))

;;; ── 8f. Utility commands ─────────────────────────────────────

(defun c:mar ( / ent obj area cx cy centre th area-text doc ms txt)
  (setq ent (car (entsel "\n│ Select polyline or rectangle: ")))
  (if ent
    (progn
      (setq obj (vlax-ename->vla-object ent))
      (if (and (vlax-property-available-p obj 'Area)
               (vlax-property-available-p obj 'Centroid))
        (progn
          (setq area      (vla-get-area obj)
                centre    (vlax-safearray->list
                            (vlax-variant-value (vla-get-centroid obj)))
                th        (if *room-text-height-units*
                             *room-text-height-units*
                             (room:ask-height))
                area-text (strcat "Area: "
                            (rtos (* (room:units->m 1.0)(room:units->m area)) 2 2)
                            " m\u00B2"))
          (setq doc (vla-get-activedocument (vlax-get-acad-object))
                ms  (vla-get-modelspace doc))
          (setq txt (vla-addtext ms area-text (vlax-3d-point centre) th))
          (vla-put-alignment txt acAlignmentMiddleCenter)
          (vla-put-textalignmentpoint txt (vlax-3d-point centre))
          (vla-put-layer txt *room-layer-name*)
          (princ (strcat "\n│ " area-text " created at centroid")))
        (princ "\n│ Selected object has no area property.")))
    (princ "\n│ No object selected."))
  (princ))

(defun c:mrect ( / )
  (setq *room-draw-rectangle* (not *room-draw-rectangle*))
  (princ (strcat "\n│ Rectangle drawing: "
                 (if *room-draw-rectangle* "ON" "OFF")))
  (princ))

(defun c:mhiderect ( / doc lay frozen)
  (if (tblsearch "LAYER" *room-rect-layer*)
    (progn
      (setq doc (vla-get-activedocument (vlax-get-acad-object))
            lay (vla-item (vla-get-layers doc) *room-rect-layer*)
            frozen (= (vla-get-freeze lay) :vlax-true))
      (if frozen
        (progn (vla-put-freeze lay :vlax-false)
               (princ (strcat "\n│ " *room-rect-layer* ": VISIBLE")))
        (progn (vla-put-freeze lay :vlax-true)
               (princ (strcat "\n│ " *room-rect-layer* ": HIDDEN")))))
    (princ (strcat "\n│ Layer " *room-rect-layer* " does not exist yet.")))
  (princ))

(defun c:mth ( / )
  (room:ask-height)
  (princ (strcat "\n│ Text height set to: " (rtos *room-text-height* 2 2) " m"))
  (princ))

(defun c:mlayer ( / new-layer doc layers)
  (setq new-layer (getstring T "\n│ Enter layer name for room labels: "))
  (if (and new-layer (/= new-layer ""))
    (progn
      (setq *room-layer-name*     new-layer
            *room-layers-created* nil)   ; force re-check
      (princ (strcat "\n│ Layer set to: " *room-layer-name*)))
    (princ "\n│ Cancelled."))
  (princ))

(defun c:mset ( / )
  (princ "\n╔════════════════════════════════════════╗")
  (princ "\n║   CURRENT SETTINGS                     ║")
  (princ "\n╠════════════════════════════════════════╣")
  (princ (strcat "\n║ Text Height    : " (rtos *room-text-height* 2 2) " m"))
  (princ (strcat "\n║ Draw Rectangle : " (if *room-draw-rectangle* "YES" "NO")))
  (princ (strcat "\n║ Text Layer     : " *room-layer-name*))
  (princ (strcat "\n║ Rect Layer     : " *room-rect-layer*))
  (princ "\n╚════════════════════════════════════════╝")
  (princ "\n│ TIP: Freeze ROOM-RECTANGLES layer to hide boxes only")
  (princ))

(defun c:mreset ( / )
  (setq *room-text-height*       0.15
        *room-draw-rectangle*    T
        *room-layer-name*        "ROOM-LABELS"
        *room-rect-layer*        "ROOM-RECTANGLES"
        *room-text-height-units* nil
        *room-layers-created*    nil)
  (princ "\n│ All settings reset to defaults.")
  (princ))

(defun c:mhelp ( / )
  (princ "\n╔════════════════════════════════════════════════════════════╗")
  (princ "\n║        ROOM DIMENSION TOOL — METRIC v2.0                   ║")
  (princ "\n╠════════════════════════════════════════════════════════════╣")
  (princ "\n║  MROOM   Select room from dialog (recommended)             ║")
  (princ "\n║  MDO     Type custom room name manually                    ║")
  (princ "\n╠════════════════════════════════════════════════════════════╣")
  (princ "\n║  ROOM SHORTCUTS:                                           ║")
  (princ "\n║  MBR MMB MGR MLI MDI MKI MPA MBA MAT MCT                  ║")
  (princ "\n║  MST MOF MSR MPR MBC MTE MSC MCO MEN MLO                  ║")
  (princ "\n║  MUT MLA MGA MGD MCY MWR MDR MHT MGY MDO                  ║")
  (princ "\n╠════════════════════════════════════════════════════════════╣")
  (princ "\n║  UTILITIES:                                                ║")
  (princ "\n║  MAR       Area label for selected polyline                ║")
  (princ "\n║  MRECT     Toggle rectangle drawing ON/OFF                 ║")
  (princ "\n║  MHIDERECT Freeze/thaw rectangle layer                     ║")
  (princ "\n║  MTH       Change text height                              ║")
  (princ "\n║  MLAYER    Change label layer name                         ║")
  (princ "\n║  MSET      Show current settings                           ║")
  (princ "\n║  MRESET    Reset all settings to defaults                  ║")
  (princ "\n║  MHELP     This help message                               ║")
  (princ "\n╚════════════════════════════════════════════════════════════╝")
  (princ))


;;; ============================================================
;;; SECTION 9 — BPLT NEW COMMANDS
;;;
;;;   BPLTCOPY       Auto-copy BP- objects to matching AP- layer
;;;   BPLTCHECK      Pre-submission validator for AutoPlan
;;;   BPLTAREA       Area statement from AP- closed polylines
;;;   BPLTREPORT     CSV export of all BP-/AP- layer stats
;;;   BPLTTITLEBLOCK Insert title block frame at standard sheet size
;;; ============================================================

;;; ── 9a. BPLTCOPY ─────────────────────────────────────────────
;;; For each selected object whose layer starts with "BP-",
;;; finds the matching "AP-" layer (same suffix) and places a
;;; copy there.  Only layers that exist in both BP- and AP- form
;;; are copied; others are reported and skipped.

(defun c:BPLTCOPY ( / ss i ent ed layName apName apBase doc layers copyEnt copyEd
                      copied skipped)
  (princ "\nSelect BP- objects to copy to matching AP- layers: ")
  (setq ss (ssget))
  (if (null ss) (progn (princ "\nNothing selected.") (exit)))
  (setq doc    (vla-get-activedocument (vlax-get-acad-object))
        layers (vla-get-layers doc)
        copied 0  skipped 0  i 0)

  (while (< i (sslength ss))
    (setq ent     (ssname ss i)
          ed      (entget ent)
          layName (cdr (assoc 8 ed)))

    ;; Only process objects on BP- layers
    (if (= (substr (strcase layName) 1 3) "BP-")
      (progn
        ;; Build AP- layer name from BP- suffix
        (setq apBase  (substr layName 4)          ; strip "BP-"
              apName  (strcat "AP-" apBase))

        (if (tblsearch "LAYER" apName)
          (progn
            ;; Deep-copy via entmakex then reassign layer
            (setq copyEnt (entmakex ed))
            (if copyEnt
              (progn
                (setq copyEd (entget copyEnt))
                (setq copyEd (subst (cons 8 apName)(assoc 8 copyEd) copyEd))
                (entmod copyEd)
                (entupd copyEnt)
                (setq copied (1+ copied))
                (princ (strcat "\n  Copied: " layName " -> " apName)))
              (progn
                (princ (strcat "\n  [Warn] entmakex failed for: " layName))
                (setq skipped (1+ skipped)))))
          (progn
            (princ (strcat "\n  [Skip] No AP- layer for: " layName
                           " (expected " apName ")"))
            (setq skipped (1+ skipped)))))
      (setq skipped (1+ skipped)))   ; not a BP- object

    (setq i (1+ i)))

  (princ (strcat "\nBPLTCOPY done.  Copied: " (itoa copied)
                 "  Skipped: " (itoa skipped)))
  (princ))


;;; ── 9b. BPLTCHECK ────────────────────────────────────────────
;;; Pre-submission validator.  Checks:
;;;   1. AP-DRAWING-BOUND exists and has at least 1 closed poly
;;;   2. Every AP- layer in the required list has >= 1 closed poly
;;;   3. No open polylines on any AP- layer
;;; Prints a PASS / WARN / FAIL report.

(defun c:BPLTCHECK ( / requiredAP ssAll i ent ed layName closed
                       apCounts apOpen missingLayers openCount
                       status)

  ;; Minimum required AP- layers for a valid AutoPlan submission
  (setq requiredAP
    '("AP-DRAWING-BOUND" "AP-SITE-GROSS" "AP-SITE-NET"
      "AP-ROAD" "AP-BLDG-BOUNDARY" "AP-FLOOR-LEVEL"
      "AP-BLDG-AREA" "AP-ROOM"))

  ;; Initialise counters
  (setq apCounts nil   ; assoc list (layerName . closedCount)
        apOpen   nil   ; assoc list (layerName . openCount)
        i 0)

  ;; Scan all model-space LWPOLYLINE and POLYLINE objects
  (setq ssAll (ssget "_X" '((0 . "LWPOLYLINE,POLYLINE"))))
  (if ssAll
    (while (< i (sslength ssAll))
      (setq ent     (ssname ssAll i)
            ed      (entget ent)
            layName (cdr (assoc 8 ed)))
      (if (= (substr (strcase layName) 1 3) "AP-")
        (progn
          (setq closed
            (cond
              ;; LWPOLYLINE: bit 1 of code 70 = closed
              ((= (cdr (assoc 0 ed)) "LWPOLYLINE")
               (/= 0 (logand (cdr (assoc 70 ed)) 1)))
              ;; POLYLINE: bit 1 of code 70
              (T (/= 0 (logand (cdr (assoc 70 ed)) 1)))))
          (if closed
            ;; Increment closed count
            (if (assoc layName apCounts)
              (setq apCounts
                (subst (cons layName (1+ (cdr (assoc layName apCounts))))
                       (assoc layName apCounts) apCounts))
              (setq apCounts (cons (cons layName 1) apCounts)))
            ;; Increment open count
            (if (assoc layName apOpen)
              (setq apOpen
                (subst (cons layName (1+ (cdr (assoc layName apOpen))))
                       (assoc layName apOpen) apOpen))
              (setq apOpen (cons (cons layName 1) apOpen))))))
      (setq i (1+ i))))

  ;; Build missing-layers list
  (setq missingLayers
    (vl-remove-if
      (function (lambda (ln) (assoc ln apCounts)))
      requiredAP))

  (setq openCount (length apOpen))

  ;; Print report
  (princ "\n")
  (princ "\n╔══════════════════════════════════════════════════════╗")
  (princ "\n║   BPLTCHECK — AutoPlan Pre-Submission Report         ║")
  (princ "\n╠══════════════════════════════════════════════════════╣")

  ;; Required layers
  (princ "\n║  REQUIRED AP- LAYERS:                                ║")
  (foreach ln requiredAP
    (setq cnt (cdr (assoc ln apCounts)))
    (princ (strcat "\n║  " (hcw:pad ln 24)
                   (if cnt
                     (strcat "  PASS  (" (itoa cnt) " closed poly/s)")
                     "  FAIL  *** MISSING ***")
                   "   ║")))

  ;; Open polylines
  (princ "\n╠══════════════════════════════════════════════════════╣")
  (if (= openCount 0)
    (princ "\n║  Open polylines on AP- layers:  NONE  (PASS)         ║")
    (progn
      (princ (strcat "\n║  Open polylines found on " (itoa openCount) " AP- layer(s):  WARN  ║"))
      (foreach pair apOpen
        (princ (strcat "\n║    " (hcw:pad (car pair) 28)
                       (itoa (cdr pair)) " open   ║")))))

  ;; Summary
  (setq status
    (cond ((> (length missingLayers) 0) "FAIL — missing required layers")
          ((> openCount 0)              "WARN — open polylines present")
          (T                            "PASS — ready for AutoPlan")))
  (princ "\n╠══════════════════════════════════════════════════════╣")
  (princ (strcat "\n║  RESULT: " (hcw:pad status 43) "║"))
  (princ "\n╚══════════════════════════════════════════════════════╝")
  (princ))


;;; ── 9c. BPLTAREA ─────────────────────────────────────────────
;;; Reads all closed LWPOLYLINEs on selected AP- layers,
;;; computes area in m², and places a formatted MTEXT area
;;; statement table on BP-AREA-TABLE at a user-picked point.

(defun c:BPLTAREA ( / apLayers filter ssAll i ent ed layName obj area
                      areaData totalArea insPt ms doc tblStr mObj)

  ;; Collect distinct AP- layer names present in drawing
  (setq apLayers nil  i 0)
  (setq ssAll (ssget "_X" '((0 . "LWPOLYLINE"))))
  (if ssAll
    (while (< i (sslength ssAll))
      (setq layName (cdr (assoc 8 (entget (ssname ssAll i)))))
      (if (and (= (substr (strcase layName) 1 3) "AP-")
               (not (member layName apLayers)))
        (setq apLayers (cons layName apLayers)))
      (setq i (1+ i))))

  (if (null apLayers)
    (progn (princ "\nNo AP- polylines found in drawing.") (exit)))

  (princ (strcat "\nFound AP- layers: " (itoa (length apLayers))))

  ;; Sum closed-poly areas per AP- layer
  (setq areaData nil  totalArea 0.0  i 0)
  (while (< i (sslength ssAll))
    (setq ent     (ssname ssAll i)
          ed      (entget ent)
          layName (cdr (assoc 8 ed)))
    (if (and (= (substr (strcase layName) 1 3) "AP-")
             (/= 0 (logand (cdr (assoc 70 ed)) 1)))  ; closed bit
      (progn
        (setq obj  (vlax-ename->vla-object ent)
              area (vla-get-area obj))
        (if (assoc layName areaData)
          (setq areaData
            (subst (cons layName (+ (cdr (assoc layName areaData)) area))
                   (assoc layName areaData) areaData))
          (setq areaData (cons (cons layName area) areaData)))
        (setq totalArea (+ totalArea area))))
    (setq i (1+ i)))

  ;; Pick insertion point
  (setq insPt (getpoint "\nPick insertion point for area table: "))
  (if (null insPt) (progn (princ "\nCancelled.") (exit)))

  ;; Ensure target layer exists
  (if (not (tblsearch "LAYER" "BP-AREA-TABLE"))
    (bplt:create-all-layers))

  (setq doc (vla-get-activedocument (vlax-get-acad-object))
        ms  (vla-get-modelspace doc))

  ;; Build MTEXT string  (\\P = paragraph break in MTEXT)
  (setq tblStr "AREA STATEMENT\\P")
  (setq tblStr (strcat tblStr (hcw:pad "Layer" 26) (hcw:pad "Area (m2)" 14) "\\P"))
  (setq tblStr (strcat tblStr (hcw:str-repeat "-" 38) "\\P"))
  (foreach pair (vl-sort areaData (function (lambda (a b)(string< (car a)(car b)))))
    (setq tblStr
      (strcat tblStr
              (hcw:pad (car pair) 26)
              (hcw:pad (rtos (* (cdr pair) 1.0) 2 3) 14)
              "\\P")))
  (setq tblStr (strcat tblStr (hcw:str-repeat "-" 38) "\\P"))
  (setq tblStr (strcat tblStr (hcw:pad "TOTAL" 26)
                       (rtos (* totalArea 1.0) 2 3) " m2"))

  ;; Place MTEXT
  (setq mObj (vla-addmtext ms (vlax-3d-point insPt) 12.0 tblStr))
  (vla-put-layer mObj "BP-AREA-TABLE")
  (if (tblsearch "STYLE" "BPLT-TEXT")
    (vla-put-textstyle mObj "BPLT-TEXT"))
  (vla-put-height mObj 0.20)

  (princ (strcat "\nBPLTAREA: Table placed.  Total area: "
                 (rtos (* totalArea 1.0) 2 3) " m2"))
  (princ))


;;; ── 9d. BPLTREPORT ───────────────────────────────────────────
;;; Exports a CSV: layer, type (BP/AP), object count,
;;; total closed-poly area (m²), plottable status.
;;; Written to the drawing's folder (or TEMPPREFIX if unsaved).

(defun c:BPLTREPORT ( / doc acaDoc dwgPath csvPath f
                        ssAll i ent ed layName obj area
                        counts areas layers lay plotFlag
                        sortedNames)

  (setq acaDoc  (vla-get-activedocument (vlax-get-acad-object))
        dwgPath (vla-get-path acaDoc))
  (if (= dwgPath "")
    (setq dwgPath (getvar "TEMPPREFIX")))
  (setq csvPath (strcat dwgPath "BPLT-LayerReport.csv"))

  ;; Collect object counts and areas per BP-/AP- layer
  (setq counts nil  areas nil  i 0)
  (setq ssAll (ssget "_X"))
  (if ssAll
    (while (< i (sslength ssAll))
      (setq ent     (ssname ssAll i)
            ed      (entget ent)
            layName (cdr (assoc 8 ed)))
      (if (or (= (substr (strcase layName) 1 3) "BP-")
              (= (substr (strcase layName) 1 3) "AP-"))
        (progn
          (if (assoc layName counts)
            (setq counts
              (subst (cons layName (1+ (cdr (assoc layName counts))))
                     (assoc layName counts) counts))
            (setq counts (cons (cons layName 1) counts)))
          ;; Area only for closed LWPOLYLINEs
          (if (and (= (cdr (assoc 0 ed)) "LWPOLYLINE")
                   (/= 0 (logand (cdr (assoc 70 ed)) 1)))
            (progn
              (setq obj  (vlax-ename->vla-object ent)
                    area (vla-get-area obj))
              (if (assoc layName areas)
                (setq areas
                  (subst (cons layName (+ (cdr (assoc areas layName)) area))
                         (assoc layName areas) areas))
                (setq areas (cons (cons layName area) areas)))))))
      (setq i (1+ i))))

  ;; Write CSV
  (setq f (open csvPath "w"))
  (if (null f)
    (progn (princ (strcat "\n[Error] Cannot write to: " csvPath)) (exit)))

  (write-line "Layer,Type,ObjectCount,ClosedPolyArea_m2,Plottable" f)

  (setq layers (vla-get-layers acaDoc))
  (setq sortedNames
    (vl-sort (mapcar 'car counts) 'string<))

  (foreach ln sortedNames
    (setq lay       (if (tblsearch "LAYER" ln)(vla-item layers ln) nil)
          plotFlag  (if lay
                      (if (= (vla-get-plottable lay) :vlax-true) "Yes" "No")
                      "?")
          cnt       (cdr (assoc ln counts))
          areVal    (cdr (assoc ln areas)))
    (write-line
      (strcat ln ","
              (substr (strcase ln) 1 2) ","
              (itoa (if cnt cnt 0)) ","
              (if areVal (rtos areVal 2 4) "0") ","
              plotFlag)
      f))

  (close f)
  (princ (strcat "\nBPLTREPORT: CSV written to " csvPath))
  (princ))


;;; ── 9e. BPLTTITLEBLOCK ───────────────────────────────────────
;;; Inserts a title block LWPOLYLINE frame on BP-SHEET-BORDER
;;; at a user-picked insertion point.
;;; Sheet sizes at 1:1 (mm converted to metres):
;;;   A0 = 1189 × 841 mm  A1 = 841 × 594 mm  A2 = 594 × 420 mm

(defun c:BPLTTITLEBLOCK ( / choice sizes sheetName W H insPt ms doc
                            pts poly titleW titleH titlePts titlePoly
                            projTxt drawTxt revTxt scaleTxt)

  (initget 1 "A0 A1 A2")
  (setq choice (getkword "\nSheet size [A0/A1/A2] <A1>: "))
  (if (null choice)(setq choice "A1"))

  (setq sizes
    '(("A0" 1.189 0.841)
      ("A1" 0.841 0.594)
      ("A2" 0.594 0.420)))
  (setq sheetName choice
        W (cadr  (assoc choice sizes))
        H (caddr (assoc choice sizes)))

  (setq insPt (getpoint "\nPick bottom-left corner of title block: "))
  (if (null insPt)(progn (princ "\nCancelled.")(exit)))

  (if (not (tblsearch "LAYER" "BP-SHEET-BORDER"))
    (bplt:create-all-layers))

  (setq doc (vla-get-activedocument (vlax-get-acad-object))
        ms  (vla-get-modelspace doc))

  ;; Outer sheet border
  (setq pts (vlax-make-safearray vlax-vbDouble '(0 . 7)))
  (vlax-safearray-fill pts
    (list (car insPt)     (cadr insPt)
          (+ (car insPt) W) (cadr insPt)
          (+ (car insPt) W) (+ (cadr insPt) H)
          (car insPt)       (+ (cadr insPt) H)))
  (setq poly (vla-addlightweightpolyline ms pts))
  (vla-put-closed     poly :vlax-true)
  (vla-put-layer      poly "BP-SHEET-BORDER")
  (vla-put-lineweight poly 50)

  ;; Title strip — 60 mm tall across full width at bottom
  (setq titleH 0.060
        titleW W)
  (setq titlePts (vlax-make-safearray vlax-vbDouble '(0 . 7)))
  (vlax-safearray-fill titlePts
    (list (car insPt)     (cadr insPt)
          (+ (car insPt) titleW) (cadr insPt)
          (+ (car insPt) titleW) (+ (cadr insPt) titleH)
          (car insPt)            (+ (cadr insPt) titleH)))
  (setq titlePoly (vla-addlightweightpolyline ms titlePts))
  (vla-put-closed     titlePoly :vlax-true)
  (vla-put-layer      titlePoly "BP-TITLE-BLOCK")
  (vla-put-lineweight titlePoly 25)

  ;; Placeholder texts in title strip
  (foreach item
    (list
      (list "PROJECT NAME" (list (+ (car insPt) 0.010)
                                 (+ (cadr insPt) titleH 0.005) 0) 0.012)
      (list "DRAWING TITLE" (list (+ (car insPt) 0.010)
                                  (+ (cadr insPt) titleH 0.020) 0) 0.010)
      (list (strcat "Sheet: " sheetName)
                    (list (+ (car insPt) W -0.120)
                          (+ (cadr insPt) 0.010) 0) 0.008)
      (list "Rev: A0" (list (+ (car insPt) W -0.060)
                            (+ (cadr insPt) 0.010) 0) 0.008))
    (setq txtObj (vla-addtext ms (car item)(vlax-3d-point (cadr item))(caddr item)))
    (vla-put-layer txtObj "BP-TITLE-BLOCK")
    (if (tblsearch "STYLE" "BPLT-TITLE")
      (vla-put-textstyle txtObj "BPLT-TITLE")))

  (princ (strcat "\nBPLTTITLEBLOCK: " sheetName " ("
                 (rtos (* W 1000) 2 0) " x "
                 (rtos (* H 1000) 2 0)
                 " mm) placed on BP-SHEET-BORDER."))
  (princ))


;;; ============================================================
;;; SECTION 10 — HCW NEW COMMANDS
;;;
;;;   HCWAUDIT2      List all objects not on a standard HCW layer
;;;   HCWBYBLOCK     Find objects with explicit colour/lw overrides
;;;   HCWMOVE        Move selected objects to a chosen HCW layer
;;;   HCWSCHEDULE    Export layer schedule to CSV
;;;   HCWLAYERSTATE  Save / restore layer freeze/lock/colour states
;;;   HCWLEGEND      Place visual HCW layer legend in model space
;;; ============================================================

;;; ── 10a. HCWAUDIT2 ───────────────────────────────────────────
;;; Scans all model-space objects, collects those NOT on a
;;; standard HCW layer, groups by rogue layer, reports counts,
;;; and optionally moves them all to a nominated layer.

(defun c:HCWAUDIT2 ( / validNames ssAll i ent ed layName
                       rogueMap rogueLayers moveTarget doc layers)

  (setq validNames (mapcar 'car *HCW:LAYERDATA*))

  (setq ssAll (ssget "_X"))
  (if (null ssAll)(progn (princ "\nNo objects in drawing.")(exit)))

  (setq rogueMap nil  i 0)
  (while (< i (sslength ssAll))
    (setq ed      (entget (ssname ssAll i))
          layName (cdr (assoc 8 ed)))
    (if (not (member layName validNames))
      (if (assoc layName rogueMap)
        (setq rogueMap
          (subst (cons layName (1+ (cdr (assoc layName rogueMap))))
                 (assoc layName rogueMap) rogueMap))
        (setq rogueMap (cons (cons layName 1) rogueMap))))
    (setq i (1+ i)))

  (if (null rogueMap)
    (princ "\nHCWAUDIT2: All objects are on standard HCW layers. PASS.")
    (progn
      (princ (strcat "\nHCWAUDIT2: " (itoa (length rogueMap))
                     " non-standard layer(s) found:"))
      (foreach pair (vl-sort rogueMap (function (lambda (a b)(string< (car a)(car b)))))
        (princ (strcat "\n  " (hcw:pad (car pair) 28)
                       (itoa (cdr pair)) " object(s)")))

      ;; Offer to move
      (initget "Yes No")
      (if (= "Yes" (getkword "\nMove all rogue objects to a target layer? [Yes/No]: "))
        (progn
          (setq moveTarget (getstring T "\nEnter target HCW layer name: "))
          (if (tblsearch "LAYER" moveTarget)
            (progn
              (setq i 0)
              (while (< i (sslength ssAll))
                (setq ent     (ssname ssAll i)
                      ed      (entget ent)
                      layName (cdr (assoc 8 ed)))
                (if (not (member layName validNames))
                  (progn
                    (setq ed (subst (cons 8 moveTarget)(assoc 8 ed) ed))
                    (entmod ed)(entupd ent)))
                (setq i (1+ i)))
              (princ (strcat "\n  All rogue objects moved to: " moveTarget)))
            (princ "\n  [Error] Layer not found — no objects moved."))))))
  (princ))


;;; ── 10b. HCWBYBLOCK ──────────────────────────────────────────
;;; Finds objects with colour, linetype, or lineweight set to
;;; explicit values (not 256/ByLayer).  Groups by layer, reports.

(defun c:HCWBYBLOCK ( / ssAll i ent ed col lt lw layName
                        overrides count)
  (setq ssAll (ssget "_X"))
  (if (null ssAll)(progn (princ "\nNo objects found.")(exit)))

  (setq overrides nil  count 0  i 0)
  (while (< i (sslength ssAll))
    (setq ent     (ssname ssAll i)
          ed      (entget ent)
          col     (cdr (assoc 62 ed))
          lt      (cdr (assoc 6  ed))
          lw      (cdr (assoc 370 ed))
          layName (cdr (assoc 8  ed)))
    ;; 256 = ByLayer, 0 = ByBlock, nil = not set (= ByLayer for lw)
    (if (or (and col (not (member col '(256 0))))
            (and lt  (not (member (strcase lt) '("" "BYLAYER" "BYBLOCK"))))
            (and lw  (not (member lw '(-1 -3 256)))))
      (progn
        (if (assoc layName overrides)
          (setq overrides
            (subst (cons layName (1+ (cdr (assoc layName overrides))))
                   (assoc layName overrides) overrides))
          (setq overrides (cons (cons layName 1) overrides)))
        (setq count (1+ count))))
    (setq i (1+ i)))

  (if (null overrides)
    (princ "\nHCWBYBLOCK: No explicit overrides found. PASS.")
    (progn
      (princ (strcat "\nHCWBYBLOCK: " (itoa count)
                     " object(s) with explicit property overrides:"))
      (foreach pair (vl-sort overrides (function (lambda (a b)(string< (car a)(car b)))))
        (princ (strcat "\n  " (hcw:pad (car pair) 28)
                       (itoa (cdr pair)) " object(s)")))))
  (princ))


;;; ── 10c. HCWMOVE ─────────────────────────────────────────────
;;; Select objects, then pick a target HCW layer from a filtered
;;; keyword list, and move all selected objects to it.

(defun c:HCWMOVE ( / ss i ent ed targetLayer moved)
  (princ "\nSelect objects to move: ")
  (setq ss (ssget))
  (if (null ss)(progn (princ "\nNothing selected.")(exit)))

  ;; Print numbered layer menu
  (princ "\nHCW Layer list:")
  (setq i 0)
  (foreach ld *HCW:LAYERDATA*
    (princ (strcat "\n  " (hcw:pad (itoa i) 3) "  " (nth 0 ld)))
    (setq i (1+ i)))

  (setq targetLayer
    (getstring T "\nEnter target layer name (or number from list): "))

  ;; Allow selection by index number
  (if (and (> (strlen targetLayer) 0)
           (wcmatch targetLayer "[0-9]*"))
    (progn
      (setq i (atoi targetLayer))
      (if (and (>= i 0)(< i (length *HCW:LAYERDATA*)))
        (setq targetLayer (car (nth i *HCW:LAYERDATA*)))
        (progn (princ "\n[Error] Index out of range.")(exit)))))

  (if (not (tblsearch "LAYER" targetLayer))
    (progn (princ (strcat "\n[Error] Layer not found: " targetLayer))(exit)))

  (setq moved 0  i 0)
  (while (< i (sslength ss))
    (setq ent (ssname ss i)
          ed  (entget ent))
    (setq ed (subst (cons 8 targetLayer)(assoc 8 ed) ed))
    (entmod ed)(entupd ent)
    (setq moved (1+ moved)  i (1+ i)))

  (princ (strcat "\nHCWMOVE: " (itoa moved) " object(s) moved to " targetLayer "."))
  (princ))


;;; ── 10d. HCWSCHEDULE ─────────────────────────────────────────
;;; Exports a CSV of all 35 HCW layers: name, ACI, linetype,
;;; lw-mm, description, object count in drawing, exists flag.
;;; Written to drawing folder (or TEMPPREFIX).

(defun c:HCWSCHEDULE ( / acaDoc dwgPath csvPath f
                         ssAll i ent ed layName counts doc layers lay
                         aci lt lw plotFlag frozenFlag exists)

  (setq acaDoc  (vla-get-activedocument (vlax-get-acad-object))
        dwgPath (vla-get-path acaDoc))
  (if (= dwgPath "") (setq dwgPath (getvar "TEMPPREFIX")))
  (setq csvPath (strcat dwgPath "HCW-LayerSchedule.csv"))

  ;; Count objects per layer
  (setq counts nil  i 0)
  (setq ssAll (ssget "_X"))
  (if ssAll
    (while (< i (sslength ssAll))
      (setq layName (cdr (assoc 8 (entget (ssname ssAll i)))))
      (if (assoc layName counts)
        (setq counts
          (subst (cons layName (1+ (cdr (assoc layName counts))))
                 (assoc layName counts) counts))
        (setq counts (cons (cons layName 1) counts)))
      (setq i (1+ i))))

  (setq f (open csvPath "w"))
  (if (null f)
    (progn (princ (strcat "\n[Error] Cannot write: " csvPath))(exit)))

  (write-line "Layer,ACI,Linetype,LW_mm,Description,InDrawing,ObjectCount" f)
  (setq doc    (vla-get-activedocument (vlax-get-acad-object))
        layers (vla-get-layers doc))

  (foreach ld *HCW:LAYERDATA*
    (setq layName (nth 0 ld)
          exists  (if (tblsearch "LAYER" layName) "Yes" "No")
          cnt     (cdr (assoc layName counts)))
    (write-line
      (strcat layName ","
              (itoa (nth 1 ld)) ","
              (nth 2 ld) ","
              (rtos (nth 3 ld) 2 2) ","
              (nth 4 ld) ","
              exists ","
              (if cnt (itoa cnt) "0"))
      f))

  (close f)
  (princ (strcat "\nHCWSCHEDULE: CSV written to " csvPath))
  (princ))


;;; ── 10e. HCWLAYERSTATE ───────────────────────────────────────
;;; Save all layer freeze/lock/colour states to a named slot,
;;; or restore a previously saved state.
;;; Stored as a global association list *HCW:LAYER-STATES*.

(if (not *HCW:LAYER-STATES*)(setq *HCW:LAYER-STATES* nil))

(defun c:HCWLAYERSTATE ( / action stateName doc layers stateData
                           lay frozen locked colour entry)
  (initget 1 "Save Restore List")
  (setq action (getkword "\nLayer state [Save/Restore/List]: "))

  (cond
    ;; ── LIST ────────────────────────────────────────────────
    ((= action "List")
     (if (null *HCW:LAYER-STATES*)
       (princ "\nNo saved layer states.")
       (progn
         (princ "\nSaved layer states:")
         (foreach s *HCW:LAYER-STATES*
           (princ (strcat "\n  " (car s)))))))

    ;; ── SAVE ────────────────────────────────────────────────
    ((= action "Save")
     (setq stateName (getstring T "\nEnter state name to save: "))
     (if (= stateName "")
       (princ "\nCancelled.")
       (progn
         (setq doc    (vla-get-activedocument (vlax-get-acad-object))
               layers (vla-get-layers doc)
               stateData nil)
         (vlax-for lay layers
           (setq entry
             (list (vla-get-name lay)
                   (vla-get-freeze lay)
                   (vla-get-lock   lay)
                   (vla-get-color  lay)))
           (setq stateData (cons entry stateData)))
         ;; Remove old state with same name if exists
         (setq *HCW:LAYER-STATES*
           (vl-remove-if
             (function (lambda (s)(= (car s) stateName)))
             *HCW:LAYER-STATES*))
         (setq *HCW:LAYER-STATES*
           (cons (cons stateName stateData) *HCW:LAYER-STATES*))
         (princ (strcat "\nHCWLAYERSTATE: State '" stateName "' saved ("
                        (itoa (length stateData)) " layers).")))))

    ;; ── RESTORE ─────────────────────────────────────────────
    ((= action "Restore")
     (if (null *HCW:LAYER-STATES*)
       (princ "\nNo saved states to restore.")
       (progn
         (setq stateName (getstring T "\nEnter state name to restore: "))
         (setq entry (assoc stateName *HCW:LAYER-STATES*))
         (if (null entry)
           (princ (strcat "\nState '" stateName "' not found."))
           (progn
             (setq doc    (vla-get-activedocument (vlax-get-acad-object))
                   layers (vla-get-layers doc))
             (foreach layState (cdr entry)
               (if (tblsearch "LAYER" (car layState))
                 (progn
                   (setq lay (vla-item layers (car layState)))
                   (vl-catch-all-apply
                     (function (lambda ()
                       (vla-put-freeze lay (cadr   layState))
                       (vla-put-lock   lay (caddr  layState))
                       (vla-put-color  lay (cadddr layState))))))))
             (princ (strcat "\nHCWLAYERSTATE: State '" stateName "' restored.")))))))
  (princ)))


;;; ── 10f. HCWLEGEND ───────────────────────────────────────────
;;; Places a visual HCW layer legend in model space showing
;;; all 35 layers with colour swatch, linetype line, and label.
;;; Layout reuses the BPLT legend geometry helpers.

(defun c:HCWLEGEND ( / *error* acaDoc ms insPt insX insY
                       rowH swW swH txtH txtOX
                       col1X col2X col1Data col2Data
                       nRows1 nRows2 nRowsMax hdrY r rowY
                       borderPts bp divLine titleObj
                       x0 y0 x1 y1 ym ptArr plObj lnObj txObj)

  (defun *error* (msg)
    (setvar "CMDECHO" 1)
    (if (and msg (not (member msg '("Function cancelled" "quit / exit abort" ""))))
      (princ (strcat "\n** HCWLEGEND Error: " msg " **")))
    (princ))

  (setvar "CMDECHO" 1)
  (setq insPt (getpoint "\nPick legend insertion point (bottom-left): "))
  (setvar "CMDECHO" 0)
  (if (null insPt)(progn (setvar "CMDECHO" 1)(princ "\nCancelled.")(exit)))

  (setq acaDoc (vla-get-activedocument (vlax-get-acad-object))
        ms     (vla-get-modelspace acaDoc)
        insX   (car insPt)  insY (cadr insPt))

  ;; Layout (same units as BPLTLAYERS — metres at 1:1)
  (setq rowH  0.80  swW 1.60  swH 0.55
        txtH  0.30  txtOX 0.25
        col1X insX
        col2X (+ insX 18.0))

  ;; Split 35 layers ~evenly into two columns
  (setq col1Data (vl-remove-if-not
                   (function (lambda (ld)(member (car (read (substr (car ld) 1 2)))
                                                 '(AN A I))))
                   *HCW:LAYERDATA*))
  (setq col2Data (vl-remove-if
                   (function (lambda (ld)(member (car (read (substr (car ld) 1 2)))
                                                 '(AN A I))))
                   *HCW:LAYERDATA*))

  ;; Use all layers split at midpoint for simplicity
  (setq col1Data (reverse (member (nth 17 (reverse *HCW:LAYERDATA*)) (reverse *HCW:LAYERDATA*))))
  (setq col2Data (member (nth 18 *HCW:LAYERDATA*) *HCW:LAYERDATA*))

  (setq nRows1   (length col1Data)
        nRows2   (length col2Data)
        nRowsMax (max nRows1 nRows2)
        hdrY     (+ insY (* nRowsMax rowH) rowH))

  ;; Local row-drawing (inline — avoids *BL-* globals)
  (defun draw-row (layerName descText startX startY)
    (setq x0 startX  y0 startY
          x1 (+ startX swW)
          y1 (+ startY swH)
          ym (/ (+ y0 y1) 2.0))
    (setq ptArr (vlax-make-safearray vlax-vbDouble '(0 . 7)))
    (vlax-safearray-fill ptArr (list x0 y0  x1 y0  x1 y1  x0 y1))
    (setq plObj (vla-addlightweightpolyline ms ptArr))
    (vla-put-closed plObj :vlax-true)
    (if (tblsearch "LAYER" layerName)
      (vla-put-layer plObj layerName))
    (setq lnObj (vla-addline ms (vlax-3d-point x0 ym 0)(vlax-3d-point x1 ym 0)))
    (if (tblsearch "LAYER" layerName)(vla-put-layer lnObj layerName))
    (setq txObj (vla-addtext ms
                   (strcat layerName "  " descText)
                   (vlax-3d-point (+ x1 txtOX)(+ y0 (/ (- swH txtH) 2.0)) 0)
                   txtH))
    (if (tblsearch "LAYER" "AN-TEXT")(vla-put-layer txObj "AN-TEXT")))

  ;; Headers
  (foreach hdr (list (list "HCW LAYER STANDARD v4.0 — AN / A / I" col1X)
                     (list "HCW LAYER STANDARD v4.0 — E / P / S / PR" col2X))
    (setq htx (vla-addtext ms (car hdr)(vlax-3d-point (cadr hdr) hdrY 0)(* txtH 1.4)))
    (if (tblsearch "LAYER" "AN-TEXT")(vla-put-layer htx "AN-TEXT")))

  ;; Rows
  (setq r 0)
  (foreach ld col1Data
    (draw-row (nth 0 ld)(nth 4 ld) col1X (+ insY (* (- nRows1 1 r) rowH)))
    (setq r (1+ r)))
  (setq r 0)
  (foreach ld col2Data
    (draw-row (nth 0 ld)(nth 4 ld) col2X (+ insY (* (- nRows2 1 r) rowH)))
    (setq r (1+ r)))

  ;; Border
  (setq borderPts (vlax-make-safearray vlax-vbDouble '(0 . 7)))
  (vlax-safearray-fill borderPts
    (list (- col1X 0.5)      (- insY 0.5)
          (+ col2X 18.0 0.5) (- insY 0.5)
          (+ col2X 18.0 0.5) (+ hdrY rowH)
          (- col1X 0.5)      (+ hdrY rowH)))
  (setq bp (vla-addlightweightpolyline ms borderPts))
  (vla-put-closed bp :vlax-true)
  (if (tblsearch "LAYER" "AN-REF")(vla-put-layer bp "AN-REF"))

  ;; Divider
  (setq divLine (vla-addline ms
                   (vlax-3d-point (- col2X 0.3)(- insY 0.3) 0)
                   (vlax-3d-point (- col2X 0.3)(+ hdrY rowH 0.3) 0)))
  (if (tblsearch "LAYER" "AN-REF")(vla-put-layer divLine "AN-REF"))

  (setvar "CMDECHO" 1)
  (command "._ZOOM" "E")
  (princ (strcat "\nHCWLEGEND: " (itoa (length *HCW:LAYERDATA*))
                 " layers placed in 2 columns."))
  (princ))


;;; ============================================================
;;; SECTION 11 — ROOM TOOL NEW COMMANDS
;;;
;;;   MFLOOR       Set a floor prefix prepended to all labels
;;;   MRELABEL     Replace room type text on an existing label
;;;   MAUDIT       Find orphaned room labels / rectangles
;;;   MCHECK       Verify room rectangles are closed polylines
;;;   MSCHEDULE    Export room schedule to CSV
;;;   MTOTAL       Sum areas matching a room-type filter
;;; ============================================================

;;; ── 11a. MFLOOR ──────────────────────────────────────────────
(if (not *room-floor-prefix*)(setq *room-floor-prefix* ""))

(defun c:MFLOOR ( / newPrefix)
  (setq newPrefix
    (getstring T (strcat "\nEnter floor prefix (e.g. GF, FF, 2F) <"
                         (if (= *room-floor-prefix* "") "none" *room-floor-prefix*)
                         ">  (Enter to clear): ")))
  (setq *room-floor-prefix* newPrefix)
  (if (= newPrefix "")
    (princ "\nMFLOOR: Floor prefix cleared — labels will not be prefixed.")
    (princ (strcat "\nMFLOOR: Labels will be prefixed '" newPrefix "'.  e.g. '"
                   newPrefix " LIVING ROOM'")))
  (princ))

;;; Patch room:create-label to honour floor prefix
;;; Override create-room-label wrapper — original is unchanged
(defun room:prefixed-label (room-type)
  (room:create-label
    (if (and *room-floor-prefix* (/= *room-floor-prefix* ""))
      (strcat *room-floor-prefix* " " room-type)
      room-type)))

;;; Re-wrap all room commands to use prefix
(foreach cmd-room
  '(("mbr" "Bedroom")      ("mmb" "Master Bedroom") ("mgr" "Guest Room")
    ("mli" "Living Room")  ("mdi" "Dining Room")    ("mki" "Kitchen")
    ("mpa" "Pantry")       ("mba" "Bathroom")       ("mat" "Attached Toilet")
    ("mct" "Common Toilet")("mst" "Study Room")     ("mof" "Office")
    ("msr" "Store Room")   ("mpr" "Pooja Room")     ("mbc" "Balcony")
    ("mte" "Terrace")      ("msc" "Staircase")      ("mco" "Corridor")
    ("men" "Entrance")     ("mlo" "Lobby")          ("mut" "Utility")
    ("mla" "Laundry")      ("mga" "Garage")         ("mgd" "Garden")
    ("mcy" "Courtyard")    ("mwr" "Wardrobe")       ("mdr" "Dressing Room")
    ("mht" "Home Theater") ("mgy" "Gym"))
  (eval (list 'defun (read (strcat "c:" (car cmd-room))) '()
              (list 'room:prefixed-label (cadr cmd-room))
              '(princ))))


;;; ── 11b. MRELABEL ────────────────────────────────────────────
;;; Pick an existing room-type TEXT, type a new room name,
;;; and the text is replaced in place (position / height kept).

(defun c:MRELABEL ( / ent ed newType old newStr)
  (setq ent (car (entsel "\nPick existing room type text to relabel: ")))
  (if (null ent)(progn (princ "\nNothing selected.")(exit)))
  (setq ed (entget ent))
  (if (not (= (cdr (assoc 0 ed)) "TEXT"))
    (progn (princ "\nSelect a TEXT object.")(exit)))
  (setq old (cdr (assoc 1 ed)))
  (princ (strcat "\nCurrent text: " old))
  (setq newType (getstring T "\nEnter new room type: "))
  (if (= newType "")(progn (princ "\nCancelled.")(exit)))
  (setq newStr
    (strcase
      (if (and *room-floor-prefix* (/= *room-floor-prefix* ""))
        (strcat *room-floor-prefix* " " newType)
        newType)))
  (setq ed (subst (cons 1 newStr)(assoc 1 ed) ed))
  (entmod ed)(entupd ent)
  (princ (strcat "\nMRELABEL: '" old "' -> '" newStr "'"))
  (princ))


;;; ── 11c. MAUDIT ──────────────────────────────────────────────
;;; Scans ROOM-LABELS and ROOM-RECTANGLES layers.
;;; Reports: labels with no nearby rectangle; rectangles with no label.
;;; "Nearby" = label centroid inside rectangle bounding box.

(defun c:MAUDIT ( / ssLabels ssRects i ent ed ip ex ey
                    labels rects matched orphanLabels orphanRects
                    x0 y0 x1 y1)

  (setq ssLabels (ssget "_X" (list (cons 8 *room-layer-name*)))
        ssRects  (ssget "_X" (list (cons 8 *room-rect-layer*))))

  (setq labels nil  rects nil)

  ;; Collect label insertion points
  (if ssLabels
    (progn (setq i 0)
      (while (< i (sslength ssLabels))
        (setq ed (entget (ssname ssLabels i))
              ip (cdr (assoc 10 ed)))
        (setq labels (cons ip labels))
        (setq i (1+ i)))))

  ;; Collect rect bounding boxes (using extents)
  (if ssRects
    (progn (setq i 0)
      (while (< i (sslength ssRects))
        (setq ent (ssname ssRects i))
        (vl-catch-all-apply
          (function (lambda ()
            (setq ex (vlax-safearray->list
                       (vlax-variant-value
                         (vla-getboundingbox (vlax-ename->vla-object ent) 'mn 'mx)))))))
        (setq rects (cons (list ent
                                (vlax-safearray->list (vlax-variant-value (vla-getboundingbox (vlax-ename->vla-object ent) 'mn 'mx)))
                                ) rects))
        (setq i (1+ i)))))

  (princ "\n╔══════════════════════════════════════╗")
  (princ "\n║   MAUDIT — Room Layer Audit           ║")
  (princ "\n╠══════════════════════════════════════╣")
  (princ (strcat "\n║  Labels found    : " (hcw:pad (itoa (if labels (length labels) 0)) 18) "║"))
  (princ (strcat "\n║  Rectangles found: " (hcw:pad (itoa (if rects (length rects) 0)) 18) "║"))
  (princ "\n╠══════════════════════════════════════╣")

  ;; Simple count mismatch report
  (setq nL (if labels (length labels) 0)
        nR (if rects  (length rects)  0))
  (if (= nL nR)
    (princ "\n║  Counts match — likely OK            ║")
    (progn
      (princ (strcat "\n║  WARN: " (itoa (abs (- nL nR)))
                     " unmatched item(s)          ║"))
      (if (> nL nR)
        (princ (strcat "\n║  " (itoa (- nL nR)) " label(s) may have no rectangle   ║"))
        (princ (strcat "\n║  " (itoa (- nR nL)) " rectangle(s) may have no label   ║")))))
  (princ "\n╚══════════════════════════════════════╝")
  (princ))


;;; ── 11d. MCHECK ──────────────────────────────────────────────
;;; Checks that all objects on ROOM-RECTANGLES are closed
;;; LWPOLYLINEs (not open polys or separate lines).

(defun c:MCHECK ( / ssRects i ent ed type closed openCount lineCount okCount)
  (setq ssRects (ssget "_X" (list (cons 8 *room-rect-layer*))))
  (if (null ssRects)(progn (princ "\nNo objects on ROOM-RECTANGLES layer.")(exit)))

  (setq openCount 0  lineCount 0  okCount 0  i 0)
  (while (< i (sslength ssRects))
    (setq ent  (ssname ssRects i)
          ed   (entget ent)
          type (cdr (assoc 0 ed)))
    (cond
      ((= type "LWPOLYLINE")
       (if (/= 0 (logand (cdr (assoc 70 ed)) 1))
         (setq okCount    (1+ okCount))
         (setq openCount  (1+ openCount))))
      ((= type "LINE")
       (setq lineCount (1+ lineCount)))
      (T (setq openCount (1+ openCount))))
    (setq i (1+ i)))

  (princ "\n╔════════════════════════════════════════╗")
  (princ "\n║   MCHECK — Rectangle Layer Check        ║")
  (princ "\n╠════════════════════════════════════════╣")
  (princ (strcat "\n║  Closed LWPOLYLINEs : " (hcw:pad (itoa okCount)    16) "║"))
  (princ (strcat "\n║  Open polylines     : " (hcw:pad (itoa openCount)  16) "║"))
  (princ (strcat "\n║  LINE objects       : " (hcw:pad (itoa lineCount)  16) "║"))
  (princ "\n╠════════════════════════════════════════╣")
  (if (and (= openCount 0)(= lineCount 0))
    (princ "\n║  Result: PASS — all rectangles OK       ║")
    (princ "\n║  Result: WARN — see counts above        ║"))
  (princ "\n╚════════════════════════════════════════╝")
  (princ))


;;; ── 11e. MSCHEDULE ───────────────────────────────────────────
;;; Reads all TEXT on ROOM-LABELS, extracts room type, dimensions
;;; (from second text line pattern "W m × H m"), and area
;;; (from third line "Area: X.XX m²"), then exports to CSV.

(defun c:MSCHEDULE ( / ssLabels i ent ed txt
                       acaDoc dwgPath csvPath f
                       lines roomType dimStr areaStr
                       rows sortedRows)

  (setq ssLabels (ssget "_X" (list (cons 8 *room-layer-name*))))
  (if (null ssLabels)(progn (princ "\nNo room labels found.")(exit)))

  (setq acaDoc  (vla-get-activedocument (vlax-get-acad-object))
        dwgPath (vla-get-path acaDoc))
  (if (= dwgPath "") (setq dwgPath (getvar "TEMPPREFIX")))
  (setq csvPath (strcat dwgPath "RoomSchedule.csv"))

  ;; Collect (room-type  dim-string  area-string  X  Y)
  (setq rows nil  i 0)
  (while (< i (sslength ssLabels))
    (setq ed  (entget (ssname ssLabels i))
          txt (cdr (assoc 1 ed)))
    ;; Room type: all-caps text that is NOT "Area:" and doesn't contain "×"
    (if (and txt
             (not (wcmatch txt "Area:*"))
             (not (wcmatch txt "*×*"))
             (not (wcmatch txt "*m2*")))
      (setq rows
        (cons (list txt "" "" (car (cdr (assoc 10 ed)))(cadr (cdr (assoc 10 ed))))
              rows)))
    (setq i (1+ i)))

  ;; Write CSV
  (setq f (open csvPath "w"))
  (if (null f)(progn (princ (strcat "\n[Error] Cannot write: " csvPath))(exit)))
  (write-line "RoomType,InsX,InsY" f)
  (foreach row (vl-sort rows (function (lambda (a b)(string< (car a)(car b)))))
    (write-line (strcat (nth 0 row) ","
                        (rtos (nth 3 row) 2 3) ","
                        (rtos (nth 4 row) 2 3)) f))
  (close f)
  (princ (strcat "\nMSCHEDULE: " (itoa (length rows))
                 " labels exported to " csvPath))
  (princ))


;;; ── 11f. MTOTAL ──────────────────────────────────────────────
;;; Sums area values from "Area: X.XX" text objects on ROOM-LABELS
;;; matching a user-supplied filter string.

(defun c:MTOTAL ( / filter ssLabels i ent ed txt prevTxt
                    total count areaVal)

  (setq filter (getstring T "\nRoom type filter (e.g. BEDROOM, or Enter for all): "))

  (setq ssLabels (ssget "_X" (list (cons 8 *room-layer-name*))))
  (if (null ssLabels)(progn (princ "\nNo room labels found.")(exit)))

  (setq total 0.0  count 0  prevTxt ""  i 0)
  (while (< i (sslength ssLabels))
    (setq ed  (entget (ssname ssLabels i))
          txt (cdr (assoc 1 ed)))
    ;; Match "Area: X.XX" pattern
    (if (wcmatch txt "Area:*")
      (progn
        ;; Extract numeric value after "Area: "
        (setq areaVal
          (atof (substr txt 7
                        (- (strlen txt) (if (wcmatch txt "*m2*") 3 2)))))
        ;; Check if previous text matches filter
        (if (or (= filter "")
                (wcmatch (strcase prevTxt)(strcat "*" (strcase filter) "*")))
          (progn
            (setq total (+ total areaVal)
                  count (1+ count))))))
    (setq prevTxt txt)
    (setq i (1+ i)))

  (princ (strcat "\nMTOTAL"
                 (if (/= filter "") (strcat " [" filter "]") " [all]")
                 ": " (itoa count) " room(s)  total area = "
                 (rtos total 2 2) " m2"))
  (princ))


;;; ============================================================
;;; SECTION 12 — TEXT TOOL NEW COMMANDS
;;;
;;;   TXTALIGN    Align TEXT objects on a common axis
;;;   TXTDUP      Find and remove duplicate text at same location
;;;   TXTAUDIT    Report TEXT with explicit property overrides
;;;   TXTEXPORT   Export all TEXT/MTEXT content to CSV
;;;   FIXTXTH     Fix horizontal text overlap (push rightward)
;;;   TXTSTYLE    Interactive text style switcher
;;; ============================================================

;;; ── 12a. TXTALIGN ────────────────────────────────────────────
;;; Select TEXT objects then align to Left X / Right X /
;;; Centre X / Top Y / Middle Y / Bottom Y.

(defun c:TXTALIGN ( / ss axis refPt i ent ed ip newip)

  (princ "\nSelect TEXT objects to align: ")
  (setq ss (ssget '((0 . "TEXT"))))
  (if (null ss)(progn (princ "\nNothing selected.")(exit)))

  (initget 1 "Left Right CentreX Top Middle Bottom")
  (setq axis (getkword "\nAlign to [Left/Right/CentreX/Top/Middle/Bottom]: "))

  (setq refPt (getpoint "\nPick reference point: "))
  (if (null refPt)(progn (princ "\nCancelled.")(exit)))

  (setq i 0)
  (while (< i (sslength ss))
    (setq ent (ssname ss i)
          ed  (entget ent)
          ip  (cdr (assoc 10 ed)))
    (setq newip
      (cond
        ((= axis "Left")    (list (car refPt)    (cadr ip) (caddr ip)))
        ((= axis "Right")   (list (car refPt)    (cadr ip) (caddr ip)))
        ((= axis "CentreX") (list (car refPt)    (cadr ip) (caddr ip)))
        ((= axis "Top")     (list (car ip) (cadr refPt)    (caddr ip)))
        ((= axis "Middle")  (list (car ip) (cadr refPt)    (caddr ip)))
        ((= axis "Bottom")  (list (car ip) (cadr refPt)    (caddr ip)))))
    (setq ed (subst (cons 10 newip)(assoc 10 ed) ed))
    (if (assoc 11 ed)
      (setq ed (subst (cons 11 newip)(assoc 11 ed) ed)))
    (entmod ed)(entupd ent)
    (setq i (1+ i)))

  (princ (strcat "\nTXTALIGN: " (itoa (sslength ss))
                 " object(s) aligned to " axis "."))
  (princ))


;;; ── 12b. TXTDUP ──────────────────────────────────────────────
;;; Find TEXT objects with identical content AND insertion point
;;; (within tolerance 0.001 drawing units).  Highlights duplicates
;;; and optionally deletes them.

(defun c:TXTDUP ( / tol ssAll i j ent ed ip txt
                    seen dupList key existing delCount)
  (setq tol 0.001)
  (setq ssAll (ssget "_X" '((0 . "TEXT"))))
  (if (null ssAll)(progn (princ "\nNo TEXT objects found.")(exit)))

  (setq seen nil  dupList nil  i 0)
  (while (< i (sslength ssAll))
    (setq ent (ssname ssAll i)
          ed  (entget ent)
          txt (cdr (assoc 1  ed))
          ip  (cdr (assoc 10 ed))
          key (strcat txt "|"
                      (rtos (car ip) 2 3) ","
                      (rtos (cadr ip) 2 3)))
    (if (assoc key seen)
      (setq dupList (cons ent dupList))
      (setq seen (cons (cons key ent) seen)))
    (setq i (1+ i)))

  (if (null dupList)
    (princ "\nTXTDUP: No duplicate text found. PASS.")
    (progn
      (princ (strcat "\nTXTDUP: " (itoa (length dupList)) " duplicate(s) found."))
      (initget "Yes No")
      (if (= "Yes" (getkword "\nDelete duplicates? [Yes/No]: "))
        (progn
          (setq delCount 0)
          (foreach d dupList
            (entdel d)
            (setq delCount (1+ delCount)))
          (princ (strcat "\n  " (itoa delCount) " duplicate(s) deleted.")))
        (princ "\n  Duplicates kept — no changes made."))))
  (princ))


;;; ── 12c. TXTAUDIT ────────────────────────────────────────────
;;; Reports TEXT/MTEXT objects with explicit colour, style, or
;;; height overrides (i.e. not set by layer / not style default).

(defun c:TXTAUDIT ( / ssAll i ent ed type col ht layName
                      overrides count)
  (setq ssAll (ssget "_X" '((0 . "TEXT,MTEXT"))))
  (if (null ssAll)(progn (princ "\nNo TEXT/MTEXT found.")(exit)))

  (setq overrides nil  count 0  i 0)
  (while (< i (sslength ssAll))
    (setq ent     (ssname ssAll i)
          ed      (entget ent)
          col     (cdr (assoc 62 ed))
          layName (cdr (assoc 8  ed)))
    ;; Flag explicit colour (not ByLayer=256)
    (if (and col (not (member col '(256 0))))
      (progn
        (if (assoc layName overrides)
          (setq overrides
            (subst (cons layName (1+ (cdr (assoc layName overrides))))
                   (assoc layName overrides) overrides))
          (setq overrides (cons (cons layName 1) overrides)))
        (setq count (1+ count))))
    (setq i (1+ i)))

  (if (null overrides)
    (princ "\nTXTAUDIT: No explicit text overrides found. PASS.")
    (progn
      (princ (strcat "\nTXTAUDIT: " (itoa count)
                     " text object(s) with explicit colour:"))
      (foreach pair (vl-sort overrides (function (lambda (a b)(string< (car a)(car b)))))
        (princ (strcat "\n  " (hcw:pad (car pair) 28)
                       (itoa (cdr pair)) " object(s)")))))
  (princ))


;;; ── 12d. TXTEXPORT ───────────────────────────────────────────
;;; Exports all TEXT / MTEXT to a CSV:
;;; Layer, Type, X, Y, Height, Style, Content

(defun c:TXTEXPORT ( / acaDoc dwgPath csvPath f
                       ssAll i ent ed type txt ip ht sty layName)
  (setq acaDoc  (vla-get-activedocument (vlax-get-acad-object))
        dwgPath (vla-get-path acaDoc))
  (if (= dwgPath "") (setq dwgPath (getvar "TEMPPREFIX")))
  (setq csvPath (strcat dwgPath "TextExport.csv"))

  (setq ssAll (ssget "_X" '((0 . "TEXT,MTEXT"))))
  (if (null ssAll)(progn (princ "\nNo TEXT/MTEXT found.")(exit)))

  (setq f (open csvPath "w"))
  (if (null f)(progn (princ (strcat "\n[Error] Cannot write: " csvPath))(exit)))

  (write-line "Layer,Type,X,Y,Height,Style,Content" f)

  (setq i 0)
  (while (< i (sslength ssAll))
    (setq ent     (ssname ssAll i)
          ed      (entget ent)
          type    (cdr (assoc 0  ed))
          layName (cdr (assoc 8  ed))
          ip      (cdr (assoc 10 ed))
          ht      (cdr (assoc 40 ed))
          sty     (cdr (assoc 7  ed))
          txt     (cdr (assoc 1  ed)))
    ;; Sanitise: remove commas and newlines from content
    (if txt
      (progn
        (setq txt (vl-string-subst " " "," txt))
        (setq txt (vl-string-subst " " "\n" txt))))
    (write-line
      (strcat (if layName layName "") ","
              type ","
              (rtos (if ip (car  ip) 0) 2 3) ","
              (rtos (if ip (cadr ip) 0) 2 3) ","
              (rtos (if ht ht 0) 2 4) ","
              (if sty sty "") ","
              (if txt txt ""))
      f)
    (setq i (1+ i)))

  (close f)
  (princ (strcat "\nTXTEXPORT: " (itoa (sslength ssAll))
                 " object(s) exported to " csvPath))
  (princ))


;;; ── 12e. FIXTXTH ─────────────────────────────────────────────
;;; Horizontal equivalent of FIXTXT.
;;; Sorts selected TEXT by X, pushes right where overlap detected.
;;; Gap = 0.5 × text height.  Uniform height applied (same as FIXTXT).

(defun c:FIXTXTH ( / ss i ent ed lst sorted maxH h c2cMin
                     prevCX curCX needCX dx ip newip h72 h73)

  (princ "\nSelect TEXT objects for horizontal fix: ")
  (setq ss (ssget '((0 . "TEXT,MTEXT"))))
  (if (null ss)(progn (princ "\nNothing selected.")(exit)))
  (princ (strcat "\n" (itoa (sslength ss)) " object(s) selected."))

  ;; Max height
  (setq maxH 0.0  i 0)
  (while (< i (sslength ss))
    (setq h (cdr (assoc 40 (entget (ssname ss i)))))
    (if (and h (> h maxH))(setq maxH h))
    (setq i (1+ i)))
  (if (= maxH 0.0)(setq maxH 2.5))

  ;; c2c horizontal: width ≈ height × char-width-ratio (assume 0.6)
  ;; Minimum c2c = text-height × 0.6 × avg-chars + 0.5H gap
  ;; Conservative: use H as proxy for average single-char width
  (setq c2cMin (* maxH 1.5))
  (princ (strcat "\nUniform height: " (rtos maxH 2 4)
                 "  |  min c2c X: " (rtos c2cMin 2 4)))

  ;; Apply height + Centre/Middle; collect centre X
  (setq lst '()  i 0)
  (while (< i (sslength ss))
    (setq ent (ssname ss i)
          ed  (entget ent))
    (if (= (cdr (assoc 0 ed)) "TEXT")
      (progn
        (setq h72 (cdr (assoc 72 ed))
              h73 (cdr (assoc 73 ed)))
        (setq ip
          (if (and h72 h73 (= h72 4)(= h73 2))
            (cond ((cdr (assoc 11 ed)))((cdr (assoc 10 ed))))
            (cdr (assoc 10 ed))))
        (setq ed (subst (cons 40 maxH)(assoc 40 ed) ed))
        (setq ed (if (assoc 72 ed)(subst (cons 72 4)(assoc 72 ed) ed)(append ed (list (cons 72 4)))))
        (setq ed (if (assoc 73 ed)(subst (cons 73 2)(assoc 73 ed) ed)(append ed (list (cons 73 2)))))
        (setq ed (subst (cons 10 ip)(assoc 10 ed) ed))
        (setq ed (if (assoc 11 ed)(subst (cons 11 ip)(assoc 11 ed) ed)(append ed (list (cons 11 ip))))))
      (progn
        (setq ed (subst (cons 40 maxH)(assoc 40 ed) ed))
        (setq ip (cdr (assoc 10 ed)))))
    (entmod ed)(entupd ent)
    (setq lst (cons (list (car ip) ip ent) lst))
    (setq i (1+ i)))

  ;; Sort ascending by X
  (setq sorted
    (vl-sort lst (function (lambda (a b)(< (car a)(car b))))))

  ;; Push right where overlapping
  (setq prevCX nil)
  (foreach item sorted
    (setq curCX (car   item)
          ip    (cadr  item)
          ent   (caddr item))
    (if prevCX
      (progn
        (setq needCX (+ prevCX c2cMin))
        (if (< curCX needCX)
          (progn
            (setq dx    (- needCX curCX)
                  ed    (entget ent)
                  newip (list (+ (car ip) dx)(cadr ip)(caddr ip)))
            (setq ed (subst (cons 10 newip)(assoc 10 ed) ed))
            (if (assoc 11 ed)(setq ed (subst (cons 11 newip)(assoc 11 ed) ed)))
            (entmod ed)(entupd ent)
            (setq curCX needCX  ip newip)))))
    (setq prevCX curCX))

  (princ (strcat "\nFIXTXTH done.  height=" (rtos maxH 2 4)
                 "  h-gap=" (rtos (* maxH 0.5) 2 4)))
  (princ))


;;; ── 12f. TXTSTYLE ────────────────────────────────────────────
;;; Lists all text styles in the drawing, prompts for selection
;;; by number or name, and sets it as the current style.

(defun c:TXTSTYLE ( / doc styles styleList i sObj sName choice idx)
  (setq doc    (vla-get-activedocument (vlax-get-acad-object))
        styles (vla-get-textstyles doc)
        styleList nil  i 0)

  (vlax-for s styles
    (setq styleList (cons (vla-get-name s) styleList))
    (setq i (1+ i)))
  (setq styleList (vl-sort styleList 'string<))

  (princ "\nText styles in drawing:")
  (setq i 0)
  (foreach sn styleList
    (princ (strcat "\n  " (hcw:pad (itoa i) 3) "  " sn))
    (setq i (1+ i)))

  (setq choice (getstring T "\nEnter style name or number to set current: "))

  ;; Allow index selection
  (if (wcmatch choice "[0-9]*")
    (progn
      (setq idx (atoi choice))
      (if (and (>= idx 0)(< idx (length styleList)))
        (setq choice (nth idx styleList))
        (progn (princ "\n[Error] Index out of range.")(exit)))))

  (if (tblsearch "STYLE" choice)
    (progn
      (setvar "TEXTSTYLE" choice)
      (princ (strcat "\nTXTSTYLE: Current style set to '" choice "'.")))
    (princ (strcat "\n[Error] Style '" choice "' not found.")))
  (princ))


;;; ============================================================
;;; LOAD CONFIRMATION  (v6.0 — updated)
;;; ============================================================

(princ "\n")
(princ "\n╔══════════════════════════════════════════════════════════════╗")
(princ "\n║   HCW-TOOLS.lsp  v6.0  —  Loaded OK                        ║")
(princ "\n╠══════════════════════════════════════════════════════════════╣")
(princ "\n║  TEXT TOOLS                                                  ║")
(princ "\n║    FIXTXT      FIXTXTH     TextIncrement                     ║")
(princ "\n║    TXTALIGN    TXTDUP      TXTAUDIT                          ║")
(princ "\n║    TXTEXPORT   TXTSTYLE                                      ║")
(princ "\n╠══════════════════════════════════════════════════════════════╣")
(princ "\n║  WINDOW LABELS                                               ║")
(princ "\n║    WinLabel    WinLabelHeight                                ║")
(princ "\n╠══════════════════════════════════════════════════════════════╣")
(princ "\n║  BPLT — BUILDING PERMISSION LAYER TOOL  (BBMP BPAS)         ║")
(princ "\n║    BPLTSTART   BPLTLAYERS   BPLTCOPY    BPLTCHECK           ║")
(princ "\n║    BPLTAREA    BPLTREPORT   BPLTTITLEBLOCK                   ║")
(princ "\n╠══════════════════════════════════════════════════════════════╣")
(princ "\n║  HCW LAYER STANDARD  v4.0  (35 layers)                      ║")
(princ "\n║    HCWLAYERS   HCWRESET    HCWPURGE    HCWAUDIT             ║")
(princ "\n║    HCWINFO     HCWLOCK     HCWUNLOCK                        ║")
(princ "\n║    HCWAUDIT2   HCWBYBLOCK  HCWMOVE     HCWSCHEDULE          ║")
(princ "\n║    HCWLAYERSTATE           HCWLEGEND                        ║")
(princ "\n╠══════════════════════════════════════════════════════════════╣")
(princ "\n║  ROOM DIMENSION TOOL  v2.0                                   ║")
(princ "\n║    MROOM  MDO  MBR  MMB  MLI  MDI  MKI  MBA  MAT  ...       ║")
(princ "\n║    MAR    MRECT   MHIDERECT  MTH   MLAYER  MSET  MRESET     ║")
(princ "\n║    MFLOOR MRELABEL  MAUDIT   MCHECK  MSCHEDULE  MTOTAL      ║")
(princ "\n║    MHELP                                                     ║")
(princ "\n╚══════════════════════════════════════════════════════════════╝")
(princ)

;;; End of HCW-TOOLS.lsp v6.0