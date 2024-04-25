/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./templates/**/*.html"],
  darkMode: 'selector',
  plugins: [
    require('@tailwindcss/typography'),
  ],
}
