# ========================================================================================
# DAAP MINT PREP UTILITY
# Project Confirmation UI
# ----------------------------------------------------------------------------------------
# FILE:        Package_confirm_project.py
# PURPOSE:
#   Presents a read-only confirmation screen after successful project validation.
#   This screen represents the explicit scope-lock boundary before analysis begins.
#
# DESIGN NOTES:
#   - No filesystem access occurs here.
#   - No mutation of project data.
#   - User must explicitly confirm or cancel.
#
# CHANGELOG:
#   v0.1.0  |  Initial confirmation screen implementation
# ========================================================================================

from PySide6.QtWidgets import (
    QWidget,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QHBoxLayout
)
from PySide6.QtCore import Qt


class ConfirmProjectWidget(QWidget):
    """
    ====================================================================================
    CONFIRM PROJECT WIDGET
    ====================================================================================
    Displays project metadata and requires explicit user confirmation before
    proceeding to analysis.
    ====================================================================================
    """

    def __init__(self, project_context: dict, on_confirm, on_cancel):
        super().__init__()

        self.project_context = project_context
        self.on_confirm = on_confirm
        self.on_cancel = on_cancel

        # ------------------------------
        # Header
        # ------------------------------
        header = QLabel("Confirm Project for Mint Preparation")
        header.setAlignment(Qt.AlignCenter)
        header.setStyleSheet("font-size: 18px; font-weight: bold;")

        # ------------------------------
        # Project Details (Read-Only)
        # ------------------------------
        details = QLabel(
            f"Project Name:\n  {project_context['project_name']}\n\n"
            f"Session File:\n  {project_context['session_file']}\n\n"
            f"Project Path:\n  {project_context['project_path']}\n\n"
            "Confirming will lock the project scope for analysis.\n"
            "No files will be modified."
        )
        details.setAlignment(Qt.AlignLeft)
        details.setWordWrap(True)
        details.setStyleSheet("font-size: 13px; padding: 10px;")

        # ------------------------------
        # Action Buttons
        # ------------------------------
        confirm_btn = QPushButton("Confirm & Continue")
        cancel_btn = QPushButton("Cancel / Choose Different Project")

        confirm_btn.clicked.connect(self.on_confirm)
        cancel_btn.clicked.connect(self.on_cancel)

        button_row = QHBoxLayout()
        button_row.addStretch()
        button_row.addWidget(confirm_btn)
        button_row.addWidget(cancel_btn)

        # ------------------------------
        # Layout Assembly
        # ------------------------------
        layout = QVBoxLayout(self)
        layout.addWidget(header)
        layout.addSpacing(20)
        layout.addWidget(details)
        layout.addStretch()
        layout.addLayout(button_row)

