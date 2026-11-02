import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './ui/App';
import { BOOT_SCRIPT_READY, setBootProgress } from './ui/boot';
import './ui/styles.css';
setBootProgress(BOOT_SCRIPT_READY);
ReactDOM.createRoot(document.getElementById('root')!).render(<App />);
