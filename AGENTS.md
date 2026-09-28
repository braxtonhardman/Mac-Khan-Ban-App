# Project UI conventions

- All UI surfaces, text, borders, and controls must follow the profile’s System, Light, or Dark appearance. System follows the device; explicit Light or Dark takes precedence.
- Use adaptive system colors and semantic foreground/background styles. Do not hard-code light or dark surface colors or introduce independent appearance overrides.
- Use the profile’s selected accent for interactive emphasis. Use adaptive semantic colors for status and error indicators.
- Text editors should hide their internal scroll background so the surrounding themed surface stays uniform across the full field. Avoid overlapping background patches.

- Use `AppTypography` for all app-authored text; choose by role rather than introducing individual sizes. Use `AppSection` for grouped form headings. Keep native navigation bars, menus, and system dialogs platform-managed.
- Hierarchy: pageTitle for Workspace, board titles, and sheet titles; sectionTitle for Areas, board stages, and form sections; contextTitle for the secondary project name in an editor; itemTitle for task names and emphasized values; body for project rows, fields, and actions; supporting for descriptions and tag chips; caption for metadata and helper text. At default Mac sizing the scale is 17 / 15 / 13 / 12 / 11 points. Keep semantic styles on iPhone so Dynamic Type works.
- Review surrounding text roles together when changing typography. Change the shared scale rather than adding one-off font sizes. Icon-only controls use separate symbol styles.
