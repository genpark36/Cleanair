# Design System Document

## 1. Overview & Creative North Star
**Creative North Star: "The Atmospheric Lens"**

This design system moves beyond the utility of a standard dashboard to create an editorial, high-end experience that feels as light and clear as the air it monitors. We reject the "boxed-in" nature of traditional SaaS apps. Instead, we use **Atmospheric Layering**—a technique where hierarchy is defined by light, depth, and tonal shifts rather than rigid lines.

By leveraging intentional asymmetry, high-contrast typography scales, and "Glassmorphic" overlays, we transform raw data into a premium digital artifact. The goal is to make the user feel a sense of "breathable space" within the interface itself.

---

## 2. Colors & Tonal Architecture
The palette is rooted in a sophisticated grayscale foundation, punctuated by high-vibrancy primary tones to signal environmental health.

### Color Tokens
- **Primary (`#00677d`):** The "Oxygen" blue. Reserved for positive air quality states and main actions.
- **Secondary (`#4a626d`):** A muted, slate-blue used for supporting information and less urgent interactive elements.
- **Tertiary (`#914d00`):** An organic ochre, used sparingly for cautionary data or high-end accenting.
- **Background (`#f8fafb`):** A crisp, cool white that serves as our canvas.

### The "No-Line" Rule
**Standard 1px borders are strictly prohibited for sectioning.** 
Structure must be achieved through background shifts. For example, a global navigation bar should not have a bottom border; instead, use `surface_container_low` to sit subtly against the `surface` background.

### Surface Hierarchy & Nesting
Use the `surface_container` tiers to create a "Paper-on-Glass" effect:
1.  **Base Layer:** `surface` (The deepest background).
2.  **Sectioning:** `surface_container_low` (For grouping large content areas).
3.  **Component Level:** `surface_container_lowest` (For cards or interactive modules to "pop" forward).

### The "Glass & Gradient" Rule
To add soul to the "Minimalist" aesthetic, primary CTAs should utilize a subtle linear gradient from `primary` to `primary_container`. For floating notifications or "Quick View" modals, use a backdrop-blur (12px–20px) combined with a semi-transparent `surface_container_lowest` at 80% opacity.

---

## 3. Typography
We utilize a dual-font system to balance editorial authority with functional precision.

*   **Headlines (Manrope):** A geometric sans-serif that feels modern and expansive.
    *   **Display-LG (3.5rem):** Used for the primary Air Quality Index (AQI) number. This is our "Hero" element.
    *   **Headline-SM (1.5rem):** Used for location names or major health recommendations.
*   **Functional Labels (Inter):** A high-legibility face for technical data.
    *   **Label-MD (0.75rem):** Used for timestamps, units of measurement (µg/m³), and secondary metadata.

**Editorial Tip:** Use "Title-LG" for section headers but set them in a slightly lower opacity (using `on_surface_variant`) to let the data (in `on_surface`) take center stage.

---

## 4. Elevation & Depth
In this system, elevation is a matter of **Luminance, not Shadows.**

*   **The Layering Principle:** Depth is achieved by stacking. Place a `surface_container_highest` element on top of a `surface_dim` background to create immediate focus without a single drop shadow.
*   **Ambient Shadows:** If a floating element (like a FAB or critical Alert) requires a shadow, use a "Soft-Atmosphere" shadow: 
    *   *Blur:* 32px | *Opacity:* 6% | *Color:* Derived from `on_surface`.
*   **The "Ghost Border" Fallback:** For high-density data tables where separation is critical, use the `outline_variant` token at **15% opacity**. It should feel felt, not seen.

---

## 5. Components

### Buttons
- **Primary:** Gradient-filled (`primary` to `primary_container`), `xl` (0.75rem) roundedness. No border.
- **Secondary:** `surface_container_high` background with `on_secondary_container` text. This blends into the UI until needed.
- **States:** On hover, shift the background to `primary_fixed_dim`.

### Cards & Data Modules
**Forbid the use of divider lines.** 
To separate "PM2.5" from "Humidity" in a list, use a `6` (1.5rem) spacing gap or a subtle background shift to `surface_container_low`. Use `xl` (0.75rem) corner radius for all container elements to maintain the "Subtle Roundness" requirement.

### Input Fields
Minimalist "Underline" style or "Soft Box." If using a box, use `surface_container_highest` with no border. Upon focus, transition the background to `surface_container_lowest` and apply a `ghost-border` of the `primary` color at 40% opacity.

### Signature App Components
- **The AQI Aura:** A large, semi-transparent radial gradient behind the main AQI number that pulses slightly, using the `primary` color (when air is good) or `error` (when air is poor).
- **Atmospheric Timeline:** A vertical list of hourly forecasts where time is noted in `label-sm` and the weather/air state is represented by a soft-glow icon. Use spacing `8` (2rem) between items instead of lines.

---

## 6. Do's and Don'ts

### Do
- **Do** use whitespace as a structural element. If in doubt, increase the spacing from `4` (1rem) to `6` (1.5rem).
- **Do** use `inverse_surface` for dark-mode-style "Toast" notifications to create high-contrast urgency.
- **Do** ensure the `on_surface` text provides at least 7:1 contrast against `surface` for key air quality metrics.

### Don't
- **Don't** use pure black (#000000). Always use `on_surface` (#191c1d) for a softer, premium feel.
- **Don't** use "Default" 1px borders. They clutter the "Atmospheric" feel.
- **Don't** crowd the display. Air quality monitoring is about "clarity"—the UI must reflect that. If the screen feels full, remove a container and use a typography size shift instead.