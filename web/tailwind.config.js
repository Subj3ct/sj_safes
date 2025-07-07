/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        'white-70': 'rgba(255, 255, 255, 0.7)',
      },
    },
  },
  plugins: [],
} 