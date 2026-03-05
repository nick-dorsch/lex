// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/lex_web.ex",
    "../lib/lex_web/**/*.*ex"
  ],
  safelist: [
    "profile-blocked",
    "profile-setup-overlay",
    "profile-setup-modal",
    "profile-setup-error",
    "profile-language-options",
    "profile-language-option",
    "profile-setup-submit",
    "library-filter-pills",
    "filter-pill",
    "active"
  ],
  theme: {
    extend: {
      colors: {
        // Custom dark theme colors
        dark: {
          bg: '#0f172a',
          surface: '#1e293b',
          border: '#334155',
          text: '#f8fafc',
          muted: '#94a3b8',
          accent: '#38bdf8',
        },
        // Light theme colors
        light: {
          bg: '#ffffff',
          surface: '#f8fafc',
          border: '#e2e8f0',
          text: '#0f172a',
          muted: '#64748b',
          accent: '#0ea5e9',
        },
      },
      fontFamily: {
        sans: ['Merriweather', 'serif'],
        serif: ['Merriweather', 'serif'],
      },
    },
  },
  plugins: [
    plugin(({addVariant}) => addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"])),
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"]))
  ],
  darkMode: 'class'
}
