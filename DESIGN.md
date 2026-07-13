# Orbit Design System

## Direction

Orbit is a calm, local-first macOS productivity application. Its interface uses familiar native controls, warm neutral surfaces, restrained accent color, and dense but legible working canvases. Visual effects must support state and hierarchy rather than decoration.

## Color

- Canvas light: `#F7F6F3`
- Surface light: `#FFFEFC`
- Sunken light: `#F2F0EC`
- Canvas dark: `#131211`
- Surface dark: `#1C1A18`
- Sunken dark: `#262421`
- Default accent: `#8B5CF6`
- Semantic colors: cobalt `#3D6DF2`, emerald `#10B981`, amber `#F59E0B`, rose `#F43F5E`, teal `#0EA5A8`

Accent color is reserved for the current destination, primary actions, selected graph elements, focus, and progress. Secondary text always uses the theme's tinted neutral tokens.

## Typography

Orbit uses the macOS system typeface throughout. Screen titles are 27 pt semibold, section titles are 14–17 pt semibold, interface text is 12–14 pt, and compact metadata is 10–12 pt. Prose remains below 75 characters per line.

## Geometry

- Major cards: 14 pt continuous corner radius
- Canvas nodes: 11–12 pt continuous corner radius
- Compact controls: 7–10 pt corner radius
- Standard screen inset: 32 pt
- Standard card inset: 18–22 pt
- Standard control height: 34–42 pt

## Motion

State transitions use a 180–220 ms ease-out animation. Sidebar movement, viewport reset, and selection changes communicate state only. Reduced-motion preferences must never block access to content.

## Canvas behavior

Nodes remain native SwiftUI views. Hover reveals connection ports, dragging a port creates a relationship, clicking a node opens its content or sub-workflow, and clicking an edge selects it for deletion. Grids, edges, previews, and ink use `Canvas` drawing.

## Accessibility

Use semantic buttons and labels, keyboard shortcuts, visible selected states, and color-independent labels or symbols. Interactive heatmap cells and graph ports expose useful VoiceOver labels and values.
