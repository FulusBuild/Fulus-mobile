# Phase 7 — Consumer-grade polish

Phase 7 is the final interaction-quality pass over the completed Fulus business workflows. It does not add new business capabilities; it makes the existing product feel deliberate, responsive, accessible, and reliable on real phones and larger windows.

## Acceptance contract

### Motion and transitions

- Shared actions use one motion language and stay within the existing 150/220/320ms ceilings.
- Route transitions remain calm and directional rather than decorative.
- System reduced-motion settings remove non-essential scale, opacity, shimmer, and rotation animation.
- Loading and state changes preserve layout so fast local reads do not flash or jump.

### Haptics and gestures

- High-frequency primary actions provide restrained selection feedback.
- Destructive/confirmation haptics are available as explicit primitives rather than being triggered indiscriminately.
- Press states work for touch, mouse, and keyboard-focusable controls without changing business behavior.
- Gesture affordances never become the only way to discover or complete an action.

### Skeletons and perceived performance

- Skeletons are content-shaped and reserve final layout space.
- Skeleton animation stops when reduced motion is enabled.
- Delayed skeletons avoid flashing for fast local database reads.
- Indeterminate loaders have a non-animated fallback.

### Accessibility

- Interactive targets remain at least 48dp.
- Icon-only actions expose a tooltip and semantic label.
- Important action labels are not truncated solely because the system text size is large.
- Keyboard/focus traversal remains possible for supported platforms.
- Status changes communicate meaning through text/semantics, not colour alone.

### Dark mode and visual consistency

- Light/dark surfaces, borders, focus states, controls, loading states, and status treatments use the shared token system.
- No new screen introduces hard-coded light-only surfaces or text colours.
- Brand blue remains the interaction accent in both themes.

### Small and large windows

- Narrow phones avoid unnecessary horizontal gutters.
- Tablet/large-window content remains constrained and readable instead of stretching indefinitely.
- Large text is allowed to reflow; critical labels and actions must remain discoverable rather than being clipped or silently ellipsized.

### Edge states

Every production screen must have an intentional treatment for the states relevant to it:

- empty data
- loading
- error + retry
- offline
- disabled/unavailable action
- long content / large text
- dark theme
- narrow width

## Current implementation slice

This phase branch establishes the shared interaction foundation first: haptic feedback, press-state gestures, reduced-motion-aware durations, narrow-window insets, large-text-friendly button/action labels, and skeleton animation tuning. Feature screens should consume these primitives instead of creating one-off interaction behaviour.

The remaining screen-by-screen audit should use this contract as the checklist, with priority on Home → Sell → Cart → Payment → Sale complete, then Stock, Money, Reports, and More.
