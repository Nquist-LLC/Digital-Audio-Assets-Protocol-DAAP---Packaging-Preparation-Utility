# ========================================================================================
# DAAP MINT PREP UTILITY
# Resolution Preview UI
# ----------------------------------------------------------------------------------------
# FILE:        Package_resolution_preview.py
# PURPOSE:
#   Displays a read-only summary of Tier-2 discrepancies for user acknowledgment.
#
# DESIGN NOTES:
#   - No edits allowed.
#   - This screen is the final review checkpoint before mint preparation.
#
# CHANGELOG:
#   v0.1.0  |  Initial resolution preview screen
# ========================================================================================

from PySide6.QtWidgets import (
    QWidget,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QHBoxLayout,
    QTableWidget,
    QTableWidgetItem,
    QCheckBox
)
from PySide6.QtCore import Qt


class ResolutionPreviewWidget(QWidget):
    """
    ====================================================================================
    RESOLUTION PREVIEW WIDGET
    ====================================================================================
    Presents Tier-2 discrepancy summaries for user acknowledgment.
    ====================================================================================
    """

    def __init__(
        self,
        *,
        session_map: dict,
        on_back_to_analysis,
        on_back_to_drop,
        on_acknowledged_proceed
    ):
        super().__init__()

        self.session_map = session_map or {}
        self.on_back_to_analysis = on_back_to_analysis
        self.on_back_to_drop = on_back_to_drop
        self.on_acknowledged_proceed = on_acknowledged_proceed

        # ------------------------------
        # Header
        # ------------------------------
        header = QLabel("Session-Asset Resolution Summary")
        header.setAlignment(Qt.AlignCenter)
        header.setStyleSheet("font-size: 18px; font-weight: bold;")

        subheader = QLabel(
            "This summary shows differences between the DAW session and the project directory.\n"
            "Review carefully before proceeding."
        )
        subheader.setAlignment(Qt.AlignCenter)
        subheader.setStyleSheet("font-size: 12px;")
        subheader.setWordWrap(True)

        # ------------------------------
        # Summary Counters
        # ------------------------------
        track_count = self.session_map.get("session", {}).get("track_count", 0)
        unresolved = self.session_map.get("unresolved_references", [])
        unmapped = self.session_map.get("unmapped_assets", [])

        tracks_lbl = QLabel(f"Tracks Parsed: {track_count}")
        unresolved_lbl = QLabel(
            f"Unresolved Session References: {len(unresolved)}"
        )
        unmapped_lbl = QLabel(f"Unmapped Assets: {len(unmapped)}")

        for label in (tracks_lbl, unmapped_lbl, unresolved_lbl):
            label.setStyleSheet("font-size: 12px; font-weight: bold;")

        summary_row = QHBoxLayout()
        summary_row.addStretch()
        summary_row.addWidget(tracks_lbl)
        summary_row.addWidget(QLabel("|"))
        summary_row.addWidget(unmapped_lbl)
        summary_row.addWidget(QLabel("|"))
        summary_row.addWidget(unresolved_lbl)

        # ------------------------------
        # Unresolved References Section
        # ------------------------------
        unresolved_title = QLabel(
            "Session references that could not be resolved to project assets"
        )
        unresolved_title.setStyleSheet("font-weight: bold;")
        unresolved_title.setWordWrap(True)

        unresolved_table = QTableWidget()
        unresolved_table.setColumnCount(2)
        unresolved_table.setHorizontalHeaderLabels([
            "Source Path",
            "Reason"
        ])
        unresolved_rows = self._normalize_unresolved(unresolved)
        unresolved_table.setRowCount(len(unresolved_rows))
        unresolved_table.setEditTriggers(QTableWidget.NoEditTriggers)

        for row, (source_path, reason_code) in enumerate(unresolved_rows):
            unresolved_table.setItem(row, 0, QTableWidgetItem(source_path))
            reason_text = self._human_reason(reason_code, kind="unresolved")
            unresolved_table.setItem(row, 1, QTableWidgetItem(reason_text))

        unresolved_table.resizeColumnsToContents()

        # ------------------------------
        # Unmapped Assets Section
        # ------------------------------
        unmapped_title = QLabel("Project assets not referenced by the session")
        unmapped_title.setStyleSheet("font-weight: bold;")
        unmapped_title.setWordWrap(True)

        unmapped_table = QTableWidget()
        unmapped_table.setColumnCount(2)
        unmapped_table.setHorizontalHeaderLabels([
            "Asset ID",
            "Reason"
        ])
        unmapped_rows = self._normalize_unmapped(unmapped)
        unmapped_table.setRowCount(len(unmapped_rows))
        unmapped_table.setEditTriggers(QTableWidget.NoEditTriggers)

        for row, (asset_id, reason_code) in enumerate(unmapped_rows):
            unmapped_table.setItem(row, 0, QTableWidgetItem(asset_id))
            reason_text = self._human_reason(reason_code, kind="unmapped")
            unmapped_table.setItem(row, 1, QTableWidgetItem(reason_text))

        unmapped_table.resizeColumnsToContents()

        # ------------------------------
        # Acknowledgment
        # ------------------------------
        ack_checkbox = QCheckBox(
            "I understand the discrepancies listed above and wish to proceed."
        )

        # ------------------------------
        # Action Buttons
        # ------------------------------
        back_to_analysis_btn = QPushButton("Back to Analysis")
        back_to_drop_btn = QPushButton("Back to Drop")
        proceed_btn = QPushButton("Proceed to Mint Preparation")
        proceed_btn.setEnabled(False)

        back_to_analysis_btn.clicked.connect(self.on_back_to_analysis)
        back_to_drop_btn.clicked.connect(self.on_back_to_drop)
        proceed_btn.clicked.connect(self.on_acknowledged_proceed)

        def _toggle_proceed(_state):
            proceed_btn.setEnabled(ack_checkbox.isChecked())

        ack_checkbox.stateChanged.connect(_toggle_proceed)

        button_row = QHBoxLayout()
        button_row.addWidget(back_to_analysis_btn)
        button_row.addWidget(back_to_drop_btn)
        button_row.addStretch()
        button_row.addWidget(proceed_btn)

        # ------------------------------
        # Layout Assembly
        # ------------------------------
        layout = QVBoxLayout(self)
        layout.addWidget(header)
        layout.addWidget(subheader)
        layout.addSpacing(8)
        layout.addLayout(summary_row)
        layout.addSpacing(12)
        layout.addWidget(unresolved_title)
        layout.addWidget(unresolved_table)
        layout.addSpacing(12)
        layout.addWidget(unmapped_title)
        layout.addWidget(unmapped_table)
        layout.addSpacing(12)
        layout.addWidget(ack_checkbox)
        layout.addLayout(button_row)

    @staticmethod
    def _normalize_unresolved(unresolved: list) -> list[tuple[str, str]]:
        rows = []
        for item in unresolved:
            if isinstance(item, dict):
                source_path = item.get("source_path", "")
                reason = item.get("reason", "file_not_in_manifest")
            else:
                source_path = str(item)
                reason = "file_not_in_manifest"
            rows.append((source_path, reason))
        return rows

    @staticmethod
    def _normalize_unmapped(unmapped: list) -> list[tuple[str, str]]:
        rows = []
        for item in unmapped:
            if isinstance(item, dict):
                asset_id = item.get("asset_id", "")
                reason = item.get(
                    "reason",
                    "present_on_disk_not_used_in_session"
                )
            else:
                asset_id = str(item)
                reason = "present_on_disk_not_used_in_session"
            rows.append((asset_id, reason))
        return rows

    @staticmethod
    def _human_reason(reason_code: str, *, kind: str) -> str:
        unresolved_map = {
            "file_not_in_manifest": (
                "Referenced by session but not found in project manifest"
            ),
            "outside_project_root": "Absolute path is outside project root",
            "ambiguous_basename": "Multiple assets share this filename",
            "invalid_path": "Path is missing or malformed"
        }

        unmapped_map = {
            "present_on_disk_not_used_in_session": (
                "Present on disk but not used by the session"
            ),
            "non_audio_or_unsupported": (
                "Present on disk but excluded by Tier-1 rules"
            )
        }

        if kind == "unresolved":
            return unresolved_map.get(reason_code, reason_code or "unknown")
        return unmapped_map.get(reason_code, reason_code or "unknown")
