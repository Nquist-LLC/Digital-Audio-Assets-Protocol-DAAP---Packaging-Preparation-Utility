# ========================================================================================
# DAAP MINT PREP UTILITY
# Application Entry Point
# ----------------------------------------------------------------------------------------
# FILE:        DAAP_Package_Prep_v1.py
# PURPOSE:
#   Initializes the Qt application and launches the Mint Prep main window.
#
# DESIGN NOTES:
#   - This file must remain minimal.
#   - No validation, no business logic, no filesystem operations.
#   - Acts strictly as the bootstrapper for the UI layer.
#
# CHANGELOG:
#   v0.1.0  |  Initial scaffold for DAAP Mint Prep Utility
# ========================================================================================

import sys
from PySide6.QtWidgets import QApplication
from ui.Package_main_window import MintPrepMainWindow


def main():
    """
    ------------------------------------------------------------------------------------
    MAIN APPLICATION BOOTSTRAP
    ------------------------------------------------------------------------------------
    - Instantiates QApplication
    - Creates the main window
    - Enters Qt event loop
    ------------------------------------------------------------------------------------
    """
    app = QApplication(sys.argv)

    window = MintPrepMainWindow()
    window.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()