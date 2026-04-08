# Scanova Implementation Plan

## Phase 1: Foundation
- Create the app shell, folder structure, domain models, router, and workflow controller.
- Keep release builds free of dead-end placeholder UI once production work starts.
- Treat App Store compliance as a product constraint from the beginning.

## Phase 2: Capture and Import
- Add scan entry points with VisionKit or a custom camera path.
- Support multi-image import from Photos and PDF import from Files.
- Normalize imported assets into a single document/page representation.

## Phase 3: Intelligence
- Implement Vision OCR and per-page text storage.
- Add deterministic document type detection, entity extraction, naming, and summary generation.
- Gate Apple Intelligence integration behind availability and feature flags.

## Phase 4: Editing and Conversion
- Add reorder, delete, rotate, crop, and enhancement controls.
- Generate PDFs from page sets.
- Support merge, extract, split, remove pages, and PDF-to-images conversion.

## Phase 5: Viewer, Storage, and Recents
- Build PDF viewing, local persistence, documents library, and basic search.

## Phase 6: Premium and Monetization
- Integrate StoreKit 2 for password-protected export, advanced compression, and batch export.
- Keep core scan, OCR, export, and document operations free.

## Phase 7: Hardening
- Add unit and UI tests for the workflow, intelligence helpers, conversion flows, and entitlements.
- Validate metadata, permissions, and feature claims before release.
