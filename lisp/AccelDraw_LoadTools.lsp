;;; ============================================================
;;; AccelDraw_LoadTools.lsp
;;;
;;; Loads the HCW/AccelDraw legacy LISP toolkit. Loaded automatically
;;; by AccelDraw.Plugin on NETLOAD (see PluginEntry.cs / LegacyToolsRibbon.cs),
;;; and safe to run manually with (load "AccelDraw_LoadTools.lsp").
;;;
;;; hcwtools.lsp is a consolidated v5.0 toolkit that already contains
;;; FIXTXT, TextIncrement, WinLabel, BPLTSTART/BPLTLAYERS and HCWLAYERS —
;;; the older standalone files that also define those same commands
;;; (archive/Building_Permit_Layers.lsp, archive/FIXTXT.LSP, archive/label.lsp,
;;; archive/Text_Increment.lsp) are kept for reference only and NOT loaded
;;; here, to avoid silently redefining the same command twice.
;;; HCW_Layer_Standard_v3.0.lsp (VHLAYERS) predates hcwtools.lsp's HCWLAYERS
;;; and defines a different layer set under a different command name, so
;;; both are loaded.
;;; ============================================================

(defun AccelDraw:LoadTool (relPath / dir full)
  (setq dir (if (boundp '*AccelDraw:LispDir*) *AccelDraw:LispDir* (getvar "TEMPPREFIX")))
  (setq full (strcat dir relPath))
  (if (findfile full)
    (progn (load full) T)
    (progn (princ (strcat "\n[AccelDraw] Missing LISP file: " full)) nil)))

(foreach f '("hcwtools.lsp"
             "HCW_Layer_Standard_v3.0.lsp"
             "areatxt.lsp"
             "LayerMapper.lsp"
             "metric\\PolyArea.lsp"
             "metric\\Room_Tag_Metric.lsp")
  (AccelDraw:LoadTool f))

(princ "\n[AccelDraw] Legacy LISP toolkit loaded. Type ACCELDRAW_TOOLS_HELP for a command list.")
(princ)

(defun c:ACCELDRAW_TOOLS_HELP ()
  (princ "\n============================================================")
  (princ "\nACCELDRAW LEGACY TOOLS")
  (princ "\n------------------------------------------------------------")
  (princ "\nArea & Text:")
  (princ "\n  POLYAREA        Number selected polylines + area table")
  (princ "\n  DELETEAREATEXT  Delete generated \"Area: n\" text")
  (princ "\n  FIXTXT          Fix overlapping text height/spacing")
  (princ "\n  TextIncrement   Copy text, auto-incrementing the number")
  (princ "\nRooms (Metric):")
  (princ "\n  MROOM   Room selector dialog (A-Z)      MDO   Custom room name")
  (princ "\n  MAR     Area label on selected polyline MSET  Show current settings")
  (princ "\n  MHELP   Full room-tool command list")
  (princ "\nBlocks:")
  (princ "\n  WinLabel        Label window blocks from WNAME parameter")
  (princ "\nLayers & Standards:")
  (princ "\n  VHLAYERS    VH Indian Architecture layer set")
  (princ "\n  HCWLAYERS   HCW Layer Standard v4.0 (AN/A/I/E/P/S/PR)")
  (princ "\n  BPLTSTART   Building Permission (BBMP BPAS/AutoPlan) setup")
  (princ "\n  BPLTLAYERS  Building Permission layer legend")
  (princ "\n  LAYERMAP    Map existing layers onto standard layers (dialog)")
  (princ "\n============================================================")
  (princ))
