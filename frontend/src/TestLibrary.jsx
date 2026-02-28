import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import './TestLibrary.css';
import './test-icons.css';

const TestLibrary = () => {
  const API_BASE = 'http://localhost:3000';
  const navigate = useNavigate();
  const [testGroups, setTestGroups] = useState([]);
  const [tests, setTests] = useState([]);
  const [selectedGroup, setSelectedGroup] = useState(null);
  const [selectedTest, setSelectedTest] = useState(null);
  const [loading, setLoading] = useState(true);
  const [showImport, setShowImport] = useState(false);
  const [showNewGroup, setShowNewGroup] = useState(false);
  const [stats, setStats] = useState(null);

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    setLoading(true);
    try {
      const [groupsRes, testsRes] = await Promise.all([
        fetch(`${API_BASE}/test-groups`),
        fetch(`${API_BASE}/tests`)
      ]);
      
      const groupsData = await groupsRes.json();
      const testsData = await testsRes.json();
      
      setTestGroups(groupsData.test_groups || []);
      setTests(testsData.tests || []);
    } catch (error) {
      console.error('Error loading data:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleToggleActive = async (testId) => {
    try {
      await fetch(`${API_BASE}/tests/${testId}/toggle_active`, { method: 'POST' });
      loadData();
    } catch (error) {
      console.error('Error toggling test:', error);
    }
  };

  const handleToggleCore = async (testId) => {
    try {
      await fetch(`${API_BASE}/tests/${testId}/toggle_core`, { method: 'POST' });
      loadData();
    } catch (error) {
      console.error('Error toggling core:', error);
    }
  };

  const handleDeleteTest = async (testId) => {
    if (!confirm('Are you sure you want to delete this test?')) return;
    
    try {
      await fetch(`${API_BASE}/tests/${testId}`, { method: 'DELETE' });
      loadData();
      setSelectedTest(null);
    } catch (error) {
      console.error('Error deleting test:', error);
    }
  };

  const handleExport = async () => {
    try {
      const response = await fetch(`${API_BASE}/tests/export`);
      const blob = await response.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `tests_export_${Date.now()}.json`;
      a.click();
    } catch (error) {
      console.error('Error exporting tests:', error);
    }
  };

  const handleImport = async (event) => {
    const file = event.target.files[0];
    if (!file) return;

    const formData = new FormData();
    formData.append('file', file);

    try {
      const response = await fetch(`${API_BASE}/tests/import`, {
        method: 'POST',
        body: formData
      });
      
      const result = await response.json();
      
      if (result.error) {
        alert(`Import failed: ${result.error}`);
      } else {
        alert(`Imported ${result.imported} tests. Errors: ${result.errors?.length || 0}`);
        loadData();
        setShowImport(false);
      }
    } catch (error) {
      console.error('Error importing tests:', error);
    }
  };

  const filteredTests = selectedGroup
    ? tests.filter(t => t.test_group.id === selectedGroup)
    : tests;

  if (loading) {
    return <div className="test-library-loading">Loading test library...</div>;
  }

  return (
    <div className="main-content">
      <div className="content-wrapper">
        <div className="content-inner">
          <div className="test-library">
            <div className="test-library-header">
              <h1>Test Library</h1>
              <div className="header-actions">
          <button onClick={handleExport} className="btn btn-secondary">
            Export Tests
          </button>
          <button onClick={() => setShowImport(!showImport)} className="btn btn-secondary">
            Import Tests
          </button>
          <button onClick={() => navigate('/test-builder')} className="btn btn-primary">
            + New Test
          </button>
        </div>
      </div>

      {showImport && (
        <div className="import-panel">
          <input type="file" accept=".json" onChange={handleImport} />
        </div>
      )}

      {stats && (
        <div className="test-stats">
          <div className="stat-card">
            <div className="stat-value">{stats.total_tests}</div>
            <div className="stat-label">Total Tests</div>
          </div>
          <div className="stat-card">
            <div className="stat-value">{stats.active_tests}</div>
            <div className="stat-label">Active Tests</div>
          </div>
          <div className="stat-card">
            <div className="stat-value">{stats.core_tests}</div>
            <div className="stat-label">Core Tests</div>
          </div>
        </div>
      )}

      <div className="test-library-content">
        <div className="groups-sidebar">
          <div className="sidebar-header">
            <h3>Test Groups</h3>
            <button onClick={() => navigate('/test-groups')} className="btn-icon" title="Create New Test Group">+</button>
          </div>
          
          <div 
            className={`group-item ${!selectedGroup ? 'active' : ''}`}
            onClick={() => setSelectedGroup(null)}
          >
            <span>All Tests</span>
            <span className="count">{tests.length}</span>
          </div>

          {testGroups.map(group => (
            <div
              key={group.id}
              className={`group-item ${selectedGroup === group.id ? 'active' : ''}`}
              onClick={() => setSelectedGroup(group.id)}
            >
              <span className="group-color" style={{ backgroundColor: group.color }}></span>
              <span>{group.name}</span>
              <span className="count">{group.tests_count}</span>
            </div>
          ))}
        </div>

        <div className="tests-main">
          <div className="tests-grid">
            {filteredTests.map(test => {
              const getDataSourceIcon = (source) => {
                const icons = {
                  'page_content': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M3 2h10a1 1 0 011 1v10a1 1 0 01-1 1H3a1 1 0 01-1-1V3a1 1 0 011-1zm1 2v8h8V4H4zm2 2h4v1H6V6zm0 2h4v1H6V8z"/></svg>',
                  'page_html': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M5 3L2 8l3 5v-2L3 8l2-3V3zm6 0v2l2 3-2 3v2l3-5-3-5z"/></svg>',
                  'head_html': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M3 2h10v4H3V2zm1 1v2h8V3H4zm-1 5h10v1H3V8zm0 2h7v1H3v-1z"/></svg>',
                  'nav_html': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M2 4h12v1H2V4zm0 3h12v1H2V7zm0 3h12v1H2v-1z"/></svg>',
                  'body_html': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M3 2h10a1 1 0 011 1v10a1 1 0 01-1 1H3a1 1 0 01-1-1V3a1 1 0 011-1zm1 4v7h8V6H4z"/></svg>',
                  'headings': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M3 3h2v4h4V3h2v10h-2V9H5v4H3V3z"/></svg>',
                  'asset_urls': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M2 3h5v2H4v8h3v2H2V3zm7 0h5v12h-5v-2h3V5h-3V3z"/><rect x="6" y="7" width="4" height="2"/></svg>',
                  'performance_data': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M8 2a6 6 0 106 6h-2a4 4 0 11-4-4V2zm1 3v3h3a4 4 0 00-3-3z"/></svg>',
                  'internal_links': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M6.5 9.5l-2 2a2 2 0 11-2.8-2.8l2-2m8.6-2.2l-2 2a2 2 0 102.8 2.8l2-2M5.5 10.5l5-5"/></svg>',
                  'external_links': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M11 3h2v2h-2V3zM9 5V3h2v2H9zm2 2V5h2v2h-2zm0 2V7h2v2h-2zm-2 2V9h2v2H9zM3 13h6v-2H5V5h6V3H3v10z"/></svg>',
                  'colors': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><circle cx="5" cy="5" r="3"/><circle cx="11" cy="5" r="2.5" opacity="0.7"/><circle cx="8" cy="10" r="2.5" opacity="0.8"/></svg>',
                  'screenshots': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><rect x="2" y="3" width="12" height="9" rx="1" fill="none" stroke="currentColor" stroke-width="1.5"/><circle cx="8" cy="7.5" r="2.5"/></svg>'
                };
                return icons[source] || '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><rect x="3" y="3" width="10" height="10" rx="2"/></svg>';
              };

              const sourceLabels = {
                'page_content': 'Page Content',
                'page_html': 'Page HTML',
                'head_html': 'Head HTML',
                'nav_html': 'Nav HTML',
                'body_html': 'Body HTML',
                'headings': 'Headings',
                'asset_urls': 'Asset URLs',
                'performance_data': 'Performance Data',
                'internal_links': 'Internal Links',
                'external_links': 'External Links',
                'colors': 'Colors',
                'screenshots': 'Screenshots'
              };

              return (
                <div 
                  key={test.id} 
                  className={`test-card ${!test.active ? 'inactive' : ''}`}
                  onClick={() => navigate(`/test-builder/${test.id}`)}
                >
                  <div className="test-card-header">
                    <h4>{test.name}</h4>
                    {!test.active && <span className="badge badge-inactive">Inactive</span>}
                  </div>
                  
                  <p className="test-description">{test.description}</p>
                  
                  <div className="test-meta">
                    <span className="data-sources-label">Data Sources:</span>
                    <div className="data-source-icons">
                      {test.data_sources?.map(source => (
                        <span 
                          key={source} 
                          className="data-source-icon"
                          title={sourceLabels[source] || source}
                          dangerouslySetInnerHTML={{__html: getDataSourceIcon(source)}}
                        />
                      ))}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default TestLibrary;
