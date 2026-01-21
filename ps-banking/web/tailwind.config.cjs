/** @type {import('tailwindcss').Config}*/
const config = {
  content: ["./src/**/*.{html,js,svelte,ts}"],

  theme: {
    extend: {
      colors: {
        glass: {
          50: 'rgba(255, 255, 255, 0.1)',
          100: 'rgba(255, 255, 255, 0.15)',
          200: 'rgba(255, 255, 255, 0.2)',
          300: 'rgba(255, 255, 255, 0.25)',
          dark: 'rgba(0, 0, 0, 0.1)',
          darker: 'rgba(0, 0, 0, 0.2)',
        },
        gradient: {
          primary: '#ffd700',
          secondary: '#f4a300',
          accent: '#ffed4e',
          pink: '#f093fb',
          purple: '#667eea',
        },
        bank: {
          primary: '#00a859',
          secondary: '#009b4d',
          accent: '#00c96b',
          dark: '#008f44',
          darker: '#007a3a',
          gold: '#ffd700',
          yellow: '#f4a300',
        },
        brasil: {
          green: '#009b3a',
          yellow: '#fedd00',
          blue: '#002776',
          gold: '#ffd700',
        }
      },
      backdropBlur: {
        xs: '2px',
      },
      boxShadow: {
        glass: '0 8px 32px 0 rgba(31, 38, 135, 0.37)',
        'glass-inset': 'inset 0 1px 0 0 rgba(255, 255, 255, 0.05)',
        'neon-green': '0 0 20px rgba(0, 168, 89, 0.5)',
        'neon-green-lg': '0 0 40px rgba(0, 168, 89, 0.6)',
        'neon-gold': '0 0 20px rgba(255, 215, 0, 0.5)',
        'neon-gold-lg': '0 0 40px rgba(255, 215, 0, 0.6)',
        'card-hover': '0 20px 50px rgba(0, 0, 0, 0.4)',
        'inner-glow': 'inset 0 0 20px rgba(255, 255, 255, 0.05)',
        'elevate': '0 10px 40px rgba(0, 0, 0, 0.3)',
        'brasil': '0 0 30px rgba(0, 155, 58, 0.4), 0 0 60px rgba(255, 215, 0, 0.2)',
        'money': '0 4px 20px rgba(255, 215, 0, 0.3), 0 8px 40px rgba(0, 168, 89, 0.2)',
      },
      animation: {
        'float': 'float 6s ease-in-out infinite',
        'glow': 'glow 2s ease-in-out infinite alternate',
        'pulse-soft': 'pulse-soft 2s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'shimmer': 'shimmer 2s linear infinite',
        'slide-up': 'slide-up 0.5s ease-out',
        'slide-down': 'slide-down 0.5s ease-out',
        'scale-in': 'scale-in 0.3s ease-out',
        'fade-in': 'fade-in 0.4s ease-out',
        'bounce-soft': 'bounce-soft 1s ease-in-out infinite',
        'spin-slow': 'spin 3s linear infinite',
        'ping-slow': 'ping 3s cubic-bezier(0, 0, 0.2, 1) infinite',
        'wiggle': 'wiggle 1s ease-in-out infinite',
        'gradient': 'gradient 3s ease infinite',
        'card-float': 'card-float 6s ease-in-out infinite',
        'text-shimmer': 'text-shimmer 2.5s ease-in-out infinite',
        'border-glow': 'border-glow 3s ease-in-out infinite',
        'slide-left': 'slide-left 0.5s ease-out',
        'slide-right': 'slide-right 0.5s ease-out',
        'bounce-in': 'bounce-in 0.6s ease-out',
        'rotate-in': 'rotate-in 0.6s ease-out',
        'glow-brasil': 'glow-brasil 2s ease-in-out infinite alternate',
        'money-rain': 'money-rain 3s ease-in-out infinite',
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%': { transform: 'translateY(-10px)' },
        },
        glow: {
          '0%': { boxShadow: '0 0 5px rgba(102, 126, 234, 0.5)' },
          '100%': { boxShadow: '0 0 20px rgba(102, 126, 234, 0.8)' },
        },
        'pulse-soft': {
          '0%, 100%': { opacity: '1' },
          '50%': { opacity: '0.7' },
        },
        shimmer: {
          '0%': { backgroundPosition: '-200% 0' },
          '100%': { backgroundPosition: '200% 0' },
        },
        'slide-up': {
          '0%': { transform: 'translateY(20px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        'slide-down': {
          '0%': { transform: 'translateY(-20px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        'scale-in': {
          '0%': { transform: 'scale(0.9)', opacity: '0' },
          '100%': { transform: 'scale(1)', opacity: '1' },
        },
        'fade-in': {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        'bounce-soft': {
          '0%, 100%': { transform: 'translateY(-5%)' },
          '50%': { transform: 'translateY(0)' },
        },
        wiggle: {
          '0%, 100%': { transform: 'rotate(-3deg)' },
          '50%': { transform: 'rotate(3deg)' },
        },
        gradient: {
          '0%, 100%': { backgroundPosition: '0% 50%' },
          '50%': { backgroundPosition: '100% 50%' },
        },
        'card-float': {
          '0%, 100%': { transform: 'translateY(0px) rotate(0deg)' },
          '33%': { transform: 'translateY(-10px) rotate(1deg)' },
          '66%': { transform: 'translateY(-5px) rotate(-1deg)' },
        },
        'text-shimmer': {
          '0%': { backgroundPosition: '0% 50%' },
          '100%': { backgroundPosition: '100% 50%' },
        },
        'border-glow': {
          '0%, 100%': { borderColor: 'rgba(16, 185, 129, 0.3)' },
          '50%': { borderColor: 'rgba(16, 185, 129, 0.8)' },
        },
        'slide-left': {
          '0%': { transform: 'translateX(-20px)', opacity: '0' },
          '100%': { transform: 'translateX(0)', opacity: '1' },
        },
        'slide-right': {
          '0%': { transform: 'translateX(20px)', opacity: '0' },
          '100%': { transform: 'translateX(0)', opacity: '1' },
        },
        'bounce-in': {
          '0%': { transform: 'scale(0.3)', opacity: '0' },
          '50%': { transform: 'scale(1.05)' },
          '70%': { transform: 'scale(0.9)' },
          '100%': { transform: 'scale(1)', opacity: '1' },
        },
        'rotate-in': {
          '0%': { transform: 'rotate(-180deg) scale(0)', opacity: '0' },
          '100%': { transform: 'rotate(0) scale(1)', opacity: '1' },
        },
        'glow-brasil': {
          '0%': { boxShadow: '0 0 10px rgba(0, 155, 58, 0.5), 0 0 20px rgba(255, 215, 0, 0.3)' },
          '100%': { boxShadow: '0 0 20px rgba(0, 155, 58, 0.8), 0 0 40px rgba(255, 215, 0, 0.6)' },
        },
        'money-rain': {
          '0%, 100%': { transform: 'translateY(0) rotate(0deg)' },
          '25%': { transform: 'translateY(-5px) rotate(5deg)' },
          '50%': { transform: 'translateY(-10px) rotate(-5deg)' },
          '75%': { transform: 'translateY(-5px) rotate(5deg)' },
        },
      },
      backgroundImage: {
        'shimmer-gradient': 'linear-gradient(90deg, transparent, rgba(255,255,255,0.1), transparent)',
        'glass-gradient': 'linear-gradient(135deg, rgba(255,255,255,0.1) 0%, rgba(255,255,255,0.05) 100%)',
        'bank-gradient': 'linear-gradient(135deg, #00a859 0%, #009b4d 100%)',
        'dark-gradient': 'linear-gradient(135deg, #1f2937 0%, #111827 100%)',
        'brasil-gradient': 'linear-gradient(135deg, #009b3a 0%, #fedd00 100%)',
        'gold-gradient': 'linear-gradient(135deg, #ffd700 0%, #f4a300 100%)',
        'green-glow': 'radial-gradient(circle, rgba(0,168,89,0.2) 0%, transparent 70%)',
        'brasil-flag': 'linear-gradient(180deg, #009b3a 0%, #009b3a 50%, #fedd00 50%, #fedd00 100%)',
      },
      backgroundSize: {
        '200%': '200% 100%',
        '300%': '300% 100%',
      },
    },
  },

  plugins: [],
};

module.exports = config;
