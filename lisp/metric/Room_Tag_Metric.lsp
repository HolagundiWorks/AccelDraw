;; ========================================================================
;; ROOM DIMENSION TOOL - METRIC VERSION 2.1.0
;; v2.1.0: Fixed text centering (InsertionPoint now forced to match center),
;;         Room type list alphabetized in MROOM dialog
;; ========================================================================

;; Global variables
(setq *room-text-height* 0.15)        ; Default text height in meters
(setq *room-draw-rectangle* T)        ; Draw rectangle by default
(setq *room-layer-name* "ROOM-LABELS") ; Layer for room labels
(setq *room-rect-layer* "ROOM-RECTANGLES") ; Layer for rectangles
(setq *room-layers-created* nil)      ; Flag to track if layers were checked
(setq p1 nil p2 nil)

;; ========================================================================
;; UTILITY FUNCTIONS
;; ========================================================================

;; Create or verify layer exists
(defun create-layer (layer-name color / layer-obj)
  (vl-load-com)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq layers (vla-get-layers doc))
  
  (if (not (tblsearch "LAYER" layer-name))
    (progn
      (setq layer-obj (vla-add layers layer-name))
      (vla-put-color layer-obj color)
      (princ (strcat "\n│ Layer '" layer-name "' created."))
    )
    (princ (strcat "\n│ Layer '" layer-name "' already exists - using existing layer."))
  )
  layer-name
)

;; Get text height in drawing units with persistent default
(defun get-text-height (/ input scale)
  (setq input (getreal (strcat "\nEnter text height in meters <" (rtos *room-text-height* 2 2) ">: ")))
  (if input (setq *room-text-height* input))
  
  ;; Scale factor based on INSUNITS
  (setq scale (cond
    ((= (getvar "INSUNITS") 4) 1000.0)  ; mm to m
    ((= (getvar "INSUNITS") 5) 100.0)   ; cm to m  
    ((= (getvar "INSUNITS") 6) 1.0)     ; m to m
    (T 1000.0)                          ; default assume mm
  ))
  
  (* *room-text-height* scale)  ; Return height in drawing units
)

;; Convert drawing units to meters
(defun units-to-meters (value / scale)
  (setq scale (cond
    ((= (getvar "INSUNITS") 4) 0.001)   ; mm to m
    ((= (getvar "INSUNITS") 5) 0.01)    ; cm to m
    ((= (getvar "INSUNITS") 6) 1.0)     ; m to m
    (T 0.001)                           ; default assume mm
  ))
  (* value scale)
)

;; Format dimensions in meters
(defun format-dimensions (width height / w-m h-m)
  (setq w-m (units-to-meters width))
  (setq h-m (units-to-meters height))
  (strcat (rtos w-m 2 2) " m x " (rtos h-m 2 2) " m")
)

;; Calculate area in square meters
(defun calculate-area (width height / area-m2)
  (setq area-m2 (* (units-to-meters width) (units-to-meters height)))
  (strcat "Area: " (rtos area-m2 2 2) " m²")
)

;; Draw rectangle from two corner points
(defun draw-rectangle (pt1 pt2 layer-name / pt3 pt4 pts-list pline x1 y1 x2 y2)
  (vl-load-com)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq mspace (vla-get-modelspace doc))
  
  ;; Extract coordinates
  (setq x1 (car pt1))
  (setq y1 (cadr pt1))
  (setq x2 (car pt2))
  (setq y2 (cadr pt2))
  
  ;; Create flat list of coordinates for lightweight polyline (x,y pairs only)
  (setq pts-list (list x1 y1 x2 y1 x2 y2 x1 y2))
  
  ;; Create safearray with correct size
  (setq pts-array (vlax-make-safearray vlax-vbDouble (cons 0 (- (length pts-list) 1))))
  (vlax-safearray-fill pts-array pts-list)
  
  ;; Create polyline
  (setq pline (vla-addLightweightPolyline mspace pts-array))
  (vla-put-closed pline :vlax-true)
  (vla-put-layer pline layer-name)
  
  pline
)

;; ========================================================================
;; CORE ROOM LABELING FUNCTION
;; ========================================================================

(defun create-room-label (room-type / pt1 pt2 center width height text-height 
                          room-text dim-text area-text old-layer)
  
  ;; Ensure layers exist (check only once per session)
  (if (not *room-layers-created*)
    (progn
      (create-layer *room-layer-name* 3)      ; Color 3 = Green for text
      (create-layer *room-rect-layer* 8)      ; Color 8 = Dark Gray for rectangles
      (setq *room-layers-created* T)
    )
  )
  
  ;; Save current layer
  (setq old-layer (getvar "CLAYER"))
  
  ;; Get two corner points with error checking
  (setq pt1 (getpoint "\n│ Select FIRST corner of room: "))
  (if (not pt1) (progn (princ "\nCancelled.") (exit)))
  
  (setq pt2 (getcorner pt1 "\n│ Select OPPOSITE corner of room: "))
  (if (not pt2) (progn (princ "\nCancelled.") (exit)))
  
  ;; Store points globally
  (setq p1 pt1 p2 pt2)
  
  ;; Calculate center point and dimensions
  (setq center (list 
    (/ (+ (car pt1) (car pt2)) 2.0) 
    (/ (+ (cadr pt1) (cadr pt2)) 2.0)
    0.0
  ))
  (setq width (abs (- (car pt2) (car pt1))))
  (setq height (abs (- (cadr pt2) (cadr pt1))))
  
  ;; Get text height (only asks first time, then remembers)
  (if (not (boundp '*room-text-height-units*))
    (setq *room-text-height-units* (get-text-height))
  )
  (setq text-height *room-text-height-units*)
  
  ;; Create text strings
  (setq room-text (strcase room-type))
  (setq dim-text (format-dimensions width height))
  (setq area-text (calculate-area width height))
  
  ;; Initialize Visual LISP
  (vl-load-com)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq mspace (vla-get-modelspace doc))
  
  ;; Draw rectangle if enabled (on separate rectangle layer)
  (if *room-draw-rectangle*
    (draw-rectangle pt1 pt2 *room-rect-layer*)
  )
  
  ;; Set current layer for text
  (setvar "CLAYER" *room-layer-name*)
  
  ;; Create room type text (centered)
  (setq txt1 (vla-addtext mspace room-text (vlax-3d-point center) text-height))
  (vla-put-alignment txt1 acAlignmentMiddleCenter)
  (vla-put-textalignmentpoint txt1 (vlax-3d-point center))
  (vla-put-insertionpoint txt1 (vlax-3d-point center))
  
  ;; Create dimension text (below room text)
  (setq dim-center (list (car center) (- (cadr center) (* text-height 1.5)) 0.0))
  (setq txt2 (vla-addtext mspace dim-text (vlax-3d-point dim-center) (* text-height 0.8)))
  (vla-put-alignment txt2 acAlignmentMiddleCenter)
  (vla-put-textalignmentpoint txt2 (vlax-3d-point dim-center))
  (vla-put-insertionpoint txt2 (vlax-3d-point dim-center))
  
  ;; Create area text (below dimension text)
  (setq area-center (list (car center) (- (cadr center) (* text-height 2.8)) 0.0))
  (setq txt3 (vla-addtext mspace area-text (vlax-3d-point area-center) (* text-height 0.7)))
  (vla-put-alignment txt3 acAlignmentMiddleCenter)
  (vla-put-textalignmentpoint txt3 (vlax-3d-point area-center))
  (vla-put-insertionpoint txt3 (vlax-3d-point area-center))
  
  ;; Restore original layer
  (setvar "CLAYER" old-layer)
  
  ;; Print confirmation
  (princ "\n┌────────────────────────────────────────")
  (princ (strcat "\n│ Created: " room-text))
  (princ (strcat "\n│ Size: " dim-text))
  (princ (strcat "\n│ " area-text))
  (princ "\n└────────────────────────────────────────")
  (princ)
)

;; ========================================================================
;; ROOM TYPE COMMANDS
;; ========================================================================

;; Bedroom
(defun c:mbr () (create-room-label "Bedroom") (princ))

;; Dining Room
(defun c:mdi () (create-room-label "Dining Room") (princ))

;; Kitchen
(defun c:mki () (create-room-label "Kitchen") (princ))

;; Living Room
(defun c:mli () (create-room-label "Living Room") (princ))

;; Bathroom
(defun c:mba () (create-room-label "Bathroom") (princ))

;; Attached Toilet
(defun c:mat () (create-room-label "Attached Toilet") (princ))

;; Common Toilet
(defun c:mct () (create-room-label "Common Toilet") (princ))

;; Master Bedroom
(defun c:mmb () (create-room-label "Master Bedroom") (princ))

;; Study Room
(defun c:mst () (create-room-label "Study Room") (princ))

;; Store Room
(defun c:msr () (create-room-label "Store Room") (princ))

;; Pooja Room
(defun c:mpr () (create-room-label "Pooja Room") (princ))

;; Balcony
(defun c:mbc () (create-room-label "Balcony") (princ))

;; Terrace
(defun c:mte () (create-room-label "Terrace") (princ))

;; Staircase
(defun c:msc () (create-room-label "Staircase") (princ))

;; Corridor
(defun c:mco () (create-room-label "Corridor") (princ))

;; Entrance
(defun c:men () (create-room-label "Entrance") (princ))

;; Utility
(defun c:mut () (create-room-label "Utility") (princ))

;; Garage
(defun c:mga () (create-room-label "Garage") (princ))

;; Garden
(defun c:mgd () (create-room-label "Garden") (princ))

;; Courtyard
(defun c:mcy () (create-room-label "Courtyard") (princ))

;; Lobby
(defun c:mlo () (create-room-label "Lobby") (princ))

;; Office
(defun c:mof () (create-room-label "Office") (princ))

;; Guest Room
(defun c:mgr () (create-room-label "Guest Room") (princ))

;; Pantry
(defun c:mpa () (create-room-label "Pantry") (princ))

;; Laundry
(defun c:mla () (create-room-label "Laundry") (princ))

;; Wardrobe / Walk-in Closet
(defun c:mwr () (create-room-label "Wardrobe") (princ))

;; Dressing Room
(defun c:mdr () (create-room-label "Dressing Room") (princ))

;; Home Theater
(defun c:mht () (create-room-label "Home Theater") (princ))

;; Gym
(defun c:mgy () (create-room-label "Gym") (princ))

;; Custom Room (prompts for room type)
(defun c:mdo ( / room-type)
  (setq room-type (getstring T "\n│ Enter room type: "))
  (if (and room-type (/= room-type ""))
    (create-room-label room-type)
    (princ "\nCancelled.")
  )
  (princ)
)

;; ========================================================================
;; ROOM SELECTOR DIALOG
;; ========================================================================

;; Create DCL file for room selector
(defun create-room-selector-dcl ( / dcl-file dcl-path)
  (setq dcl-path (strcat (getvar "TEMPPREFIX") "room_selector.dcl"))
  (setq dcl-file (open dcl-path "w"))
  
  (if dcl-file
    (progn
      (write-line "room_selector : dialog {" dcl-file)
      (write-line "  label = \"Select Room Type\";" dcl-file)
      (write-line "  : boxed_column {" dcl-file)
      (write-line "    label = \"Room Types\";" dcl-file)
      (write-line "    : list_box {" dcl-file)
      (write-line "      key = \"room_list\";" dcl-file)
      (write-line "      width = 40;" dcl-file)
      (write-line "      height = 20;" dcl-file)
      (write-line "      fixed_width = true;" dcl-file)
      (write-line "      fixed_height = true;" dcl-file)
      (write-line "    }" dcl-file)
      (write-line "  }" dcl-file)
      (write-line "  : row {" dcl-file)
      (write-line "    fixed_width = true;" dcl-file)
      (write-line "    alignment = centered;" dcl-file)
      (write-line "    : button {" dcl-file)
      (write-line "      key = \"accept\";" dcl-file)
      (write-line "      label = \"OK\";" dcl-file)
      (write-line "      is_default = true;" dcl-file)
      (write-line "      width = 12;" dcl-file)
      (write-line "      fixed_width = true;" dcl-file)
      (write-line "    }" dcl-file)
      (write-line "    : button {" dcl-file)
      (write-line "      key = \"cancel\";" dcl-file)
      (write-line "      label = \"Cancel\";" dcl-file)
      (write-line "      is_cancel = true;" dcl-file)
      (write-line "      width = 12;" dcl-file)
      (write-line "      fixed_width = true;" dcl-file)
      (write-line "    }" dcl-file)
      (write-line "  }" dcl-file)
      (write-line "}" dcl-file)
      (close dcl-file)
      dcl-path
    )
    nil
  )
)

;; Master command - Show dialog to select room type
;; Room types are now listed alphabetically (A-Z), with "Custom..." pinned at the end
(defun c:mroom ( / dcl_id room-choice room-types dcl-path result selected-room custom-room)
  
  ;; Define room types list (alphabetical order)
  (setq room-types '(
    "Attached Toilet"
    "Balcony"
    "Bathroom"
    "Bedroom"
    "Common Toilet"
    "Corridor"
    "Courtyard"
    "Dining Room"
    "Dressing Room"
    "Entrance"
    "Garage"
    "Garden"
    "Guest Room"
    "Gym"
    "Home Theater"
    "Kitchen"
    "Laundry"
    "Living Room"
    "Lobby"
    "Master Bedroom"
    "Office"
    "Pantry"
    "Pooja Room"
    "Staircase"
    "Store Room"
    "Study Room"
    "Terrace"
    "Utility"
    "Wardrobe"
    "Custom..."
  ))
  
  ;; Create DCL file
  (setq dcl-path (create-room-selector-dcl))
  
  (if (not dcl-path)
    (progn
      (princ "\n│ Error: Could not create dialog file")
      (princ "\n│ Using command-line input instead...")
      (c:mdo)
      (princ)
    )
    (progn
      ;; Load dialog
      (setq dcl_id (load_dialog dcl-path))
      
      (if (not dcl_id)
        (progn
          (princ "\n│ Error: Could not load dialog")
          (princ "\n│ Using command-line input instead...")
          (c:mdo)
        )
        (progn
          (if (not (new_dialog "room_selector" dcl_id))
            (progn
              (princ "\n│ Error: Could not initialize dialog")
              (unload_dialog dcl_id)
              (princ "\n│ Using command-line input instead...")
              (c:mdo)
            )
            (progn
              ;; Populate list box with room types
              (start_list "room_list")
              (mapcar 'add_list room-types)
              (end_list)
              
              ;; Set default selection
              (set_tile "room_list" "0")
              
              ;; Action when OK is clicked
              (action_tile "accept"
                "(progn
                   (setq room-choice (atoi (get_tile \"room_list\")))
                   (done_dialog 1)
                 )"
              )
              
              ;; Action when Cancel is clicked
              (action_tile "cancel"
                "(done_dialog 0)"
              )
              
              ;; Display dialog and get result
              (setq result (start_dialog))
              
              ;; Unload dialog
              (unload_dialog dcl_id)
              
              ;; Process selection
              (if (= result 1)
                (progn
                  (setq selected-room (nth room-choice room-types))
                  
                  ;; Handle custom room type
                  (if (= selected-room "Custom...")
                    (progn
                      (setq custom-room (getstring T "\n│ Enter custom room type: "))
                      (if (and custom-room (/= custom-room ""))
                        (create-room-label custom-room)
                        (princ "\n│ Cancelled.")
                      )
                    )
                    ;; Use selected room type
                    (create-room-label selected-room)
                  )
                )
                (princ "\n│ Room selection cancelled.")
              )
            )
          )
        )
      )
    )
  )
  
  (princ)
)

;; ========================================================================
;; UTILITY AND SETTINGS COMMANDS
;; ========================================================================

;; Toggle rectangle drawing on/off
(defun c:mrect ( / )
  (setq *room-draw-rectangle* (not *room-draw-rectangle*))
  (princ (strcat "\n│ Rectangle drawing is now: " 
    (if *room-draw-rectangle* "ON" "OFF")))
  (princ)
)

;; Toggle rectangle layer visibility (freeze/thaw)
(defun c:mhiderect ( / layer-obj is-frozen)
  (vl-load-com)
  (if (tblsearch "LAYER" *room-rect-layer*)
    (progn
      (setq doc (vla-get-activedocument (vlax-get-acad-object)))
      (setq layers (vla-get-layers doc))
      (setq layer-obj (vla-item layers *room-rect-layer*))
      (setq is-frozen (= (vla-get-freeze layer-obj) :vlax-true))
      
      ;; Toggle freeze state
      (if is-frozen
        (progn
          (vla-put-freeze layer-obj :vlax-false)
          (princ (strcat "\n│ " *room-rect-layer* " layer is now VISIBLE"))
        )
        (progn
          (vla-put-freeze layer-obj :vlax-true)
          (princ (strcat "\n│ " *room-rect-layer* " layer is now HIDDEN"))
        )
      )
    )
    (princ (strcat "\n│ Layer " *room-rect-layer* " does not exist yet"))
  )
  (princ)
)

;; Change text height
(defun c:mth ( / )
  (setq *room-text-height-units* (get-text-height))
  (princ (strcat "\n│ Text height set to: " (rtos *room-text-height* 2 2) " m"))
  (princ)
)

;; Change layer name
(defun c:mlayer ( / new-layer)
  (setq new-layer (getstring T "\n│ Enter layer name for room labels: "))
  (if (and new-layer (/= new-layer ""))
    (progn
      (setq *room-layer-name* new-layer)
      (create-layer *room-layer-name* 3)
      (princ (strcat "\n│ Layer set to: " *room-layer-name*))
    )
  )
  (princ)
)

;; Show current settings
(defun c:mset ( / )
  (princ "\n╔════════════════════════════════════════╗")
  (princ "\n║   CURRENT SETTINGS                     ║")
  (princ "\n╠════════════════════════════════════════╣")
  (princ (strcat "\n║ Text Height: " (rtos *room-text-height* 2 2) " m                 "))
  (princ (strcat "\n║ Draw Rectangle: " (if *room-draw-rectangle* "YES" "NO ") "               "))
  (princ (strcat "\n║ Text Layer: " *room-layer-name* "           "))
  (princ (strcat "\n║ Rectangle Layer: " *room-rect-layer* "    "))
  (princ "\n╚════════════════════════════════════════╝")
  (princ "\n│ TIP: Freeze ROOM-RECTANGLES layer to hide boxes only")
  (princ)
)

;; Calculate area of selected polyline or rectangle
(defun c:mar ( / ent obj area area-m2 center text-height area-text)
  (setq ent (car (entsel "\n│ Select polyline or rectangle: ")))
  (if ent
    (progn
      (setq obj (vlax-ename->vla-object ent))
      
      ;; Check if it's a valid object with area
      (if (and (vlax-property-available-p obj 'Area)
               (vlax-property-available-p obj 'Centroid))
        (progn
          (setq area (vla-get-area obj))
          (setq area-m2 (units-to-meters (units-to-meters area))) ; Square meters
          (setq center (vlax-safearray->list 
            (vlax-variant-value (vla-get-centroid obj))))
          
          (setq text-height (if (boundp '*room-text-height-units*)
            *room-text-height-units*
            (get-text-height)
          ))
          
          (setq area-text (strcat "Area: " (rtos area-m2 2 2) " m²"))
          
          (vl-load-com)
          (setq doc (vla-get-activedocument (vlax-get-acad-object)))
          (setq mspace (vla-get-modelspace doc))
          
          (setq txt (vla-addtext mspace area-text (vlax-3d-point center) text-height))
          (vla-put-alignment txt acAlignmentMiddleCenter)
          (vla-put-textalignmentpoint txt (vlax-3d-point center))
          (vla-put-insertionpoint txt (vlax-3d-point center))
          (vla-put-layer txt *room-layer-name*)
          
          (princ (strcat "\n│ " area-text " label created at center"))
        )
        (princ "\n│ Selected object doesn't have area property!")
      )
    )
    (princ "\n│ No object selected")
  )
  (princ)
)

;; Reset all settings to default
(defun c:mreset ( / )
  (setq *room-text-height* 0.15)
  (setq *room-draw-rectangle* T)
  (setq *room-layer-name* "ROOM-LABELS")
  (setq *room-rect-layer* "ROOM-RECTANGLES")
  (setq *room-text-height-units* nil)
  (setq *room-layers-created* nil)
  (princ "\n│ All settings reset to default")
  (princ)
)

;; ========================================================================
;; HELP AND INFORMATION
;; ========================================================================

(defun c:mhelp ( / )
  (princ "\n╔════════════════════════════════════════════════════════════╗")
  (princ "\n║        ROOM DIMENSION TOOL - METRIC v2.1.0                 ║")
  (princ "\n╠════════════════════════════════════════════════════════════╣")
  (princ "\n║ QUICK ACCESS COMMANDS:                                     ║")
  (princ "\n║   MROOM   - Show dialog with ALL room types (A-Z, rec.)   ║")
  (princ "\n║   MDO     - Type custom room name manually                 ║")
  (princ "\n╠════════════════════════════════════════════════════════════╣")
  (princ "\n║ ROOM COMMANDS:                                             ║")
  (princ "\n║   MAT  - Attached Toilet  MLA  - Laundry                   ║")
  (princ "\n║   MBC  - Balcony          MLI  - Living Room               ║")
  (princ "\n║   MBA  - Bathroom         MLO  - Lobby                     ║")
  (princ "\n║   MBR  - Bedroom          MMB  - Master Bedroom            ║")
  (princ "\n║   MCT  - Common Toilet    MOF  - Office                    ║")
  (princ "\n║   MCO  - Corridor         MPA  - Pantry                    ║")
  (princ "\n║   MCY  - Courtyard        MPR  - Pooja Room                ║")
  (princ "\n║   MDI  - Dining Room      MSC  - Staircase                 ║")
  (princ "\n║   MDR  - Dressing Room    MSR  - Store Room                ║")
  (princ "\n║   MEN  - Entrance         MST  - Study Room                ║")
  (princ "\n║   MGA  - Garage           MTE  - Terrace                   ║")
  (princ "\n║   MGD  - Garden           MUT  - Utility                   ║")
  (princ "\n║   MGR  - Guest Room       MWR  - Wardrobe                  ║")
  (princ "\n║   MGY  - Gym              MDO  - Custom Room               ║")
  (princ "\n║   MHT  - Home Theater     MKI  - Kitchen                   ║")
  (princ "\n╠════════════════════════════════════════════════════════════╣")
  (princ "\n║ UTILITY COMMANDS:                                          ║")
  (princ "\n║   MAR       - Calculate & label area of selected polyline  ║")
  (princ "\n║   MRECT     - Toggle rectangle drawing ON/OFF              ║")
  (princ "\n║   MHIDERECT - Hide/Show rectangle layer (freeze/thaw)     ║")
  (princ "\n║   MTH       - Change text height                           ║")
  (princ "\n║   MLAYER    - Change layer name                            ║")
  (princ "\n║   MSET      - Show current settings                        ║")
  (princ "\n║   MRESET    - Reset all settings to default                ║")
  (princ "\n║   MHELP     - Show this help message                       ║")
  (princ "\n╠════════════════════════════════════════════════════════════╣")
  (princ "\n║ FEATURES:                                                  ║")
  (princ "\n║   ✓ Pick two corners → Text centered automatically         ║")
  (princ "\n║   ✓ Auto-calculates dimensions and area                    ║")
  (princ "\n║   ✓ Rectangle on separate layer (ROOM-RECTANGLES)          ║")
  (princ "\n║   ✓ Text labels on dedicated layer (ROOM-LABELS)           ║")
  (princ "\n║   ✓ Freeze rectangle layer to hide boxes only              ║")
  (princ "\n║   ✓ Persistent settings across sessions                    ║")
  (princ "\n║   ✓ Works with mm, cm, or m drawing units                  ║")
  (princ "\n║   ✓ MROOM list sorted alphabetically A-Z                   ║")
  (princ "\n╠════════════════════════════════════════════════════════════╣")
  (princ "\n║ LAYER MANAGEMENT:                                          ║")
  (princ "\n║   ROOM-LABELS      - Text labels (Green)                   ║")
  (princ "\n║   ROOM-RECTANGLES  - Room boxes (Dark Gray)                ║")
  (princ "\n║   → Freeze ROOM-RECTANGLES to hide boxes, keep labels      ║")
  (princ "\n╚════════════════════════════════════════════════════════════╝")
  (princ)
)

;; ========================================================================
;; INITIALIZATION
;; ========================================================================

(princ "\n╔════════════════════════════════════════════════════════════╗")
(princ "\n║      ROOM DIMENSION TOOL - METRIC v2.1.0 LOADED!          ║")
(princ "\n╠════════════════════════════════════════════════════════════╣")
(princ "\n║  Type MROOM to select room from A-Z dropdown list         ║")
(princ "\n║  Type MHELP for full command list and features            ║")
(princ "\n║  Quick: Pick 2 corners → Text auto-centers with area!     ║")
(princ "\n║  TIP: Use MHIDERECT to toggle rectangle visibility        ║")
(princ "\n╚════════════════════════════════════════════════════════════╝")
(princ)