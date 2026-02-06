import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import './TestBuilder.css';

const TestBuilder = () => {
  const { id } = useParams();
  const navigate = useNavigate();
  const isEdit = !!id;
  const API_BASE = 'http://localhost:3000';

  const [testGroups, setTestGroups] = useState([]);
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    test_key: '',
    test_group_id: '',
    test_details: '',
    data_sources: [],
    active: true
  });
  const [loading, setLoading] = useState(isEdit);
  const [saving, setSaving] = useState(false);

  const getDataSourceIcon = (source) => {
    const icons = {
      'page_content': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M3 2h10a1 1 0 011 1v10a1 1 0 01-1 1H3a1 1 0 01-1-1V3a1 1 0 011-1zm1 2v8h8V4H4zm2 2h4v1H6V6zm0 2h4v1H6V8z"/></svg>',
      'html_content': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M5 3l-3 3 3 3V7h6v2l3-3-3-3v2H5V3z"/></svg>',
      'screenshots': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><rect x="2" y="3" width="12" height="10" rx="1" fill="none" stroke="currentColor" stroke-width="1.5"/><circle cx="8" cy="8" r="2.5"/></svg>',
      'headings': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><text x="2" y="12" font-size="12" font-weight="bold">H</text></svg>',
      'meta_tags': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M3 3h4l2 5 2-5h4L12 13h-2L8 8l-2 5H4L3 3z"/></svg>',
      'structured_data': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M2 4h12v2H2V4zm0 4h12v2H2V8zm0 4h12v2H2v-2z"/></svg>',
      'fonts': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><text x="2" y="12" font-size="12" font-style="italic">A</text></svg>',
      'colors': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><circle cx="5" cy="5" r="3" fill="#CE6262"/><circle cx="11" cy="5" r="3" fill="#4A9EFF"/><circle cx="8" cy="10" r="3" fill="#62CE8B"/></svg>',
      'images': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><rect x="2" y="3" width="12" height="10" rx="1" fill="none" stroke="currentColor" stroke-width="1.5"/><circle cx="5.5" cy="6.5" r="1.5"/><path d="M2 11l3-3 2 2 4-4 3 3v2H2z"/></svg>',
      'scripts': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M4 5l4 3-4 3V5zm6 0v6h2V5h-2z"/></svg>',
      'stylesheets': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M3 2h10v2H3V2zm0 4h10v2H3V6zm0 4h6v2H3v-2z"/></svg>',
      'performance_metrics': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M8 2a6 6 0 100 12A6 6 0 008 2zm0 2v4l3 2-1 1-4-3V4h2z"/></svg>',
      'links': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M6.5 9.5l-2 2a2 2 0 11-2.8-2.8l2-2m8.6-2.2l-2 2a2 2 0 102.8 2.8l2-2M5.5 10.5l5-5"/></svg>',
      'computed_styles': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M8 2l6 4v6l-6 4-6-4V6l6-4zm0 2L4 6.5v3L8 12l4-2.5v-3L8 4z"/></svg>'
    };
    return icons[source] || '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><rect x="3" y="3" width="10" height="10" rx="2"/></svg>';
  };

  const availableDataSources = [
    { value: 'page_content', label: 'Page Content', description: 'Main text content from the page', tooltip: 'PageDataCollector: Extracts all visible text from <body> using Selenium. Gets the rendered text content users actually see.' },
    { value: 'html_content', label: 'HTML Content', description: 'Raw HTML source code', tooltip: 'PageDataCollector: Captures the full page source HTML using driver.page_source. Includes all tags, attributes, and inline scripts/styles.' },
    { value: 'screenshots', label: 'Screenshots', description: 'Visual screenshots of the page', tooltip: 'PageDataCollector: Captures full-page screenshots at 1920x1080 (desktop) and 375x667 (mobile) using Selenium, saved as PNG files.' },
    { value: 'headings', label: 'Headings', description: 'H1, H2, H3, etc. headings structure', tooltip: 'PageDataCollector: Finds all <h1> through <h6> elements and extracts their text content. Returns structured object with arrays for each heading level.' },
    { value: 'meta_tags', label: 'Meta Tags', description: 'Title, description, and meta tags', tooltip: 'PageDataCollector: Queries all <meta> tags via JavaScript, extracting name/property and content attributes. Includes OpenGraph, Twitter Cards, etc.' },
    { value: 'structured_data', label: 'Structured Data', description: 'Schema.org markup and JSON-LD', tooltip: 'PageDataCollector: Finds all <script type="application/ld+json"> tags and parses their JSON content. Used for rich snippets and SEO.' },
    { value: 'fonts', label: 'Fonts', description: 'Font families used on the page', tooltip: 'PageDataCollector: Scans stylesheets for @font-face rules via JavaScript, checks for Google Fonts links, and extracts font-family, weight, and style.' },
    { value: 'colors', label: 'Colors', description: 'Color palette used on the page', tooltip: 'PageDataCollector: Iterates all elements via JavaScript, gets computed styles for color, backgroundColor, and borderColor. Returns top 20 by usage count.' },
    { value: 'images', label: 'Images', description: 'Image sources and metadata', tooltip: 'PageDataCollector: Queries all <img> tags via JavaScript. Returns src, alt text, dimensions (naturalWidth/Height), loading attribute, and srcset.' },
    { value: 'scripts', label: 'Scripts', description: 'JavaScript files loaded', tooltip: 'PageDataCollector: Queries all <script> tags via JavaScript. Returns src URL, type, async/defer attributes, and whether script is inline or external.' },
    { value: 'stylesheets', label: 'Stylesheets', description: 'CSS files loaded', tooltip: 'PageDataCollector: Queries all <link rel="stylesheet"> tags via JavaScript. Returns href URLs and media query attributes.' },
    { value: 'performance_metrics', label: 'Performance Metrics', description: 'Page load and performance data', tooltip: 'PageDataCollector: Uses Performance API via JavaScript to get DOM Content Loaded, Load Complete, First Paint, First Contentful Paint, and Time to First Byte.' },
    { value: 'asset_distribution', label: 'Asset Distribution', description: 'Breakdown of page weight by asset type', tooltip: 'PageDataCollector: Uses Performance API to sum transferSize of resources by type (images, scripts, CSS, fonts, other). Shows weight distribution in bytes.' },
    { value: 'total_page_weight', label: 'Total Page Weight', description: 'Total size of all page resources', tooltip: 'PageDataCollector: Sums transferSize from all Performance API resources. Returns total page weight in bytes including HTML, CSS, JS, images, fonts.' },
    { value: 'links', label: 'Links', description: 'Internal and external links', tooltip: 'PageDataCollector: Queries all <a> tags via JavaScript. Returns href, visible text content, rel attribute, and target attribute for each link.' },
    { value: 'computed_styles', label: 'Computed Styles', description: 'Final CSS styles applied', tooltip: 'PageDataCollector: Uses window.getComputedStyle() to get final rendered CSS values for elements. Shows actual styles after cascade resolution.' }
  ];

  useEffect(() => {
    loadTestGroups();
    if (isEdit) {
      loadTest();
    }
  }, [id]);

  const loadTestGroups = async () => {
    try {
      const response = await fetch(`${API_BASE}/test-groups`);
      const data = await response.json();
      setTestGroups(data.test_groups || []);
    } catch (error) {
      console.error('Error loading test groups:', error);
    }
  };

  const loadTest = async () => {
    setLoading(true);
    try {
      const response = await fetch(`${API_BASE}/tests/${id}`);
      const data = await response.json();
      setFormData({
        name: data.test.name,
        description: data.test.description || '',
        test_key: data.test.test_key,
        test_group_id: data.test.test_group.id,
        test_details: data.test.test_details,
        data_sources: data.test.data_sources || [],
        active: data.test.active
      });
    } catch (error) {
      console.error('Error loading test:', error);
      alert('Failed to load test');
    } finally {
      setLoading(false);
    }
  };

  const handleChange = (field, value) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const handleDataSourceToggle = (source) => {
    setFormData(prev => ({
      ...prev,
      data_sources: prev.data_sources.includes(source)
        ? prev.data_sources.filter(s => s !== source)
        : [...prev.data_sources, source]
    }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setSaving(true);

    try {
      const url = isEdit ? `${API_BASE}/tests/${id}` : `${API_BASE}/tests`;
      const method = isEdit ? 'PUT' : 'POST';

      const response = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ test: formData })
      });

      if (response.ok) {
        alert(isEdit ? 'Test updated successfully!' : 'Test created successfully!');
        navigate('/test-library');
      } else {
        const error = await response.json();
        alert('Error: ' + (error.errors?.join(', ') || 'Failed to save test'));
      }
    } catch (error) {
      console.error('Error saving test:', error);
      alert('Failed to save test');
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async () => {
    if (!confirm('Are you sure you want to delete this test?')) return;

    try {
      const response = await fetch(`${API_BASE}/tests/${id}`, {
        method: 'DELETE'
      });

      if (response.ok) {
        alert('Test deleted successfully!');
        navigate('/test-library');
      } else {
        alert('Failed to delete test');
      }
    } catch (error) {
      console.error('Error deleting test:', error);
      alert('Failed to delete test');
    }
  };

  const generateTestKey = () => {
    const key = formData.name
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, '')
      .replace(/\s+/g, '_');
    handleChange('test_key', key);
  };

  if (loading) {
    return <div className="test-builder-loading">Loading...</div>;
  }

  return (
    <div className="main-content">
      <div className="content-wrapper">
        <div className="content-inner">
          <div className="test-builder">
            <div className="test-builder-header">
              <h1>{isEdit ? 'Edit Test' : 'Create New Test'}</h1>
              <button onClick={() => navigate('/test-library')} className="btn btn-secondary">
                Cancel
              </button>
            </div>

      <form onSubmit={handleSubmit} className="test-builder-form">
        <div className="form-section">
          <h2>Basic Information</h2>
          
          <div className="form-group">
            <label>Test Name *</label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) => handleChange('name', e.target.value)}
              onBlur={!isEdit && !formData.test_key ? generateTestKey : undefined}
              required
              placeholder="e.g., Typography & Readability"
            />
          </div>

          <div className="form-group">
            <label>Test Key *</label>
            <input
              type="text"
              value={formData.test_key}
              onChange={(e) => handleChange('test_key', e.target.value)}
              required
              disabled={isEdit}
              placeholder="e.g., typos_check"
              pattern="[a-z0-9_]+"
              title="Lowercase letters, numbers, and underscores only"
            />
            {!isEdit && (
              <small>Unique identifier (lowercase, numbers, underscores only)</small>
            )}
          </div>

          <div className="form-group">
            <label>Description</label>
            <textarea
              value={formData.description}
              onChange={(e) => handleChange('description', e.target.value)}
              placeholder="Brief description of what this test checks..."
              rows="3"
            />
          </div>

          <div className="form-group">
            <label>Test Group *</label>
            {testGroups.length === 0 ? (
              <p style={{color: 'var(--text-tertiary, #888)', fontSize: '0.875rem'}}>No test groups exist yet. <a href="/test-groups" style={{color: 'var(--blue, #4CA9E9)'}}>Create one first</a></p>
            ) : (
              <div className="data-sources-grid">
                {testGroups.map(group => (
                  <div
                    key={group.id}
                    className={`data-source-card ${formData.test_group_id === group.id ? 'selected' : ''}`}
                    onClick={() => handleChange('test_group_id', group.id)}
                  >
                    <div className="data-source-header">
                      <input
                        type="radio"
                        checked={formData.test_group_id === group.id}
                        readOnly
                      />
                      <strong>{group.name}</strong>
                    </div>
                    {group.description && <p>{group.description}</p>}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        <div className="form-section">
          <h2>Test Configuration</h2>

          <div className="form-group">
            <label>Test Details *</label>
            <textarea
              value={formData.test_details}
              onChange={(e) => handleChange('test_details', e.target.value)}
              required
              placeholder="Enter detailed instructions for the AI to analyze this test..."
              rows="10"
              className="ai-prompt-textarea"
            />
            <small>
              This tells the AI what to look for and how to evaluate the page.
              Be specific about what constitutes a pass, fail, or not applicable.
            </small>
          </div>

          <div className="form-group">
            <label>Data Sources *</label>
            <div className="data-sources-grid">
              {availableDataSources.map(source => (
                <div
                  key={source.value}
                  className={`data-source-card ${formData.data_sources.includes(source.value) ? 'selected' : ''}`}
                  onClick={() => handleDataSourceToggle(source.value)}
                >
                  <div className="data-source-header">
                    <input
                      type="checkbox"
                      checked={formData.data_sources.includes(source.value)}
                      readOnly
                    />
                    <strong>{source.label}</strong>
                    <span className="info-icon" title={source.tooltip}>ⓘ</span>
                  </div>
                  <p>{source.description}</p>
                </div>
              ))}
            </div>
            <small>Select which data sources the AI should analyze for this test (hover ⓘ for technical details)</small>
          </div>
        </div>

        <div className="form-actions">
          <div style={{display: 'flex', gap: '1rem', flex: 1}}>
            {isEdit && (
              <button type="button" onClick={handleDelete} className="btn btn-danger">
                Delete Test
              </button>
            )}
          </div>
          <div style={{display: 'flex', gap: '1rem'}}>
            <button type="button" onClick={() => navigate('/test-library')} className="btn btn-secondary">
              Cancel
            </button>
            <button type="submit" className="btn btn-primary" disabled={saving}>
              {saving ? 'Saving...' : (isEdit ? 'Update Test' : 'Create Test')}
            </button>
          </div>
        </div>
      </form>
          </div>
        </div>
      </div>
    </div>
  );
};

export default TestBuilder;
