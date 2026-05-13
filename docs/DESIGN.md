---
name: Liquid White Edition
colors:
  surface: '#fcf8f8'
  surface-dim: '#ddd9d9'
  surface-bright: '#fcf8f8'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f6f3f2'
  surface-container: '#f1edec'
  surface-container-high: '#ebe7e7'
  surface-container-highest: '#e5e2e1'
  on-surface: '#1c1b1b'
  on-surface-variant: '#444748'
  inverse-surface: '#313030'
  inverse-on-surface: '#f4f0ef'
  outline: '#747878'
  outline-variant: '#c4c7c8'
  surface-tint: '#5d5f5f'
  primary: '#5d5f5f'
  on-primary: '#ffffff'
  primary-container: '#ffffff'
  on-primary-container: '#747676'
  inverse-primary: '#c6c6c7'
  secondary: '#0058bc'
  on-secondary: '#ffffff'
  secondary-container: '#0070eb'
  on-secondary-container: '#fefcff'
  tertiary: '#5d5f5f'
  on-tertiary: '#ffffff'
  tertiary-container: '#ffffff'
  on-tertiary-container: '#747676'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#e2e2e2'
  primary-fixed-dim: '#c6c6c7'
  on-primary-fixed: '#1a1c1c'
  on-primary-fixed-variant: '#454747'
  secondary-fixed: '#d8e2ff'
  secondary-fixed-dim: '#adc6ff'
  on-secondary-fixed: '#001a41'
  on-secondary-fixed-variant: '#004493'
  tertiary-fixed: '#e2e2e2'
  tertiary-fixed-dim: '#c6c6c7'
  on-tertiary-fixed: '#1a1c1c'
  on-tertiary-fixed-variant: '#454747'
  background: '#fcf8f8'
  on-background: '#1c1b1b'
  surface-variant: '#e5e2e1'
typography:
  display-lg:
    fontFamily: Sora
    fontSize: 64px
    fontWeight: '700'
    lineHeight: '1.1'
    letterSpacing: -0.02em
  display-sm:
    fontFamily: Sora
    fontSize: 48px
    fontWeight: '700'
    lineHeight: '1.2'
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Sora
    fontSize: 32px
    fontWeight: '600'
    lineHeight: '1.3'
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Sora
    fontSize: 28px
    fontWeight: '600'
    lineHeight: '1.3'
  headline-md:
    fontFamily: Sora
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.4'
  body-lg:
    fontFamily: Sora
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.6'
  body-md:
    fontFamily: Sora
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.6'
  label-md:
    fontFamily: Sora
    fontSize: 14px
    fontWeight: '600'
    lineHeight: '1.2'
    letterSpacing: 0.05em
  label-sm:
    fontFamily: Sora
    fontSize: 12px
    fontWeight: '500'
    lineHeight: '1.2'
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  unit: 8px
  container-max: 1440px
  gutter: 24px
  margin-desktop: 80px
  margin-tablet: 40px
  margin-mobile: 20px
---

## Brand & Style

This design system embodies a "Liquid White" aesthetic—a premium, high-fidelity direction that merges extreme minimalism with futuristic glassmorphism. The brand personality is ethereal, professional, and technologically advanced, targeting high-end SaaS, creative studios, and innovative fintech platforms. 

The visual language focuses on the interplay of light and transparency. By treating the UI as a series of ultra-clear glass panes suspended in a bright, airy environment, the system evokes a sense of weightlessness and clarity. It avoids heavy outlines and dark shadows, instead using "white-on-white" depth cues and multi-layered background blurs to define hierarchy. The emotional response should be one of calm, precision, and limitless possibility.

## Colors

The palette is monochromatic and high-key, driven by **Pure White (#FFFFFF)**. The background is not a flat white but a very subtle, cool-tinted off-white to allow pure white glass elements to "pop" through luminosity rather than darkness.

- **Primary Base:** #FFFFFF is used for the most elevated glass surfaces and light sources.
- **Electric Blue:** #007AFF is the sole functional accent, used sparingly for primary calls-to-action and active states to maintain the professional tone.
- **Glass Transparency:** Surfaces utilize varying levels of alpha-transparency (40% to 70%) combined with high-saturation background blurs (30px to 60px).
- **Dark Mode Strategy:** This system does not use a traditional dark mode. Instead, it transitions to an "Airy Mode" which maintains high transparency but shifts the background to a soft, luminous silver-grey while keeping surfaces light and crystalline.

## Typography

**Sora** is the exclusive typeface for this design system. Its geometric construction and generous counters complement the futuristic, liquid aesthetic. 

Headlines should be set with tight letter-spacing to feel cohesive and "solid" against the transparent UI. Body text requires slightly increased line height (1.6) to ensure maximum legibility against frosted glass backgrounds. For the "Liquid White" look, headlines may occasionally use a subtle linear gradient from pure white to a very light silver to mimic the way light hits a glass edge.

## Layout & Spacing

The layout follows a fluid-to-fixed model. Content is centered within a 1440px maximum width container on desktop, utilizing a 12-column grid. Spacing is generous, emphasizing the "ethereal" quality through significant whitespace.

- **Desktop:** 80px outer margins provide a spacious frame. Elements are grouped using large internal paddings (32px+) to allow the background blurs to be felt.
- **Tablet:** 40px margins with an 8-column grid.
- **Mobile:** 20px margins with a 4-column grid. Components should stretch full-width to maximize the glass surface area.

Rhythm is based on an 8px base unit. Negative space is considered a design element in this system; components should "breathe" to avoid breaking the illusion of transparency.

## Elevation & Depth

Depth is conveyed through **refraction and luminosity** rather than traditional black shadows. 

1.  **Layer 0 (Base):** A soft, multi-colored radial gradient (soft blues and whites) that serves as the "liquid" environment.
2.  **Layer 1 (Standard Surface):** High-transparency glass (`rgba(255, 255, 255, 0.4)`) with a `backdrop-filter: blur(40px)`.
3.  **Layer 2 (Elevated):** Thicker glass (`rgba(255, 255, 255, 0.7)`) with a `backdrop-filter: blur(60px)`.
4.  **Shadows:** Use "White Shadows"—wide, diffused white glows (`0px 20px 40px rgba(255, 255, 255, 0.5)`)—to lift elements off the background.
5.  **Inner Glows:** Every glass component must have a 1px solid white stroke at 20% opacity and an inner shadow/glow (`inset 0 1px 1px rgba(255,255,255,0.8)`) to simulate the highlight on a glass edge.

## Shapes

The shape language is ultra-soft and organic. All containers and interactive elements use large corner radii to reinforce the "liquid" metaphor.

- **Standard Containers:** 24px minimum radius.
- **Buttons & Inputs:** 32px or fully pill-shaped (rounded-full).
- **Cards:** 32px to 40px radius depending on scale.

Sharp corners are strictly prohibited as they break the futuristic, ethereal flow of the system.

## Components

- **Buttons:** Primary buttons are solid Electric Blue (#007AFF) with a subtle inner glow. Secondary buttons are frosted glass with white text. Hover states should increase the backdrop blur intensity rather than changing the color.
- **Inputs:** High-transparency glass fields with a 1px "edge" stroke. On focus, the stroke becomes Electric Blue and the inner glow intensifies.
- **Cards:** The signature "Liquid Glass" component. Features a multi-layered white-on-white shadow, 32px corner radius, and significant backdrop blur. Content inside should have high contrast (Text Primary #1A1C1E).
- **Chips/Labels:** Small, fully pill-shaped glass elements with `backdrop-filter: blur(10px)`.
- **Navigation:** A floating "glass dock" centered at the bottom or top of the viewport, using a high-density blur to separate it from the content scrolling beneath.
- **Feedback:** Success and error states should avoid heavy red/green fills. Instead, use colored "glows" or icons in the specified accent colors against the white glass base.