import React from 'react';
import { Link, useLocation } from 'react-router-dom';
import './Navigation.css';

const Navigation = () => {
  const location = useLocation();

  return (
    <nav className="main-navigation">
      <Link to="/" className="nav-brand">
        <h1>Site Auditor</h1>
      </Link>
      <div className="nav-links">
        <Link 
          to="/" 
          className={location.pathname === '/' ? 'active' : ''}
        >
          Dashboard
        </Link>
        <Link 
          to="/test-library" 
          className={location.pathname.includes('/test-library') || location.pathname.includes('/test-builder') ? 'active' : ''}
        >
          Test Library
        </Link>
      </div>
    </nav>
  );
};

export default Navigation;
