# ========================================================================================
# DAAP MINT PREP UTILITY
# Manifest Preview UI
# ----------------------------------------------------------------------------------------
# FILE:        Package_manifest_preview.py
# PURPOSE:
#   Displays a read-only preview of the generated manifest prior to mint execution.
#
# DESIGN NOTES:
#   - No edits allowed.
#   - This screen is the final verification checkpoint.
#
# CHANGELOG:
#   v0.1.0  |  Initial manifest preview screen
# ========================================================================================

from PySide6.QtWidgets import (
    QWidget,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QHBoxLayout,
    QTableWidget,
    QTableWidgetItem,
    QStyledItemDelegate,
    QStyleOptionViewItem,
    QMessageBox
)
from PySide6.QtCore import Qt


class _MediaIndentDelegate(QStyledItemDelegate):
    def __init__(self, padding_px: int, parent=None):
        super().__init__(parent)
        self._padding_px = padding_px

    def paint(self, painter, option, index):
        if index.data(Qt.UserRole) == "media":
            option = QStyleOptionViewItem(option)
            option.rect = option.rect.adjusted(self._padding_px, 0, 0, 0)
        super().paint(painter, option, index)


class ManifestPreviewWidget(QWidget):
    """
    ====================================================================================
    MANIFEST PREVIEW WIDGET
    ====================================================================================
    Presents the DAAP manifest as a read-only ledger for verification.
    ====================================================================================
    """

    def __init__(self, manifest: dict, on_approve, on_back, on_back_to_drop, on_exit):
        super().__init__()

        self.manifest = manifest
        self.on_approve = on_approve
        self.on_back = on_back
        self.on_back_to_drop = on_back_to_drop
        self.on_exit = on_exit

        # ------------------------------
        # Header
        # ------------------------------
        header = QLabel("Manifest Preview")
        header.setAlignment(Qt.AlignCenter)
        header.setStyleSheet("font-size: 18px; font-weight: bold;")

        subheader = QLabel(
            "Review the physical audio assets detected on disk.\n"
            "Musical track relationships will be resolved from the session file next."
        )
        subheader.setAlignment(Qt.AlignCenter)
        subheader.setStyleSheet("font-size: 13px;")

        blocking_issue = manifest["summary"].get("blocking_issue")
        blocking_label = None
        if blocking_issue:
            blocking_label = QLabel(blocking_issue)
            blocking_label.setAlignment(Qt.AlignCenter)
            blocking_label.setStyleSheet("color: #b00020; font-weight: bold;")
            blocking_label.setWordWrap(True)

        # ------------------------------
        # Track Table
        # ------------------------------
        table = QTableWidget()
        table.setColumnCount(3)
        table.setHorizontalHeaderLabels([
            "Asset ID",
            "Media File",
            "Manifest State"
        ])
        header_item = table.horizontalHeaderItem(2)
        header_item.setToolTip(
            "Indicates the system's Tier-1 acceptance state for this asset.\n"
            "Filesystem-based only; session usage is evaluated later."
        )
        table.setItemDelegate(_MediaIndentDelegate(72, table))
        table.setColumnWidth(2, 140)
        table.setRowCount(len(manifest["tracks"]))
        table.setEditTriggers(QTableWidget.NoEditTriggers)

        # NOTE:
        # Future Manifest State values may include:
        # - "Missing"  (file removed after scan)
        # - "Changed"  (mtime/size changed after scan)
        # These will be introduced when rescans and file watching are added.
        for row, track in enumerate(manifest["tracks"]):
            table.setItem(row, 0, QTableWidgetItem(track["track_id"]))
            media_path = track["media_file"]
            media_item = QTableWidgetItem(media_path)
            media_item.setToolTip(media_path)
            media_item.setData(Qt.TextAlignmentRole, Qt.AlignLeft | Qt.AlignVCenter)
            media_item.setData(Qt.UserRole, "media")
            table.setItem(row, 1, media_item)

            status_item = QTableWidgetItem("Accepted")
            status_item.setTextAlignment(Qt.AlignRight | Qt.AlignVCenter)
            status_item.setToolTip(
                "Present on disk and accepted into the Tier-1 manifest set."
            )
            table.setItem(row, 2, status_item)

        table.resizeColumnsToContents()

        # ------------------------------
        # Summary
        # ------------------------------
        assets_lbl = QLabel(
            f"Assets: {manifest['summary']['asset_count']}"
        )
        supported_lbl = QLabel(
            f"Supported Audio: {manifest['summary']['audio_supported']}"
        )
        unsupported_lbl = QLabel(
            f'<a href="#">Unsupported Audio: {manifest["summary"]["audio_unsupported"]}</a>'
        )
        unsupported_lbl.setTextFormat(Qt.RichText)
        unsupported_lbl.setTextInteractionFlags(Qt.TextBrowserInteraction)
        unsupported_lbl.setOpenExternalLinks(False)

        other_lbl = QLabel(
            f'<a href="#">Other Files: {manifest["summary"]["non_audio_files"]}</a>'
        )
        other_lbl.setTextFormat(Qt.RichText)
        other_lbl.setTextInteractionFlags(Qt.TextBrowserInteraction)
        other_lbl.setOpenExternalLinks(False)

        for label in (assets_lbl, supported_lbl, unsupported_lbl, other_lbl):
            label.setStyleSheet("font-size: 12px;")

        unsupported_lbl.linkActivated.connect(
            lambda _: self._show_unsupported_audio_info()
        )

        other_lbl.linkActivated.connect(
            lambda _: self._show_other_files_info()
        )

        summary_row = QHBoxLayout()
        summary_row.addStretch()
        summary_row.addWidget(assets_lbl)
        summary_row.addWidget(QLabel("|"))
        summary_row.addWidget(supported_lbl)
        summary_row.addWidget(QLabel("|"))
        summary_row.addWidget(unsupported_lbl)
        summary_row.addWidget(QLabel("|"))
        summary_row.addWidget(other_lbl)

        # ------------------------------
        # Action Buttons
        # ------------------------------
        approve_btn = QPushButton("Approve & Proceed to Mint")
        back_btn = QPushButton("Back to Analysis")
        back_to_drop_btn = QPushButton("Choose Different Project")
        exit_btn = QPushButton("Exit")

        if blocking_issue:
            approve_btn.setEnabled(False)

        approve_btn.clicked.connect(self.on_approve)
        back_btn.clicked.connect(self.on_back)
        back_to_drop_btn.clicked.connect(self.on_back_to_drop)
        exit_btn.clicked.connect(self.on_exit)

        button_row = QHBoxLayout()
        button_row.addWidget(exit_btn)
        button_row.addStretch()
        button_row.addWidget(back_to_drop_btn)
        button_row.addWidget(back_btn)
        button_row.addWidget(approve_btn)

        # ------------------------------
        # Layout Assembly
        # ------------------------------
        layout = QVBoxLayout(self)
        layout.addWidget(header)
        layout.addWidget(subheader)
        if blocking_label:
            layout.addWidget(blocking_label)
        layout.addSpacing(10)
        layout.addWidget(table)
        layout.addLayout(summary_row)
        layout.addSpacing(10)
        layout.addLayout(button_row)

    def _show_unsupported_audio_info(self):
        files = self.manifest["analysis_details"]["unsupported_audio_files"]
        formats = ", ".join(self.manifest["analysis_details"]["accepted_formats"])

        QMessageBox.information(
            self,
            "Unsupported Audio Files",
            "The following audio files were detected but are not supported for minting:\n\n"
            + "\n".join(files)
            + "\n\nAccepted formats:\n"
            + formats
        )

    def _show_other_files_info(self):
        files = self.manifest["analysis_details"]["non_audio_files"]

        QMessageBox.information(
            self,
            "Other Files Detected",
            "The following files are not audio assets and will not be included:\n\n"
            + "\n".join(files)
            + "\n\nConsider moving these files before minting."
        )

