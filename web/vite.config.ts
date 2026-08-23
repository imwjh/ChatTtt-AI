import path from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    {
      // 开发模式下支持无后缀访问：/chat → /chat.html（生产由 express.static extensions 处理）
      name: "clean-urls",
      configureServer(server) {
        server.middlewares.use((req, _res, next) => {
          if (req.url === "/chat") req.url = "/chat.html";
          next();
        });
      },
    },
  ],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  build: {
    rollupOptions: {
      input: {
        landing: path.resolve(__dirname, "index.html"), // 落地页 /
        chat: path.resolve(__dirname, "chat.html"), // 聊天页 /chat
        admin: path.resolve(__dirname, "admin.html"), // 管理后台 /admin.html
      },
    },
  },
  server: {
    host: true, // 允许局域网访问
    proxy: {
      "/socket.io": {
        target: "http://localhost:3001",
        ws: true,
      },
      "/uploads": {
        target: "http://localhost:3001",
      },
      "/upload": {
        target: "http://localhost:3001",
      },
    },
  },
});
