# FlowBridge Design System

## Product signature

FlowBridge is a Voice OS, not a recorder dashboard. Its signature object is the
**Living Voice Field**: one horizontal membrane that invites speech, reacts to
real microphone energy, condenses while the engine works, and settles into the
transcript. The user must be able to follow one geometry through the entire
journey instead of watching an orb, a card, and a button swap places.

## Layer doctrine

- **Room:** edge-to-edge, quiet, adaptive light/dark background. Its two aurora
  knots inherit the current voice phase at very low opacity.
- **Content:** opaque or near-opaque raised surfaces. Transcript, history and
  explanatory copy never use Liquid Glass.
- **Controls:** Liquid Glass. Navigation, the action dock, transient chips and
  compact controls may use glass, preferably in one `GlassEffectContainer` so
  they merge and separate as state changes.
- **Color:** every take advances through one ordered color story: identity
  violet (ready) → voice coral (listening) → decode blue (understanding) →
  refine gold (improving) → delivered mint (useful). Orange means attention.
  The sequence is functional, never a decorative rainbow glow, and appears in
  the Field, seam, room, primary control, Lock Screen and Dynamic Island.

## Geometry and spacing

- iPhone 17 standard is the baseline canvas; horizontal content inset is 18pt.
- Spacing follows a 4/8pt rhythm. Primary values: 4, 8, 12, 16, 20, 24, 32, 40.
- Reading rows use 16pt continuous corners, cards 20pt, the Voice Field 30pt.
- Controls are at least 44x44pt. The action dock stays inside the bottom safe
  area and never covers transcript content at accessibility sizes.

## Type

- SF Pro is the working voice. New York italic is reserved for a few phrases
  that represent the user's own words.
- Moving numbers use rounded, monospaced digits.
- Body copy uses Dynamic Type and is never smaller than `footnote`; `caption2`
  is metadata only.

## Motion and haptics

- Motion explains state. At most two independent animations run at once.
- Direct manipulation responds in roughly 200-280ms. Field morphs take roughly
  480ms. Transcript settlement has almost no bounce.
- Transitions are interruptible and driven by state, never chained decorative
  delays. Haptics mark start, pause/resume, delivery and recoverable failure.
- Color, field contour and microcopy move as one phase transition; never tint a
  single isolated label and call that a state change.
- Reduce Motion removes travel, breathing and shimmer while preserving state
  through shape, text and semantic color. Reduce Transparency replaces glass
  and translucent content with opaque system surfaces.

## System surfaces

- The Dynamic Island shows one essential action per phase: finish while live,
  resume while paused, and the detected contextual action when delivered.
- Compact and minimal presentations prioritize live state and elapsed time.
- Lock Screen, widgets, Action Button and keyboard reuse the membrane glyph,
  state colors and short verbs. They do not reproduce the full app layout.

## Voice and ethics

- Copy is short, calm and useful. No streak shame, fake urgency, dark patterns,
  or engagement loops. The satisfying loop comes from immediate capture,
  visible understanding and one-tap completion of the user's intent.
