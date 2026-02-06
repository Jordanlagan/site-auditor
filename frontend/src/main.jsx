import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import './index.css'
import App from './App.jsx'
import TestLibrary from './TestLibrary.jsx'
import TestBuilder from './TestBuilder.jsx'
import TestGroupBuilder from './TestGroupBuilder.jsx'
import Navigation from './Navigation.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <BrowserRouter>
      <Navigation />
      <Routes>
        <Route path="/" element={<App />} />
        <Route path="/test-library" element={<TestLibrary />} />
        <Route path="/test-builder" element={<TestBuilder />} />
        <Route path="/test-builder/:id" element={<TestBuilder />} />
        <Route path="/test-groups" element={<TestGroupBuilder />} />
        <Route path="/test-groups/:id" element={<TestGroupBuilder />} />
      </Routes>
    </BrowserRouter>
  </StrictMode>,
)
