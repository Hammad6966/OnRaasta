import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          bg:             "#050A14",
          surface:        "#0F2040",
          surfaceVariant: "#0D1B2E",
          primary:        "#2563EB",
          accent:         "#F97316",
          border:         "#1E3A5F",
          textPrimary:    "#FFFFFF",
          textSecondary:  "#94A3B8",
          success:        "#22C55E",
          error:          "#EF4444",
          warning:        "#F59E0B",
        },
      },
      fontFamily: {
        syne:   ["Syne", "sans-serif"],
        dm:     ["DM Sans", "sans-serif"],
      },
    },
  },
  plugins: [],
};
export default config;
