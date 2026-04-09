# Scanova UX Rules

This document turns Apple Human Interface Guidelines into working rules for Scanova.

## Core Principles

1. One screen, one decision.
Each screen should help the user do one thing:
- `Capture`: bring in a document
- `Review`: confirm the scan looks right
- `Refine`: edit pages
- `Export`: create, save, or share output
- `Viewer`: inspect the final document
- `Documents`: reopen or start fresh

2. Show the next action first.
The primary action should be visible without scrolling and should be the strongest visual element on the screen.

3. Keep system language in the background.
Never surface internal wording like `analysis`, `pipeline`, `ingestion`, or `workflow` to the user. Use simple task language like:
- `Scan ready`
- `Generate PDF`
- `Save PDF`
- `Open Viewer`

4. Back always stays on the left.
Leading action placement must be consistent across the app.

5. Reduce explanation.
Users should not need paragraphs to understand what to do. If the layout is doing its job, helper copy should be minimal.

6. Use compact controls for frequent actions.
Page editing should feel like a native editor:
- gallery first
- selected page visible
- compact icon tools
- direct manipulation where possible

7. Secondary actions should not compete with the primary one.
If an action is optional, place it below, inside a menu, or style it more quietly.

8. Status should describe progress, not implementation.
Use:
- `PDF ready`
- `PDF saved`
- `Images saved`
Avoid:
- `Analysis complete`
- `Ready to analyze imported content`
- `Merged current document with duplicate copy for testing`

9. Preview before explanation.
If the user is working with a document, show the document early. Do not hide it below instructional content.

10. Every screen must answer one question immediately.
- What is this screen for?
- What can I do now?
- What happens next?

## Screen Rules

### Capture

Goal:
Let the user start fast.

Rules:
- Keep only three primary entry points: scan, photos, files.
- Do not explain the full journey here.
- If a document is already loaded, show a compact status card only.
- `Documents` should be secondary.

Good:
- `Scan, Photos, or Files.`

Avoid:
- long explanations about intake or on-device processing

### Review

Goal:
Confirm the scan result.

Rules:
- Use user-facing wording only.
- Show only:
  - name
  - summary
  - type
- No internal status language.
- The CTA should simply be `Continue`.

Good:
- `Scan ready`
- `Review the result and continue.`

Avoid:
- `Analysis complete`
- `Understanding your document`

### Refine

Goal:
Edit pages quickly.

Rules:
- Put the page gallery at the top.
- Put compact edit tools directly below the gallery.
- Show the selected page preview below the tools.
- Use icon-first controls for crop, rotate, add, delete, previous, next.
- Avoid large button stacks for editing commands.
- Keep the bottom CTA persistent.

Good layout order:
1. header
2. gallery
3. icon toolbar
4. selected page preview
5. bottom actions

Avoid:
- putting tools below the main preview
- large text-heavy tool sections

### Export

Goal:
Make the export flow obvious.

Rules:
- Export should behave like a clear 3-step path:
  - create
  - save
  - review
- The current step must be visually obvious.
- The primary action should change based on state.
- Optional tools like image export or merge should sit below the main flow.
- The user should always understand what happened after tapping the primary action.

Good:
- top status showing current step
- one primary button
- concise result state like `PDF ready` or `PDF saved`

Avoid:
- multiple equal-weight export actions at the top
- unclear transitions after tapping a button

### Viewer

Goal:
Inspect the final document and manage pages.

Rules:
- Show the document preview first.
- Show summary second.
- Show page actions clearly, but keep them secondary until needed.
- Do not insert instructional cards unless the screen is genuinely unclear without them.

Good:
- `Preview`
- `Summary`
- `Pages`

Avoid:
- extra cards explaining what preview or page selection means

### Documents

Goal:
Resume quickly.

Rules:
- Show the latest document first.
- Offer two obvious actions:
  - open current viewer
  - start new scan
- Keep copy short.

Avoid:
- long descriptions of “session state” or “library management”

## Copy Rules

Use:
- short titles
- direct verbs
- concrete outcomes

Preferred style:
- `Scan ready`
- `Generate PDF`
- `Save PDF`
- `Open Viewer`
- `Images saved`

Avoid:
- explaining implementation
- motivational filler
- repeated helper text across screens
- labels that sound like engineering status

## Interaction Rules

- Primary actions stay visible.
- Back stays on the left.
- Touch targets must remain comfortable.
- Gestures should have visible alternatives.
- Selection mode should only appear when relevant.

## Current Audit

### Working well

- bottom actions are persistent
- overflow menu is less distracting than fixed pills
- review copy is shorter
- export now has a clearer primary path than before

### Still needs improvement

1. `Review`
- status copy still needs to stay fully user-facing and calm

2. `Refine`
- toolbar should feel lighter and more native
- selected page preview should support the gallery, not dominate the screen

3. `Export`
- needs clearer feedback after each action
- primary and secondary actions should feel more distinct

4. `Viewer`
- should stay document-first and avoid teaching cards

## Decision Filter

Before adding anything to a screen, ask:

1. Does this help the user act right now?
2. If removed, would the screen become unclear?
3. Is this user language, not system language?
4. Is this the primary action, or should it be quieter?
5. Can the document itself replace this explanation?

If the answer is no, remove or demote it.

## References

- Apple Human Interface Guidelines:
  https://developer.apple.com/design/human-interface-guidelines/
- Designing for iOS:
  https://developer.apple.com/design/human-interface-guidelines/designing-for-ios
- Menus:
  https://developer.apple.com/design/human-interface-guidelines/menus
- Accessibility:
  https://developer.apple.com/design/human-interface-guidelines/accessibility
- Liquid Glass Overview:
  https://developer.apple.com/documentation/technologyoverviews/liquid-glass
