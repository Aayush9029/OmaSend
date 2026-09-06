import {defineConfig} from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
export default defineConfig({plugins:[react(),tailwindcss()],build:{outDir:'../linux/internal/web/static',emptyOutDir:true,rollupOptions:{output:{entryFileNames:'app.js',assetFileNames:'assets/[name]-[hash][extname]'}}},server:{proxy:{'/api':'http://127.0.0.1:53318'}}});
