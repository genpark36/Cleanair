# Design System Strategy: The Lucid Editorial

## 1. Overview & Creative North Star
The Creative North Star for this design system is **"The Lucid Editorial."** We are moving away from the rigid, boxed-in constraints of traditional SaaS dashboards toward a layout that breathes with the intentionality of a high-end lifestyle magazine. 

By utilizing **Pretendard**, we achieve a sophisticated, modern grotesque aesthetic that offers unparalleled legibility in both Korean and English. The system breaks the "template" look through **intentional asymmetry**—using wide margins, staggered content blocks, and a dramatic typographic scale. This isn't just a functional interface; it is a curated digital space where the Teal primary accent (`#00B4D8`) acts as a guiding light through a serene, layered environment.

---

## 2. Colors: Tonal Depth & The "No-Line" Rule
Our color philosophy rejects the "table-grid" mentality. We define space through weight and light, not ink.

*   **The "No-Line" Rule:** Designers are strictly prohibited from using 1-pixel solid borders to section off content. Boundaries must be defined solely through background shifts. For example, a `surface-container-low` section should sit directly on a `surface` background to denote a change in context.
*   **Surface Hierarchy & Nesting:** Treat the UI as a series of physical layers. 
    *   **Level 0 (Base):** `surface` (#f5fafd)
    *   **Level 1 (Sectioning):** `surface-container-low` (#eff4f7)
    *   **Level 2 (Interaction/Cards):** `surface-container-lowest` (#ffffff)
    *   **Level 3 (High-Detail):** `surface-container-high` (#e3e9ec)
*   **The Glass & Gradient Rule:** For floating navigation or modal overlays, use **Glassmorphism**. Apply `surface` at 70% opacity with a `20px` backdrop-blur. 
*   **Signature Textures:** For primary CTAs, do not use a flat fill. Apply a subtle linear gradient from `primary` (#00677d) to `primary_container` (#00b4d8) at a 135-degree angle to provide a "gemstone" depth.

---

## 3. Typography: Pretendard Modernity
Pretendard is the backbone of this system. It provides a variable-width feel that makes Korean characters look balanced and authoritative.

*   **Display (Display-LG to SM):** These are your "Editorial Statements." Use `display-lg` (3.5rem) with `-0.02em` letter spacing to create high-impact hero sections.
*   **Headline & Title:** Use `headline-lg` (2rem) for section starts. Ensure there is at least `spacing-10` (3.5rem) of vertical clearance above a headline to maintain the editorial feel.
*   **Body (Body-LG to SM):** Optimized for long-form reading. `body-lg` (1rem) should be used for the majority of content, ensuring a line-height of 1.6 for maximum readability in Korean.
*   **Labels:** Use `label-md` (0.75rem) in all-caps (for English) or bold (for Korean) to denote metadata, using the `secondary` (#396472) color.

---

## 4. Elevation & Depth: Tonal Layering
Traditional drop shadows are too "heavy" for this system. We use light to create volume.

*   **The Layering Principle:** Instead of a shadow, place a `surface-container-lowest` card on top of a `surface-container` background. The slight shift in hex value creates a "natural lift."
*   **Ambient Shadows:** If a floating element (like a dropdown) requires a shadow, use a multi-layered blur: `0 8px 32px rgba(23, 28, 31, 0.04)`. The color is a tint of our `on-surface` (#171c1f), never pure black.
*   **The "Ghost Border" Fallback:** If accessibility requires a stroke, use `outline-variant` (#bcc9ce) at 20% opacity. It should be felt, not seen.
*   **Glassmorphism:** Use for persistent headers. `background: rgba(245, 250, 253, 0.8); backdrop-filter: blur(12px);`.

---

## 5. Components

*   **Buttons:** 
    *   **Primary:** Gradient fill (`primary` to `primary_container`), `rounded-full` (9999px), and `spacing-3` (1rem) horizontal padding.
    *   **Tertiary:** No background, `primary` text weight 600, with an underline that only appears on hover.
*   **Cards & Lists:** 
    *   **Strict Rule:** No dividers. Separate list items using `spacing-4` (1.4rem) of vertical white space.
    *   **Cards:** Use `rounded-lg` (1rem) for containers. Content inside should have `spacing-6` (2rem) padding to ensure the "Editorial" breathability.
*   **Input Fields:** 
    *   Use `surface-container-highest` (#dee3e6) as a subtle background fill rather than a border.
    *   Active state: A `2px` bottom-bar in `primary` (#00677d), rather than a full-box outline.
*   **Signature Component: The "Editorial Float":** An asymmetrical image/text combo where the image is slightly offset from the container grid, overlapping the background color shift.

---

## 6. Do's and Don'ts

### Do:
*   **Do** embrace negative space. If a layout feels "empty," it is likely working.
*   **Do** use `primary_fixed` (#b3ebff) for soft background highlights behind important text.
*   **Do** ensure Korean text uses "Keep All" word-break rules to prevent awkward single-character line breaks.

### Don't:
*   **Don't** use 1px solid `#CCCCCC` or similar borders. It kills the premium editorial feel.
*   **Don't** use "Default" shadows. They make the UI look like a 2014 material design clone.
*   **Don't** crowd the corners. Even with `rounded-md`, ensure content stays at least `spacing-4` away from the edge of any container.