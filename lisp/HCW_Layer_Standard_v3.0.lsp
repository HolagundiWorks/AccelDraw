(defun c:VHLAYERS (/ layerList makeLayer)

  (defun makeLayer (name color ltype lw plot)
    (if (not (tblsearch "LAYER" name))
      (command "-LAYER" "M" name "C" color name "LT" ltype name "LW" lw name "P" plot name "")
      (command "-LAYER" "C" color name "LT" ltype name "LW" lw name "P" plot name "")
    )
  )

  ;; Load linetypes
  (command "-LINETYPE" "LOAD" "CENTER" "acad.lin" "")
  (command "-LINETYPE" "LOAD" "DASHED" "acad.lin" "")
  (command "-LINETYPE" "LOAD" "HIDDEN" "acad.lin" "")

  (setq layerList
    '(
      ;; ARCHITECTURE
      ("A_WALL_CUT" "7" "Continuous" "0.50" "Plot")
      ("A_WALL_LOW" "8" "Continuous" "0.25" "Plot")
      ("A_WALL_EXIST" "9" "Continuous" "0.18" "Plot")
      ("A_WALL_DEMO" "1" "DASHED" "0.18" "Plot")
      ("A_WALL_BEYOND" "8" "HIDDEN" "0.13" "Plot")
      ("A_DOOR" "3" "Continuous" "0.25" "Plot")
      ("A_WINDOW" "4" "Continuous" "0.18" "Plot")
      ("A_GLASS" "151" "Continuous" "0.13" "Plot")
      ("A_STAIRS" "2" "Continuous" "0.25" "Plot")
      ("A_RAILING" "8" "Continuous" "0.18" "Plot")
      ("A_FLOOR_PATTERN" "254" "Continuous" "0.09" "Plot")
      ("A_CEILING" "253" "Continuous" "0.09" "Plot")
      ("A_FURNITURE" "30" "Continuous" "0.13" "Plot")
      ("A_JOINERY" "32" "Continuous" "0.18" "Plot")
      ("A_SANITARY" "140" "Continuous" "0.18" "Plot")
      ("A_HATCH_CUT" "250" "Continuous" "0.09" "Plot")
      ("A_HATCH_SURFACE" "253" "Continuous" "0.05" "Plot")
      ("A_SITE" "7" "Continuous" "0.35" "Plot")
      ("A_SETBACK" "1" "DASHED" "0.13" "Plot")
      ("A_PARKING" "6" "Continuous" "0.18" "Plot")
      ("A_LANDSCAPE" "94" "Continuous" "0.13" "Plot")
      ("A_VAASTU" "210" "DASHED" "0.09" "Plot")
      ("A_FSI_FAR" "5" "Continuous" "0.13" "Plot")
      ("A_RAINWATER" "150" "Continuous" "0.18" "Plot")
      ("A_SEPTIC_STP" "145" "Continuous" "0.18" "Plot")
      ("A_SUMP_OHT" "141" "Continuous" "0.18" "Plot")
      ("A_SERVICES_SHAFT" "6" "Continuous" "0.18" "Plot")
      ("A_SECURITY" "1" "Continuous" "0.18" "Plot")
      ("A_SIGNAGE" "30" "Continuous" "0.18" "Plot")

      ;; STRUCTURE
      ("S_COLUMN" "7" "Continuous" "0.50" "Plot")
      ("S_BEAM" "8" "Continuous" "0.35" "Plot")
      ("S_SLAB" "9" "Continuous" "0.25" "Plot")
      ("S_FOOTING" "30" "Continuous" "0.35" "Plot")
      ("S_REBAR" "1" "Continuous" "0.18" "Plot")
      ("S_GRID" "2" "CENTER" "0.13" "Plot")
      ("S_LEVEL" "6" "Continuous" "0.13" "Plot")

      ;; ELECTRICAL
      ("E_LIGHT" "2" "Continuous" "0.18" "Plot")
      ("E_SWITCH" "40" "Continuous" "0.13" "Plot")
      ("E_POWER" "30" "Continuous" "0.18" "Plot")
      ("E_CONDUIT" "2" "DASHED" "0.13" "Plot")

      ;; PLUMBING / FIRE / HVAC
      ("P_WATER_SUPPLY" "5" "Continuous" "0.18" "Plot")
      ("P_DRAINAGE" "4" "DASHED" "0.18" "Plot")
      ("P_FIXTURE" "140" "Continuous" "0.18" "Plot")
      ("F_FIRE" "1" "Continuous" "0.25" "Plot")
      ("H_HVAC" "151" "Continuous" "0.18" "Plot")
      ("H_DRAIN" "5" "DASHED" "0.13" "Plot")

      ;; ANNOTATION
      ("AN_DIM" "7" "Continuous" "0.13" "Plot")
      ("AN_TEXT" "7" "Continuous" "0.13" "Plot")
      ("AN_ROOM_NAME" "7" "Continuous" "0.18" "Plot")
      ("AN_LEVEL" "6" "Continuous" "0.13" "Plot")
      ("AN_TAG_DOOR" "3" "Continuous" "0.13" "Plot")
      ("AN_TAG_WINDOW" "4" "Continuous" "0.13" "Plot")
      ("AN_GRID" "2" "Continuous" "0.13" "Plot")
      ("AN_REVISION" "1" "Continuous" "0.18" "Plot")
      ("AN_AREA" "5" "Continuous" "0.13" "Plot")
      ("AN_TITLE" "7" "Continuous" "0.25" "Plot")

      ;; PRESENTATION
      ("P_SHADOW" "251" "Continuous" "0.05" "Plot")
      ("P_POCHE" "252" "Continuous" "0.09" "Plot")
      ("P_CONTEXT" "253" "Continuous" "0.05" "Plot")
      ("P_TREE" "94" "Continuous" "0.09" "Plot")
      ("P_PEOPLE" "252" "Continuous" "0.09" "Plot")
      ("P_CAR" "252" "Continuous" "0.09" "Plot")
      ("P_TEXTURE" "253" "Continuous" "0.05" "Plot")
      ("P_SCREEN" "254" "Continuous" "0.05" "Plot")

      ;; DETAIL
      ("A_DETAIL_2D" "7" "Continuous" "0.18" "Plot")
      ("A_DETAIL_3D" "8" "Continuous" "0.13" "Plot")
      ("A_WATERPROOF" "5" "Continuous" "0.18" "Plot")
      ("A_FINISH" "30" "Continuous" "0.13" "Plot")
      ("A_EXPANDED" "6" "Continuous" "0.13" "Plot")

      ;; NON-PLOT / WORKING
      ("X_GUIDE" "8" "Continuous" "0.05" "No")
      ("X_REFERENCE" "9" "Continuous" "0.05" "No")
      ("X_TRACE" "251" "Continuous" "0.05" "No")
      ("X_RENDER" "253" "Continuous" "0.05" "No")
      ("X_COORDINATION" "1" "Continuous" "0.13" "No")
      ("X_CHECK" "1" "DASHED" "0.13" "No")
    )
  )

  (foreach lay layerList
    (makeLayer
      (nth 0 lay)
      (nth 1 lay)
      (nth 2 lay)
      (nth 3 lay)
      (nth 4 lay)
    )
  )

  (command "-LAYER" "S" "A_WALL_CUT" "")
  (princ "\nVH Indian Architecture Layer Set created successfully. Command: VHLAYERS")
  (princ)
)