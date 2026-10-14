import React from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';

function App() {
  return <main><h1>React + Vite on AppThrust</h1><p>DATABASE_URL is injected through the generated ComponentConnection for server-side components; this static browser application cannot access PostgreSQL credentials.</p></main>;
}

createRoot(document.getElementById('root')).render(<App />);
