import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import './App.css'
import './insights.css'
import './test-results.css'
import './test-json-details.css'
import './test-selection.css'
import './lightbox.css'
import WireframeConfigModal from './WireframeConfigModal'
import WireframeStreamingModal from './WireframeStreamingModal'

function App() {
  const { id: auditIdParam } = useParams()
  const navigate = useNavigate()
  
  const [url, setUrl] = useState('')
  const [fullCrawl, setFullCrawl] = useState(false)
  const [loading, setLoading] = useState(false)
  const [currentAudit, setCurrentAudit] = useState(null)
  const [audits, setAudits] = useState([])
  const [error, setError] = useState(null)
  const [polling, setPolling] = useState(false)
  const [sidebarOpen, setSidebarOpen] = useState(true)
  const [selectedPageId, setSelectedPageId] = useState(null)
  const [expandedCategories, setExpandedCategories] = useState({})
  const [deletingAudits, setDeletingAudits] = useState([])
  const [showPromptConfig, setShowPromptConfig] = useState(false)
  const [aiPrompts, setAiPrompts] = useState({
    systemPrompt: `You are an expert website auditor analyzing conversion optimization, user experience, design quality, and technical performance. Provide actionable, specific feedback.`,
    temperature: 0.3,
    model: 'claude-opus-4-6'
  })
  const [testGroups, setTestGroups] = useState([])
  const [tests, setTests] = useState([])
  const [selectedTests, setSelectedTests] = useState([])
  const [showTestSelection, setShowTestSelection] = useState(false)
  const [lightboxImage, setLightboxImage] = useState(null)
  const [wireframes, setWireframes] = useState([])
  const [showWireframeModal, setShowWireframeModal] = useState(false)
  const [loadingWireframes, setLoadingWireframes] = useState(false)
  const [wireframesGenerating, setWireframesGenerating] = useState(false)
  const [wireframesExpected, setWireframesExpected] = useState(0)
  const [generationStartedAt, setGenerationStartedAt] = useState(null)
  const [regenerateTarget, setRegenerateTarget] = useState(null) // { wireframeId, title }
  const [regeneratePrompt, setRegeneratePrompt] = useState('')
  const [regenerateSelector, setRegenerateSelector] = useState('')
  const [showRegenerateStreaming, setShowRegenerateStreaming] = useState(false)
  const [designBriefWireframe, setDesignBriefWireframe] = useState(null)

  console.log(currentAudit)

  // Data source icon getter (matching TestLibrary exactly)
  const getDataSourceIcon = (source) => {
    const icons = {
      'page_content': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M3 2h10a1 1 0 011 1v10a1 1 0 01-1 1H3a1 1 0 01-1-1V3a1 1 0 011-1zm1 2v8h8V4H4zm2 2h4v1H6V6zm0 2h4v1H6V8z"/></svg>',
      'page_html': '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M5 3L2 8l3 5v-2L3 8l2-3V3zm6 0v2l2 3-2 3v2l3-5-3-5z"/></svg>',
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
    'headings': 'Headings',
    'asset_urls': 'Asset URLs',
    'performance_data': 'Performance Data',
    'internal_links': 'Internal Links',
    'external_links': 'External Links',
    'colors': 'Colors',
    'screenshots': 'Screenshots'
  };

  const [expandedTests, setExpandedTests] = useState({})
  const [loadingAudit, setLoadingAudit] = useState(false)
  const [loadingHistory, setLoadingHistory] = useState(true)

  const API_BASE = 'http://localhost:3000'

  useEffect(() => {
    loadAuditHistory()
    loadTests()
  }, [])

  // Load audit from URL parameter
  useEffect(() => {
    if (auditIdParam) {
      const paramAuditId = parseInt(auditIdParam)
      // Only load if different from current audit
      if (!currentAudit || currentAudit.id !== paramAuditId) {
        loadAudit(paramAuditId)
      }
    }
  }, [auditIdParam])

  const loadAuditHistory = async () => {
    try {
      const response = await fetch(`${API_BASE}/audits`)
      const data = await response.json()
      setAudits(data.audits || [])
    } catch (err) {
      console.error('Failed to load audit history', err)
    } finally {
      setLoadingHistory(false)
    }
  }

  const loadTests = async () => {
    try {
      const [groupsRes, testsRes] = await Promise.all([
        fetch(`${API_BASE}/test-groups`),
        fetch(`${API_BASE}/tests`)
      ])
      const groupsData = await groupsRes.json()
      const testsData = await testsRes.json()
      
      setTestGroups(groupsData.test_groups || [])
      setTests(testsData.tests || [])
      
      // Pre-select all active tests by default
      const activeTestIds = (testsData.tests || [])
        .filter(t => t.active)
        .map(t => t.id)
      setSelectedTests(activeTestIds)
    } catch (err) {
      console.error('Failed to load tests', err)
    }
  }

  const toggleTestSelection = (testId) => {
    setSelectedTests(prev => 
      prev.includes(testId) 
        ? prev.filter(id => id !== testId)
        : [...prev, testId]
    )
  }

  const toggleGroupSelection = (groupId) => {
    const groupTests = tests.filter(t => t.test_group.id === groupId)
    const groupTestIds = groupTests.map(t => t.id)
    const allSelected = groupTestIds.every(id => selectedTests.includes(id))
    
    if (allSelected) {
      setSelectedTests(prev => prev.filter(id => !groupTestIds.includes(id)))
    } else {
      setSelectedTests(prev => [...new Set([...prev, ...groupTestIds])])
    }
  }

  const startAudit = async (e) => {
    e.preventDefault()
    setError(null)
    setCurrentAudit(null)
    setLoading(true)

    try {
      const response = await fetch(`${API_BASE}/audits`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          audit: { 
            url,
            audit_mode: fullCrawl ? 'full_crawl' : 'single_page',
            ai_config: aiPrompts,
            test_ids: selectedTests
          } 
        }),
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.errors?.[0] || 'Failed to start audit')
      }

      pollAuditStatus(data.id)
    } catch (err) {
      setError(err.message)
      setLoading(false)
    }
  }

  const pollAuditStatus = async (auditId) => {
    setPolling(true)
    const maxAttempts = 120
    let attempts = 0

    const poll = async () => {
      try {
        const response = await fetch(`${API_BASE}/audits/${auditId}/status`)
        const data = await response.json()

        if (data.status === 'complete') {
          // Load full audit data
          const fullResponse = await fetch(`${API_BASE}/audits/${auditId}`)
          const fullData = await fullResponse.json()
          
          setCurrentAudit(fullData)
          setLoading(false)
          setPolling(false)
          loadAuditHistory()
          
          // Navigate to the completed audit
          navigate(`/audits/${auditId}`)
          return
        }

        if (data.status === 'failed') {
          setError('Audit failed. Please try again.')
          setLoading(false)
          setPolling(false)
          return
        }

        attempts++
        if (attempts < maxAttempts) {
          setTimeout(poll, 3000)
        } else {
          setError('Audit timed out. Please try again.')
          setLoading(false)
          setPolling(false)
        }
      } catch (err) {
        setError('Failed to fetch audit status')
        setLoading(false)
        setPolling(false)
      }
    }

    poll()
  }

  const loadAudit = async (auditId) => {
    setLoadingAudit(true)
      
      // Navigate to this audit's URL if not already there
      if (window.location.pathname !== `/audits/${auditId}`) {
        navigate(`/audits/${auditId}`, { replace: true })
      }
    try {
      const response = await fetch(`${API_BASE}/audits/${auditId}`)
      const data = await response.json()
      setCurrentAudit(data)
      setUrl(data.url)
      setExpandedCategories({})
      setSelectedPageId(data.all_pages?.[0]?.id || null)
    } catch (err) {
      setError('Failed to load audit')
    } finally {
      setLoadingAudit(false)
    }
  }

  const deleteAudit = async (auditId, e) => {
    e.stopPropagation()
    if (!confirm('Delete this audit?')) return

    // Start animation
    setDeletingAudits(prev => [...prev, auditId])

    // Wait for animation to complete
    setTimeout(async () => {
      try {
        await fetch(`${API_BASE}/audits/${auditId}`, { method: 'DELETE' })
        
        if (currentAudit?.id === auditId) {
          setCurrentAudit(null)
          setUrl('')
          // Navigate back to home
          navigate('/')
        }
        
        // Remove from state immediately
        setAudits(prev => prev.filter(a => a.id !== auditId))
        setDeletingAudits(prev => prev.filter(id => id !== auditId))
      } catch (err) {
        setError('Failed to delete audit')
        setDeletingAudits(prev => prev.filter(id => id !== auditId))
      }
    }, 400)
  }

  const startNewAudit = () => {
    setCurrentAudit(null)
    setUrl('')
    setError(null)
    setExpandedCategories({})
    setSelectedPageId(null)
    navigate('/')
  }

  const toggleCategory = (category) => {
    setExpandedCategories(prev => ({
      ...prev,
      [category]: !prev[category]
    }))
  }

  const toggleTestExpanded = (testId) => {
    setExpandedTests(prev => ({ ...prev, [testId]: !prev[testId] }))
  }

  const openLightbox = (imageSrc, label) => {
    setLightboxImage({ src: imageSrc, label })
  }

  const closeLightbox = () => {
    setLightboxImage(null)
  }

  const copyPageData = () => {
    if (currentAudit?.pages?.[0]?.page_data) {
      const dataString = JSON.stringify(currentAudit.pages[0].page_data, null, 2)
      navigator.clipboard.writeText(dataString)
        .then(() => alert('Page data copied to clipboard!'))
        .catch(() => alert('Failed to copy to clipboard'))
    }
  }

  const loadWireframes = async (auditId) => {
    setLoadingWireframes(true)
    try {
      const response = await fetch(`${API_BASE}/audits/${auditId}/wireframes`)
      const data = await response.json()
      console.log('Wireframes data:', data) // Debug log
      setWireframes(data.wireframes || [])
      setWireframesGenerating(data.generating || false)
      setWireframesExpected(data.expected_count || 0)
      setGenerationStartedAt(data.generation_started_at)
      return data
    } catch (err) {
      console.error('Failed to load wireframes', err)
      return null
    } finally {
      setLoadingWireframes(false)
    }
  }

  const handleWireframeGenerate = (count) => {
    // Start polling every 5 seconds until server says generation is complete
    if (currentAudit?.id) {
      const pollInterval = setInterval(async () => {
        const data = await loadWireframes(currentAudit.id)
        
        // Stop polling when generation is complete or failed
        if (data && !data.generating) {
          clearInterval(pollInterval)
        }
      }, 5000) // Poll every 5 seconds
      
      // Initial load after a short delay
      setTimeout(() => loadWireframes(currentAudit.id), 2000)
    }
  }

  const deleteWireframe = async (wireframeId) => {
    if (!confirm('Delete this wireframe?')) return
    
    try {
      await fetch(`${API_BASE}/wireframes/${wireframeId}`, { method: 'DELETE' })
      setWireframes(prev => prev.filter(w => w.id !== wireframeId))
    } catch (err) {
      console.error('Failed to delete wireframe', err)
      alert('Failed to delete wireframe')
    }
  }

  const openWireframe = (wireframeUrl) => {
    window.open(`${API_BASE}${wireframeUrl}`, '_blank')
  }

  useEffect(() => {
    if (currentAudit?.id) {
      loadWireframes(currentAudit.id)
    }
  }, [currentAudit?.id])

  const getPassRateColor = (passRate) => {
    return passRate >= 50 ? '#19C798' : '#CE6262'
  }

  const getScoreColor = (score) => {
    if (score >= 80) return '#19C798'
    if (score >= 60) return '#F4C085'
    return '#CE6262'
  }

  const getCategoryIcon = (category) => {
    const icons = {
      nav: 'NAV',
      structure: 'STR',
      cro: 'CRO',
      design: 'DES',
      reviews: 'REV',
      price: 'PRC',
      speed: 'SPD'
    }
    return icons[category] || 'GEN'
  }

  const formatDate = (dateString) => {
    const date = new Date(dateString)
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
  }

  const formatTestName = (name) => {
    // Capitalize CRO specifically
    return name.replace(/\bcro\b/gi, 'CRO')
  }

  return (
    <div className="app">
      {/* Sidebar */}
      <aside className={`sidebar ${sidebarOpen ? 'open' : 'closed'}`}>
        <div className="sidebar-header">
          <button className="new-audit-btn" onClick={startNewAudit}>
            <span className="icon">+</span> New Audit
          </button>
        </div>

        <div className="audit-history">
          <div className="history-label">Recent Audits</div>
          {loadingHistory ? (
            <div className="sidebar-loading">
              <div className="spinner-small"></div>
            </div>
          ) : audits.length === 0 ? (
            <div className="no-audits">No audits yet</div>
          ) : (
            audits.map((audit) => (
              <div
                key={audit.id}
                className={`history-item ${currentAudit?.id === audit.id ? 'active' : ''} ${deletingAudits.includes(audit.id) ? 'deleting' : ''}`}
                onClick={() => !deletingAudits.includes(audit.id) && loadAudit(audit.id)}
              >
                <div className="history-item-content">
                  <div className="history-item-url">{new URL(audit.url).hostname}</div>
                  <div className="history-item-meta">
                    {audit.status === 'complete' && audit.total_tests > 0 && (
                      <span className="history-tests" style={{ color: getPassRateColor((audit.passed_tests / audit.total_tests) * 100) }}>
                        {audit.passed_tests}/{audit.total_tests} passed
                      </span>
                    )}
                    <span className="history-date">{formatDate(audit.created_at)}</span>
                  </div>
                </div>
                <button
                  className="delete-btn"
                  onClick={(e) => deleteAudit(audit.id, e)}
                  title="Delete"
                >
                  ×
                </button>
              </div>
            ))
          )}
        </div>

        <button 
          className="sidebar-toggle"
          onClick={() => setSidebarOpen(!sidebarOpen)}
        >
          {sidebarOpen ? '◄' : '►'}
        </button>
      </aside>

      {/* Main Content */}
      <main className="main-content">
        <div className="content-wrapper">
          <div className="content-inner">
          {!currentAudit ? (
            // Input Form
            <div className="input-section">
              <h1>Website Audit Tool</h1>
              <p className="subtitle">Analyze your website for CRO, UX, design, and performance</p>
              
              <button 
                className="config-toggle"
                onClick={() => setShowPromptConfig(!showPromptConfig)}
              >
                {showPromptConfig ? '−' : '+'} {showPromptConfig ? 'Hide' : 'Configure'} AI Settings
              </button>

              {showPromptConfig && (
                <div className="prompt-config">
                  <label>
                    <strong>System Prompt</strong>
                    <textarea
                      value={aiPrompts.systemPrompt}
                      onChange={(e) => setAiPrompts({...aiPrompts, systemPrompt: e.target.value})}
                      rows={4}
                      className="prompt-textarea"
                    />
                  </label>
                  
                  <div className="config-row">
                    <label>
                      <strong>Model</strong>
                      <select 
                        value={aiPrompts.model}
                        onChange={(e) => setAiPrompts({...aiPrompts, model: e.target.value})}
                        className="model-select"
                      >
                        <optgroup label="Claude (Anthropic)">
                          <option value="claude-opus-4-6">Claude Opus 4.6 (Default)</option>
                          <option value="claude-sonnet-4-5">Claude Sonnet 4.5</option>
                          <option value="claude-sonnet-3-5">Claude Sonnet 3.5</option>
                          <option value="claude-haiku-4-5">Claude Haiku 4.5</option>
                        </optgroup>
                        <optgroup label="GPT (OpenAI)">
                          <option value="gpt-4o">GPT-4o</option>
                          <option value="gpt-4o-mini">GPT-4o Mini</option>
                          <option value="gpt-4-turbo">GPT-4 Turbo</option>
                        </optgroup>
                      </select>
                    </label>
                    
                    <label>
                      <strong>Temperature ({aiPrompts.temperature})</strong>
                      <input
                        type="range"
                        min="0"
                        max="1"
                        step="0.1"
                        value={aiPrompts.temperature}
                        onChange={(e) => setAiPrompts({...aiPrompts, temperature: parseFloat(e.target.value)})}
                        className="temp-slider"
                      />
                    </label>
                  </div>
                </div>
              )}
              
              <form onSubmit={startAudit} className="audit-form">
                <div className="input-wrapper">
                  <input
                    type="url"
                    value={url}
                    onChange={(e) => setUrl(e.target.value)}
                    placeholder="Enter website URL (e.g., https://example.com)"
                    required
                    disabled={loading}
                    className="url-input"
                  />
                  <label className="crawl-checkbox">
                    <input
                      type="checkbox"
                      checked={fullCrawl}
                      onChange={(e) => setFullCrawl(e.target.checked)}
                    />
                    <span>Full site crawl</span>
                  </label>
                </div>

                {/* Test Selection */}
                <div className="test-selection-section">
                  <div className="test-selection-header">
                    <h3>
                      Select Tests to Run {tests.length === 0 ? (
                        <span className="spinner-small inline-spinner"></span>
                      ) : (
                        `(${selectedTests.length} selected)`
                      )}
                    </h3>
                    <button
                      type="button"
                      onClick={() => setShowTestSelection(!showTestSelection)}
                      className="toggle-tests-btn"
                    >
                      {showTestSelection ? '− Collapse' : '+ Expand'}
                    </button>
                  </div>

                  {showTestSelection && (
                    <div className="test-selection-grid">
                      {testGroups.map(group => {
                        const groupTests = tests.filter(t => t.test_group.id === group.id)
                        const selectedCount = groupTests.filter(t => selectedTests.includes(t.id)).length
                        const allSelected = groupTests.length > 0 && selectedCount === groupTests.length

                        return (
                          <div key={group.id} className="test-group-card">
                            <div className="test-group-header">
                              <label className="group-checkbox">
                                <input
                                  type="checkbox"
                                  checked={allSelected}
                                  onChange={() => toggleGroupSelection(group.id)}
                                />
                                <span className="group-name">{group.name}</span>
                                <span className="group-count">({selectedCount}/{groupTests.length})</span>
                              </label>
                            </div>
                            <div className="test-group-tests">
                              {groupTests.map(test => (
                                <label key={test.id} className="test-checkbox">
                                  <input
                                    type="checkbox"
                                    checked={selectedTests.includes(test.id)}
                                    onChange={() => toggleTestSelection(test.id)}
                                  />
                                  <span className="test-name">{test.name}</span>
                                </label>
                              ))}
                            </div>
                          </div>
                        )
                      })}
                    </div>
                  )}
                </div>
                
                <button
                  type="submit"
                  disabled={loading || !url}
                  className="submit-btn"
                >
                  {loading ? 'Analyzing...' : 'Start Audit'}
                </button>
              </form>

              {error && (
                <div className="error-message">
                  {error}
                </div>
              )}

              {loading && (
                <div className="loading-status">
                  <div className="spinner"></div>
                  <p>Running comprehensive audit...</p>
                  <p className="loading-subtext">This may take a few minutes</p>
                </div>
              )}
            </div>
          ) : loadingAudit ? (
            // Loading State for Audit
            <div className="loading-state">
              <div className="spinner"></div>
              <p className="loading-text">Loading audit...</p>
            </div>
          ) : (
            // Results View
            <div className="results-section">
              <div className="results-header">
                <div className="results-title">
                  <h1>{new URL(currentAudit.url).hostname}</h1>
                  <a href={currentAudit.url} target="_blank" rel="noopener noreferrer" className="visit-link">
                    Visit site →
                  </a>
                </div>
                
                <div className="results-score">
                  <div className="pass-rate-display" style={{ color: getPassRateColor(currentAudit.pass_rate) }}>
                    <div className="pass-rate-text">{currentAudit.passed_tests}/{currentAudit.total_tests} tests passed</div>
                  </div>
                </div>
              </div>

              {/* Test Results */}
              <div className="test-results">
                <h2>Test Results</h2>
                
                {/* Summary Section */}
                {currentAudit.ai_summary && (
                  <div className="audit-summary-section">
                    <h3>Summary</h3>
                    <p className="audit-summary-text">{currentAudit.ai_summary}</p>
                  </div>
                )}
                
                {/* Test Results List */}
                {!currentAudit.test_results || currentAudit.test_results.length === 0 ? (
                  <div className="section-loading">
                    <div className="spinner-small"></div>
                    <p>Loading test results...</p>
                  </div>
                ) : (
                  <div className="tests-list">
                    {currentAudit.test_results.map((test) => (
                      <div key={test.id} className={`test-item test-${test.status}`}>
                        <div 
                          className="test-header"
                          onClick={() => toggleTestExpanded(test.id)}
                        >
                          <div className="test-info">
                            <div className="test-status-badge">{test.status.toUpperCase() == "NOT_APPLICABLE" ? (
                              "N/A"
                            ) : (
                              test.status.toUpperCase()
                            )}</div>
                            <div className="test-name">{test.test_name}</div>
                          </div>
                          <span className={`expand-icon ${expandedTests[test.id] ? 'expanded' : ''}`}>+</span>
                        </div>
                        
                        {expandedTests[test.id] && (
                          <div className="test-details-expanded">
                            <div className="test-summary">{test.summary}</div>
                            {test.data_sources && test.data_sources.length > 0 && (
                              <div className="data-sources">
                                <span className="data-sources-label">Data Sources:</span>
                                <div className="data-source-icons">
                                  {test.data_sources.map((source) => (
                                    <span 
                                      key={source} 
                                      className="data-source-icon"
                                      title={sourceLabels[source] || source}
                                      dangerouslySetInnerHTML={{__html: getDataSourceIcon(source)}}
                                    />
                                  ))}
                                </div>
                              </div>
                            )}
                            
                            {/* AI Debug Info */}
                            {(test.ai_prompt || test.data_context || test.ai_response) && (
                              <details className="ai-debug-section">
                                <summary>
                                  <span className="summary-text">View Prompt Details</span>
                                  <span className="expand-icon">+</span>
                                </summary>
                                <div className="ai-debug-content">
                                  {test.ai_prompt && (
                                    <div className="debug-block">
                                      <h4>Full AI Prompt</h4>
                                      <pre className="debug-pre">{test.ai_prompt}</pre>
                                    </div>
                                  )}
                                  {test.data_context && Object.keys(test.data_context).length > 0 && (
                                    <div className="debug-block">
                                      <h4>Data Context</h4>
                                      <pre className="debug-pre">{JSON.stringify(test.data_context, null, 2)}</pre>
                                    </div>
                                  )}
                                  {test.ai_response && (
                                    <div className="debug-block">
                                      <h4>AI Response</h4>
                                      <pre className="debug-pre">{test.ai_response}</pre>
                                    </div>
                                  )}
                                </div>
                              </details>
                            )}
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                )}
                
                {/* Screenshots */}
                {currentAudit.pages && currentAudit.pages.length > 0 && currentAudit.pages[0].screenshots && (
                  <div className="screenshots-section">
                    <h3>Page Screenshots</h3>
                    <div className="screenshots-grid">
                      {currentAudit.pages[0].screenshots.desktop && (
                        <div className="screenshot-item" onClick={() => openLightbox(`http://localhost:3000${currentAudit.pages[0].screenshots.desktop}`, 'Desktop')}>
                          <div className="screenshot-label">Desktop</div>
                          <img src={`http://localhost:3000${currentAudit.pages[0].screenshots.desktop}`} alt="Desktop screenshot" />
                        </div>
                      )}
                      {currentAudit.pages[0].screenshots.mobile && (
                        <div className="screenshot-item" onClick={() => openLightbox(`http://localhost:3000${currentAudit.pages[0].screenshots.mobile}`, 'Mobile')}>
                          <div className="screenshot-label">Mobile</div>
                          <img src={`http://localhost:3000${currentAudit.pages[0].screenshots.mobile}`} alt="Mobile screenshot" />
                        </div>
                      )}
                    </div>
                  </div>
                )}
                
                {/* Page Data Viewer */}
                {currentAudit.pages && currentAudit.pages.length > 0 && (
                  <details className="page-data-section">
                    <summary>
                      <span className="summary-text">View Comprehensive Page Details</span>
                      <span className="expand-icon">+</span>
                    </summary>
                    <div className="page-data-content">
                      <div className="page-data-header">
                        <button 
                          className="copy-data-btn" 
                          onClick={() => copyPageData()}
                          title="Copy to clipboard"
                        >
                          Copy
                        </button>
                      </div>
                      <pre>{JSON.stringify(currentAudit.pages[0].page_data, null, 2)}</pre>
                    </div>
                  </details>
                )}

                {/* Wireframes Section */}
                {currentAudit.pages && currentAudit.pages.length > 0 && currentAudit.pages[0].page_data && (
                  <div className="wireframes-section">
                    <div className="wireframes-header">
                      <h3>Wireframes</h3>
                      <button 
                        className="generate-wireframes-btn"
                        onClick={() => setShowWireframeModal(true)}
                        disabled={loadingWireframes}
                      >
                        Generate Wireframe Variations
                      </button>
                    </div>
                    
                    {loadingWireframes && wireframes.length === 0 && !wireframesGenerating && (
                      <div className="wireframes-loading">Loading wireframes...</div>
                    )}
                    
                    {!loadingWireframes && wireframes.length === 0 && !wireframesGenerating && (
                      <div className="wireframes-empty">
                        No wireframes generated yet. Click the button above to create variations.
                      </div>
                    )}
                    
                    {(wireframes.length > 0 || wireframesGenerating) && (
                      <div className="wireframes-grid">
                        {/* Show generating placeholders */}
                        {wireframesGenerating && (() => {
                          // Count only wireframes from current generation batch
                          const currentBatchCount = generationStartedAt 
                            ? wireframes.filter(w => new Date(w.created_at) >= new Date(generationStartedAt)).length
                            : 0
                          const placeholdersNeeded = Math.max(0, wireframesExpected - currentBatchCount)
                          
                          return Array.from({ length: placeholdersNeeded }).map((_, idx) => (
                            <div key={`generating-${idx}`} className="wireframe-card generating">
                              <div className="wireframe-preview">
                                <div className="spinner"></div>
                              </div>
                              <div className="wireframe-info">
                                <div className="wireframe-title">Generating...</div>
                                <div className="wireframe-date">In progress</div>
                              </div>
                            </div>
                          ))
                        })()}
                        
                        {/* Show generated wireframes */}
                        {wireframes.map(wireframe => (
                          <div key={wireframe.id} className="wireframe-card">
                            <div className="wireframe-preview" onClick={() => openWireframe(wireframe.url)}>
                              <div className="wireframe-preview-placeholder">
                                <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                                  <rect x="3" y="3" width="18" height="18" rx="2"/>
                                  <line x1="9" y1="9" x2="15" y2="9"/>
                                  <line x1="9" y1="12" x2="15" y2="12"/>
                                  <line x1="9" y1="15" x2="12" y2="15"/>
                                </svg>
                              </div>
                            </div>
                            <div className="wireframe-info">
                              <div className="wireframe-title-row">
                                <div className="wireframe-title" title={wireframe.title}>{wireframe.title}</div>
                                {wireframe.config_used?.design_philosophy && (
                                  <div
                                    className="wireframe-info-icon"
                                    title="View design brief"
                                    onClick={(e) => { e.stopPropagation(); setDesignBriefWireframe(wireframe) }}
                                  >
                                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                                      <circle cx="12" cy="12" r="10"/>
                                      <line x1="12" y1="16" x2="12" y2="12"/>
                                      <line x1="12" y1="8" x2="12.01" y2="8"/>
                                    </svg>
                                  </div>
                                )}
                              </div>
                              <div className="wireframe-date">
                                {new Date(wireframe.created_at).toLocaleDateString()}
                              </div>
                            </div>
                            <div className="wireframe-actions">
                              <button 
                                className="wireframe-regen-btn"
                                onClick={() => {
                                  setRegenerateTarget({ wireframeId: wireframe.id, title: wireframe.title })
                                  setRegeneratePrompt('')
                                  setRegenerateSelector('')
                                }}
                                title="Regenerate with changes"
                              >
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                                  <polyline points="23 4 23 10 17 10"/>
                                  <polyline points="1 20 1 14 7 14"/>
                                  <path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/>
                                </svg>
                              </button>
                              <button 
                                className="wireframe-view-btn"
                                onClick={() => openWireframe(wireframe.url)}
                                title="Open in new tab"
                              >
                                View
                              </button>
                              <button 
                                className="wireframe-delete-btn"
                                onClick={() => deleteWireframe(wireframe.id)}
                                title="Delete wireframe"
                              >
                                Delete
                              </button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </div>
            </div>
          )}
          </div>
        </div>
      </main>

      {/* Lightbox */}
      {lightboxImage && (
        <div className="lightbox-overlay" onClick={closeLightbox}>
          <button className="lightbox-close" onClick={closeLightbox}>×</button>
          <div className="lightbox-content" onClick={(e) => e.stopPropagation()}>
            <img src={lightboxImage.src} alt={lightboxImage.label} />
            <div className="lightbox-label">{lightboxImage.label}</div>
          </div>
        </div>
      )}

      {/* Wireframe Config Modal */}
      {showWireframeModal && currentAudit && (
        <WireframeConfigModal
          isOpen={showWireframeModal}
          onClose={() => setShowWireframeModal(false)}
          auditId={currentAudit.id}
          pageData={currentAudit.pages[0].page_data}
          audit={currentAudit}
          onGenerate={handleWireframeGenerate}
        />
      )}

      {/* Design Brief Modal */}
      {designBriefWireframe && (() => {
        const dp = designBriefWireframe.config_used?.design_patterns
        const philosophy = designBriefWireframe.config_used?.design_philosophy
        return (
          <div className="modal-overlay" onClick={() => setDesignBriefWireframe(null)}>
            <div className="design-brief-modal" onClick={e => e.stopPropagation()}>
              <div className="design-brief-header">
                <div>
                  <h3>Design Brief</h3>
                  <p className="design-brief-subtitle">{designBriefWireframe.title}</p>
                </div>
                <button className="modal-close-btn" onClick={() => setDesignBriefWireframe(null)}>&times;</button>
              </div>
              <div className="design-brief-body">
                {philosophy && (
                  <div className="design-brief-section">
                    <h4>Design Philosophy</h4>
                    <p>{philosophy}</p>
                  </div>
                )}
                {dp?.font_pairing_strategy && (
                  <div className="design-brief-section">
                    <h4>Typography Strategy</h4>
                    <p>{dp.font_pairing_strategy}</p>
                  </div>
                )}
                {dp?.typography && (
                  <div className="design-brief-section">
                    <h4>Type Scale</h4>
                    <div className="design-brief-grid">
                      {Object.entries(dp.typography).filter(([k]) => k !== 'font_family').map(([key, val]) => (
                        <div key={key} className="design-brief-token">
                          <span className="token-name">{key}</span>
                          <span className="token-value">{typeof val === 'object' ? `${val.size} / ${val.weight}` : val}</span>
                        </div>
                      ))}
                    </div>
                    {dp.typography.font_family && <p className="design-brief-font">Font: {dp.typography.font_family}</p>}
                  </div>
                )}
                {dp?.spacing && (
                  <div className="design-brief-section">
                    <h4>Spacing</h4>
                    <div className="design-brief-grid">
                      {Object.entries(dp.spacing).map(([key, val]) => (
                        <div key={key} className="design-brief-token">
                          <span className="token-name">{key.replace(/_/g, ' ')}</span>
                          <span className="token-value">{val}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
                {dp?.layout && (
                  <div className="design-brief-section">
                    <h4>Layout</h4>
                    <div className="design-brief-grid">
                      <div className="design-brief-token">
                        <span className="token-name">system</span>
                        <span className="token-value">{dp.layout.system}</span>
                      </div>
                      <div className="design-brief-token">
                        <span className="token-name">max width</span>
                        <span className="token-value">{dp.layout.container_max_width}</span>
                      </div>
                    </div>
                    {dp.layout.sections?.length > 0 && (
                      <div className="design-brief-sections-list">
                        {dp.layout.sections.map((s, i) => (
                          <div key={i} className="design-brief-section-item">
                            <span className="section-type-badge">{s.type}</span>
                            <span className="section-layout-desc">{s.layout}</span>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                )}
                {dp?.components?.length > 0 && (
                  <div className="design-brief-section">
                    <h4>Components</h4>
                    <div className="design-brief-components">
                      {dp.components.map((c, i) => (
                        <div key={i} className="design-brief-component">
                          <div className="component-name">{c.name}</div>
                          {c.structure && <p className="component-detail"><strong>Structure:</strong> {c.structure}</p>}
                          {c.styling && <p className="component-detail"><strong>Styling:</strong> {c.styling}</p>}
                        </div>
                      ))}
                    </div>
                  </div>
                )}
                {dp?.responsive && (
                  <div className="design-brief-section">
                    <h4>Responsive</h4>
                    {dp.responsive.breakpoints && <p><strong>Breakpoints:</strong> {dp.responsive.breakpoints.join(', ')}</p>}
                    {dp.responsive.mobile_patterns && <p>{dp.responsive.mobile_patterns}</p>}
                  </div>
                )}
                {!dp && !philosophy && (
                  <p className="design-brief-empty">No design brief available for this wireframe. Regenerate it to capture full design patterns.</p>
                )}
              </div>
            </div>
          </div>
        )
      })()}

      {/* Regenerate Prompt Modal */}
      {regenerateTarget && !showRegenerateStreaming && (
        <div className="modal-overlay" onClick={() => setRegenerateTarget(null)}>
          <div className="regenerate-modal" onClick={e => e.stopPropagation()}>
            <div className="regenerate-modal-header">
              <h3>Regenerate Wireframe</h3>
              <button className="modal-close-btn" onClick={() => setRegenerateTarget(null)}>&times;</button>
            </div>
            <div className="regenerate-modal-body">
              <p className="regenerate-source">Based on: <strong>{regenerateTarget.title}</strong></p>
              <label className="regenerate-label">What changes would you like?</label>
              <textarea
                className="regenerate-textarea"
                value={regeneratePrompt}
                onChange={e => setRegeneratePrompt(e.target.value)}
                placeholder="e.g. Make the hero section more impactful, use larger product images, add more social proof..."
                rows={4}
                autoFocus
              />
              <label className="regenerate-label" style={{ marginTop: '14px' }}>Target section <span className="regenerate-optional">(optional)</span></label>
              <input
                className="regenerate-selector-input"
                type="text"
                value={regenerateSelector}
                onChange={e => setRegenerateSelector(e.target.value)}
                placeholder="CSS selector — e.g. nav, .hero, #footer, section.pricing"
              />
              <p className="regenerate-selector-hint">Only this element will be regenerated and patched into the live preview</p>
            </div>
            <div className="regenerate-modal-footer">
              <button className="btn-secondary" onClick={() => setRegenerateTarget(null)}>Cancel</button>
              <button
                className="btn-primary"
                onClick={() => setShowRegenerateStreaming(true)}
              >
                Regenerate with Live Preview
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Regenerate Streaming Modal */}
      {showRegenerateStreaming && regenerateTarget && (
        <WireframeStreamingModal
          isOpen={true}
          onClose={(success) => {
            setShowRegenerateStreaming(false)
            setRegenerateTarget(null)
            if (success && currentAudit?.id) {
              loadWireframes(currentAudit.id)
            }
          }}
          auditId={currentAudit?.id}
          config={{ custom_prompt: regeneratePrompt, css_selector: regenerateSelector }}
          sectionSelector={regenerateSelector}
          regenerateWireframeId={regenerateTarget.wireframeId}
        />
      )}
    </div>
  )
}

export default App
