# ========================================================================================
# DAAP MINT PREP UTILITY
# Project Declaration UI
# ----------------------------------------------------------------------------------------
# FILE:        Package_main_window.py
# PURPOSE:
#   Implements the initial "Project Declaration" screen.
#   Handles drag-and-drop of a finished DAW project folder and routes validation
#   to the core logic layer.
#
# DESIGN CONSTRAINTS:
#   - UI layer performs NO filesystem inspection directly.
#   - All validation logic is delegated to core.validator.
#   - UI reflects system state; it does not infer or guess.
#
# CHANGELOG:
#   v0.1.0  |  Initial drag-and-drop declaration screen
#   v1.1.0  |  Wired DAAP authority package export into _on_resolution_proceed()
# ========================================================================================

from PySide6.QtGui import QAction
from PySide6.QtWidgets import (
    QMainWindow,
    QWidget,
    QLabel,
    QHBoxLayout,
    QVBoxLayout,
    QPushButton,
    QMessageBox
)
from PySide6.QtCore import Qt

from core.Package_validator import validate_project_folder
from core.Package_manifest_model import build_manifest_from_filesystem
from core.tier2.reaper.tier2_controller import Tier2Controller
from DAAP_Package_Authority_Integrator_v1 import build_authority_package
from ui.Package_analysis_progress import AnalysisProgressWidget
from ui.Package_confirm_project import ConfirmProjectWidget
from ui.Package_manifest_preview import ManifestPreviewWidget
from ui.Package_resolution_preview import ResolutionPreviewWidget


class MintPrepMainWindow(QMainWindow):
    """
    ====================================================================================
    MAIN WINDOW CLASS
    ====================================================================================
    Represents the first interaction point for Mint Prep:
    - Accepts a finished project folder
    - Declares intent to prepare for minting
    - Enforces strict input validation
    ====================================================================================
    """

    def __init__(self):
        super().__init__()

        # ------------------------------
        # Window Configuration
        # ------------------------------
        self.setWindowTitle("DAAP Mint Prep Utility")
        self.setMinimumSize(720, 480)

        # ------------------------------
        # Global Exit Action
        # ------------------------------
        exit_action = QAction("Exit", self)
        exit_action.setShortcut("Ctrl+Q")
        exit_action.triggered.connect(self._on_exit_requested)

        self.addAction(exit_action)

        # Enable drag-and-drop events
        self.setAcceptDrops(True)

        # Project context container
        self.project_context = None
        self.session_skeleton = None
        self.approved_manifest = None
        self.session_map = None
        self.package_result = None

        # ------------------------------
        # Central Instruction Label
        # ------------------------------
        self.drop_label = QLabel(
            "Declare a Finished Project for Mint Preparation\n\n"
            "Drop the entire project folder below.\n\n"
            "Supported:\n"
            "  • Full DAW project folders\n\n"
            "Not Supported:\n"
            "  • Individual files\n"
            "  • ZIP or compressed archives\n"
            "  • Partial media folders"
        )

        self.drop_label.setAlignment(Qt.AlignCenter)
        self.drop_label.setStyleSheet(
            "border: 2px dashed #888;"
            "font-size: 15px;"
            "padding: 40px;"
        )

        # ------------------------------
        # Layout Setup
        # ------------------------------
        container = QWidget()
        layout = QVBoxLayout(container)
        layout.addWidget(self.drop_label)
        layout.addLayout(
            self._build_bottom_action_row(show_exit=True)
        )

        self._set_view_with_header(container)

    def _set_view_with_header(self, view_widget):
        """
        --------------------------------------------------------------------------------
        Sets the given view widget as the central view.
        --------------------------------------------------------------------------------
        """
        self.setCentralWidget(view_widget)

    def _build_bottom_action_row(
        self,
        *,
        show_exit=True,
        show_cancel=False,
        cancel_callback=None,
        extra_buttons=None
    ):
        """
        Builds a standardized bottom action row.
        """
        row = QHBoxLayout()

        if show_exit:
            exit_btn = QPushButton("Exit")
            exit_btn.clicked.connect(self._on_exit_requested)
            row.addWidget(exit_btn)

        if show_cancel:
            cancel_btn = QPushButton("Cancel")
            cancel_btn.clicked.connect(cancel_callback)
            row.addWidget(cancel_btn)

        row.addStretch()

        if extra_buttons:
            for btn in extra_buttons:
                row.addWidget(btn)

        return row

    def _reset_to_drop_screen(self):
        """
        --------------------------------------------------------------------------------
        Returns to the initial project declaration screen.
        --------------------------------------------------------------------------------
        """
        # ------------------------------
        # Central Instruction Label
        # ------------------------------
        self.drop_label = QLabel(
            "Declare a Finished Project for Mint Preparation\n\n"
            "Drop the entire project folder below.\n\n"
            "Supported:\n"
            "   Full DAW project folders\n\n"
            "Not Supported:\n"
            "   Individual files\n"
            "   ZIP or compressed archives\n"
            "   Partial media folders"
        )

        self.drop_label.setAlignment(Qt.AlignCenter)
        self.drop_label.setStyleSheet(
            "border: 2px dashed #888;"
            "font-size: 15px;"
            "padding: 40px;"
        )

        # ------------------------------
        # Layout Setup
        # ------------------------------
        container = QWidget()
        layout = QVBoxLayout(container)
        layout.addWidget(self.drop_label)
        layout.addLayout(
            self._build_bottom_action_row(show_exit=True)
        )

        self._set_view_with_header(container)

    # ====================================================================================
    # DRAG & DROP EVENT HANDLERS
    # ====================================================================================

    def dragEnterEvent(self, event):
        """
        --------------------------------------------------------------------------------
        Accepts drag events that contain URLs (files/folders).
        No validation occurs here.
        --------------------------------------------------------------------------------
        """
        if event.mimeData().hasUrls():
            event.acceptProposedAction()
        else:
            event.ignore()

    def dropEvent(self, event):
        """
        --------------------------------------------------------------------------------
        Handles drop event:
        - Enforces single-item drop
        - Delegates folder validation to core.validator
        - Displays authoritative system feedback
        --------------------------------------------------------------------------------
        """
        urls = event.mimeData().urls()

        # Enforce single-drop rule
        if len(urls) != 1:
            self._show_error(
                "Invalid Selection",
                "Please drop a single project folder only."
            )
            return

        project_path = urls[0].toLocalFile()

        # Delegate validation to core logic
        result = validate_project_folder(project_path)

        if not result["ok"]:
            self._show_error(result["title"], result["message"])
            return

        # ------------------------------
        # Store project context
        # ------------------------------
        self.project_context = {
            "project_name": result["project_name"],
            "session_file": result["session_file"],
            "project_path": project_path
        }

        # ------------------------------
        # Swap to confirmation screen
        # ------------------------------
        confirm_view = ConfirmProjectWidget(
            project_context=self.project_context,
            on_confirm=self._on_confirm_project,
            on_cancel=self._on_cancel_project
        )

        container = QWidget()
        layout = QVBoxLayout(container)
        layout.addWidget(confirm_view)
        layout.addLayout(
            self._build_bottom_action_row(show_exit=True)
        )

        self.setCentralWidget(container)

    # ====================================================================================
    # CONFIRMATION HANDLERS
    # ====================================================================================

    def _on_confirm_project(self):
        """
        --------------------------------------------------------------------------------
        User has explicitly confirmed project scope.
        Transition to analysis progress screen.
        --------------------------------------------------------------------------------
        """
        analysis_view = AnalysisProgressWidget(
            project_context=self.project_context,
            on_complete=self._on_analysis_complete,
            on_cancel=self._on_analysis_cancelled
        )

        container = QWidget()
        layout = QVBoxLayout(container)
        layout.addWidget(analysis_view)
        layout.addLayout(
            self._build_bottom_action_row(
                show_exit=True,
                show_cancel=True,
                cancel_callback=analysis_view._handle_cancel
            )
        )

        self.setCentralWidget(container)

    def _on_cancel_project(self):
        """
        --------------------------------------------------------------------------------
        User has cancelled confirmation.
        Returns to initial project declaration screen.
        --------------------------------------------------------------------------------
        """
        self.project_context = None
        self._reset_to_drop_screen()

    def _on_analysis_complete(self):
        """
        --------------------------------------------------------------------------------
        Analysis phase complete.
        Transition to manifest preview screen.
        --------------------------------------------------------------------------------
        """
        manifest = build_manifest_from_filesystem(self.project_context)
        self.approved_manifest = manifest

        preview_view = ManifestPreviewWidget(
            manifest=manifest,
            on_approve=self._on_manifest_approved,
            on_back=self._on_manifest_back,
            on_back_to_drop=self._on_back_to_drop,
            on_exit=self._on_exit_requested
        )

        self._set_view_with_header(preview_view)

    # ====================================================================================
    # MANIFEST HANDLERS
    # ====================================================================================

    def _on_manifest_approved(self):
        """
        ------------------------------------------------------------------------
        Tier-1 manifest approval → Tier-2 Phase 2.1 + 2.2 execution
        ------------------------------------------------------------------------
        """

        try:
            tier2 = Tier2Controller(
                manifest=self.approved_manifest,
                project_context=self.project_context
            )

            # Phase 2.1
            self.session_skeleton = tier2.run_phase_2_1()

            # Phase 2.2
            self.session_map = tier2.run_phase_2_2(self.session_skeleton)
            self.session_map = tier2.run_phase_2_3(self.session_map)

            print("[Tier-2 Diagnostics] Example unresolved:")
            if self.session_map["raw_unresolved_reference_paths"]:
                print(f"raw: {self.session_map['raw_unresolved_reference_paths'][0]}")
            if self.session_map["unresolved_references"]:
                print(f"diag: {self.session_map['unresolved_references'][0]}")

            print("[Tier-2 Diagnostics] Example unmapped:")
            if self.session_map["raw_unmapped_asset_ids"]:
                print(f"raw: {self.session_map['raw_unmapped_asset_ids'][0]}")
            if self.session_map["unmapped_assets"]:
                print(f"diag: {self.session_map['unmapped_assets'][0]}")

            print(
                f"[Tier-2] Parsed {self.session_skeleton['session']['track_count']} tracks | ",
                f"{len(self.session_map['unmapped_assets'])} unmapped assets | ",
                f"{len(self.session_map['unresolved_references'])} unresolved references"
            )

        except Exception as e:
            QMessageBox.critical(
                self,
                "Tier-2 Error",
                f"Tier-2 processing failed:\n\n{e}"
            )
            return

        self._show_resolution_preview()

    def _show_resolution_preview(self):
        """
        --------------------------------------------------------------------------------
        Displays the resolution preview screen.
        --------------------------------------------------------------------------------
        """
        resolution_view = ResolutionPreviewWidget(
            session_map=self.session_map,
            on_back_to_analysis=self._on_resolution_back_to_analysis,
            on_back_to_drop=self._on_resolution_back_to_drop,
            on_acknowledged_proceed=self._on_resolution_proceed
        )

        self._set_view_with_header(resolution_view)

    def _on_resolution_back_to_analysis(self):
        """
        --------------------------------------------------------------------------------
        Returns to analysis to allow project fixes and re-scan.
        --------------------------------------------------------------------------------
        """
        self.session_skeleton = None
        self.session_map = None
        self._on_manifest_back()

    def _on_resolution_back_to_drop(self):
        """
        --------------------------------------------------------------------------------
        Returns to project selection from resolution preview.
        --------------------------------------------------------------------------------
        """
        self.project_context = None
        self.approved_manifest = None
        self.session_skeleton = None
        self.session_map = None
        self._reset_to_drop_screen()

    def _on_resolution_proceed(self):
        """
        --------------------------------------------------------------------------------
        Resolution acknowledged -> Authority Packaging / Mint Preparation
        --------------------------------------------------------------------------------
        Uses the already-approved Tier-1 + Tier-2 application state to build the
        DAAP authority package.
        --------------------------------------------------------------------------------
        """

        # ------------------------------
        # Defensive state validation
        # ------------------------------
        if not self.project_context:
            QMessageBox.critical(
                self,
                "Mint Preparation Error",
                "Project context is missing. Restart the mint-prep flow."
            )
            return

        if not self.approved_manifest:
            QMessageBox.critical(
                self,
                "Mint Preparation Error",
                "Approved manifest is missing. Restart the mint-prep flow."
            )
            return

        if not self.session_skeleton:
            QMessageBox.critical(
                self,
                "Mint Preparation Error",
                "Session skeleton is missing. Tier-2 Phase 2.1 did not complete."
            )
            return

        if not self.session_map:
            QMessageBox.critical(
                self,
                "Mint Preparation Error",
                "Session map is missing. Tier-2 Phase 2.2 did not complete."
            )
            return

        # ------------------------------
        # Authority packaging
        # ------------------------------
        try:
            self.package_result = build_authority_package(
                project_context=self.project_context,
                tier1_manifest=self.approved_manifest,
                session_skeleton=self.session_skeleton,
                session_map=self.session_map,
                lua_snapshot=None
            )

        except Exception as e:
            QMessageBox.critical(
                self,
                "Mint Preparation Error",
                f"Authority packaging failed:\n\n{e}"
            )
            return

        # ------------------------------
        # Success dialog
        # ------------------------------
        QMessageBox.information(
            self,
            "Mint Preparation Complete",
            "The DAAP authority package was built successfully.\n\n"
            f"Bundle Root:\n{self.package_result.bundle_root}\n\n"
            f"Manifest Store:\n{self.package_result.manifest_store_path}\n\n"
            f"Receipt:\n{self.package_result.readable_receipt_path}\n\n"
            "Click OK to return to project selection.",
            QMessageBox.Ok
        )

        # ------------------------------
        # Reset state for next run
        # ------------------------------
        self.project_context = None
        self.approved_manifest = None
        self.session_skeleton = None
        self.session_map = None
        self.package_result = None

        self._reset_to_drop_screen()

    def _on_manifest_back(self):
        """
        --------------------------------------------------------------------------------
        User has chosen to return to analysis.
        --------------------------------------------------------------------------------
        """
        analysis_view = AnalysisProgressWidget(
            project_context=self.project_context,
            on_complete=self._on_analysis_complete,
            on_cancel=self._on_analysis_cancelled
        )
        container = QWidget()
        layout = QVBoxLayout(container)
        layout.addWidget(analysis_view)
        layout.addLayout(
            self._build_bottom_action_row(
                show_exit=True,
                show_cancel=True,
                cancel_callback=analysis_view._handle_cancel
            )
        )

        self.setCentralWidget(container)

    def _on_back_to_drop(self):
        """
        --------------------------------------------------------------------------------
        User has chosen to select a different project.
        --------------------------------------------------------------------------------
        """
        self.project_context = None
        self._reset_to_drop_screen()

    def _on_analysis_cancelled(self):
        self.project_context = None
        self._reset_to_drop_screen()

    # ====================================================================================
    # EXIT HANDLER
    # ====================================================================================

    def _on_exit_requested(self):
        """
        --------------------------------------------------------------------------------
        Handles explicit application exit request.
        --------------------------------------------------------------------------------
        """
        response = QMessageBox.question(
            self,
            "Exit DAAP Mint Prep",
            "Are you sure you want to exit?\n\n"
            "Any current analysis progress will be lost.",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No
        )

        if response == QMessageBox.Yes:
            self.close()

    # ====================================================================================
    # UI MESSAGE HELPERS
    # ====================================================================================

    def _show_error(self, title: str, message: str):
        """
        Displays a modal error dialog.
        """
        QMessageBox.critical(self, title, message)

    def _show_info(self, title: str, message: str):
        """
        Displays a modal informational dialog.
        """
        QMessageBox.information(self, title, message)
