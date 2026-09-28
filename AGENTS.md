# Project UI conventions

- All UI surfaces, text, borders, and controls must follow the profile’s System, Light, or Dark appearance. System follows the device; explicit Light or Dark takes precedence.
- Use adaptive system colors and semantic foreground/background styles. Do not hard-code light or dark surface colors or introduce independent appearance overrides.
- Use the profile’s selected accent for interactive emphasis. Use adaptive semantic colors for status and error indicators.
- Text editors should hide their internal scroll background so the surrounding themed surface stays uniform across the full field. Avoid overlapping background patches.

- Preserve sidebar typography hierarchy: Workspace uses title2 bold, Area headings use title3 semibold, and project rows use body regular. At default Mac sizing this is 17 / 15 / 13 points. Review related text sizes together when changing typography; parent labels must remain visually stronger than their children.
