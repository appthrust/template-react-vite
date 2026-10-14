import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
export default defineConfig({
  plugins: [react()],
  // AppThrust publishes the app behind arbitrary public hostnames; Vite's
  // preview server rejects unknown Host headers unless they are allowed.
  preview: { allowedHosts: true },
});
