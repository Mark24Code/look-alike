import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: '../dist',  // 输出到项目根目录的 dist 文件夹
    emptyOutDir: true,  // 构建前清空输出目录
  },
  server: {
    port: 5174,
    proxy: {
      '/api': {
        target: 'http://localhost:4568',
        changeOrigin: true
      }
    }
  }
})
