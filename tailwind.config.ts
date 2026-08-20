import type { Config } from "tailwindcss";

/**
 * Design tokens.
 *
 * The visual language is deliberately that of an official Nepali vehicle
 * document: the bluebook (नीलपुस्तिका) is the trust artifact at the centre of
 * every second-hand car sale here, so the palette is drawn from it —
 * indigo ink on paper stock, with a sayapatri-marigold accent and a
 * stamped-seal motif for verification.
 */
const config: Config = {
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: {
          DEFAULT: "#17255A", // bluebook cover indigo
          deep: "#0E1740",
          soft: "#2E3D77",
        },
        paper: {
          DEFAULT: "#FBFAF7",
          shade: "#F1EEE7",
          line: "#DFD9CC",
        },
        marigold: {
          DEFAULT: "#E8A33D", // sayapatri
          deep: "#C4832A",
        },
        verified: "#1F7A5C",
        alert: "#B23A48",
        slate: {
          DEFAULT: "#2C3241",
          muted: "#6B7280",
        },
      },
      fontFamily: {
        display: ["Archivo", "system-ui", "sans-serif"],
        body: ["Inter", "system-ui", "sans-serif"],
        deva: ["'Noto Sans Devanagari'", "sans-serif"],
        mono: ["'JetBrains Mono'", "ui-monospace", "monospace"],
      },
      fontSize: {
        "display-lg": ["clamp(2.5rem, 6vw, 4.25rem)", { lineHeight: "0.95", letterSpacing: "-0.03em" }],
        "display-md": ["clamp(1.875rem, 4vw, 2.75rem)", { lineHeight: "1.02", letterSpacing: "-0.02em" }],
      },
      boxShadow: {
        card: "0 1px 2px rgba(23,37,90,0.06), 0 8px 24px -12px rgba(23,37,90,0.18)",
        lift: "0 2px 4px rgba(23,37,90,0.08), 0 18px 40px -18px rgba(23,37,90,0.28)",
      },
      backgroundImage: {
        // Faint ruled-paper texture, echoing a printed document.
        ruled:
          "repeating-linear-gradient(to bottom, transparent, transparent 31px, rgba(23,37,90,0.045) 31px, rgba(23,37,90,0.045) 32px)",
      },
      keyframes: {
        stampIn: {
          "0%": { opacity: "0", transform: "rotate(-18deg) scale(1.6)" },
          "60%": { opacity: "1", transform: "rotate(-11deg) scale(0.96)" },
          "100%": { opacity: "1", transform: "rotate(-11deg) scale(1)" },
        },
        riseIn: {
          "0%": { opacity: "0", transform: "translateY(10px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
      },
      animation: {
        stamp: "stampIn 420ms cubic-bezier(0.2, 0.9, 0.3, 1) both",
        rise: "riseIn 380ms ease-out both",
      },
    },
  },
  plugins: [],
};

export default config;
