# Digital Audio Assets Protocol (DAAP) — Package Prep Utility

[![Version](https://img.shields.io/badge/version-1.1.0-blue)](#)
[![Language](https://img.shields.io/badge/language-Python-3776AB)](#)
[![UI](https://img.shields.io/badge/UI-PySide6-41CD52)](#)
[![Status](https://img.shields.io/badge/status-active%20prototype-success)](#)
[![Audience](https://img.shields.io/badge/audience-advanced%20operators-purple)](#)

Drag-and-drop project packaging utility for preparing a finished DAW project for DAAP authority packaging. This tool validates a project folder, builds a filesystem-authoritative Tier-1 manifest, parses session relationships in later tiers, presents discrepancy review screens, and then hands approved state into the authority packaging step. 

---

## Overview

The **DAAP Packaging Prep Utility** is the packaging-side counterpart to the in-session manifest tool.

Where the in-session utility captures structural state from inside the DAW, this application starts from the **finished project folder** and walks the operator through a controlled packaging-prep flow:

1. declare a finished project by drag-and-drop  
2. validate the folder and detect the session file  
3. confirm project scope  
4. run analysis  
5. review the Tier-1 manifest  
6. review Tier-2 discrepancies  
7. proceed to mint preparation / authority packaging

This repository is intended for **advanced technical operators**, not casual end users. The current workflow assumes a project has already been organized correctly and that the operator understands the implications of scope-lock, session/media mismatch, and packaging review.

---

## Why this exists

DAAP needs a controlled packaging layer between a finished DAW project and a formal authority package.

This utility exists to make that packaging-prep step explicit and reviewable. Instead of assuming that a project folder is clean, unambiguous, and ready, it forces a staged process:

- validate the folder
- detect the session file
- build a deterministic Tier-1 manifest from files on disk
- compare session references against project assets in later tiers
- require human acknowledgment before packaging proceeds 
The goal is not “one-click magic.” The goal is disciplined packaging.

---

## What this repo is

This repository contains the Python/PySide6 packaging-prep application for DAAP.

Current visible components include:

- Qt application bootstrap
- drag-and-drop project declaration window
- project validation logic
- supported DAW session detection
- Tier-1 filesystem manifest generation
- project confirmation screen
- analysis progress screen
- manifest preview screen
- resolution preview screen
- handoff into the authority package build logic 

---

## What this repo is not

This repo is not:

- the in-session REAPER inspection tool
- a consumer-facing “instant mint” product
- a casual uploader for unreviewed projects
- a DAW replacement
- a full rights-management system
- a get-rich-quick automation layer

It is an operator-facing packaging surface that assumes technical judgment.

---

## Features

- Drag-and-drop intake of a finished DAW project folder
- Single-folder validation with authoritative error feedback
- Detection of supported session types at project root
- Explicit project confirmation before analysis
- Tier-1 manifest generation directly from files on disk
- Read-only manifest preview before approval
- Tier-2 discrepancy review before packaging
- Acknowledgment gate before authority package build
- Success dialog showing bundle root, manifest store, and receipt output paths 
---

## Current Status

**Entry point:** `DAAP_Package_Prep_v1.py`

The current application is a PySide6 desktop utility that launches the main window and enters the Qt event loop. The entry file is intentionally minimal and acts only as the application bootstrapper. 
The main UI flow currently lives in `Package_main_window.py`, which coordinates validation, analysis, manifest preview, discrepancy review, and authority packaging handoff. 

## Getting Started

### Requirements

You need:

- Python 3.10+ recommended
- PySide6
- the expected package layout used by the repo (`ui/`, `core/`, and tiered modules referenced by imports)
- a finished DAW project folder containing exactly one supported session file at project root 
### Install

Clone or download the repository, then install dependencies in your Python environment:

```bash
pip install PySide6

If your local checkout does not already reflect the expected package layout, make sure the repository structure matches the imports used by the codebase, including ui and core modules. The visible bootstrap file imports ui.Package_main_window, and the main window delegates validation and manifest building to core modules.

Run

From the repository root:

python DAAP_Package_Prep_v1.py

This launches the Qt application and opens the main window.

Project Intake Rules

The utility is strict about intake.

Accepted input
one project folder only
Rejected input
individual files
ZIP or compressed archives
partial media folders
ambiguous multi-session folders

If more than one item is dropped, the UI returns an error asking for a single project folder only. If the dropped item is not a folder, validation fails.

Supported Session Detection

Current session detection checks the top level of the selected project root and recognizes these extensions:

.rpp — REAPER
.ptx — Pro Tools
.logicx — Logic Pro

Current behavior is intentionally narrow:

detection is top-level only
recursive or DAW-specific deep logic is planned later

The validator will fail if:

no supported session file is found
more than one session file is found
