import { useState, useEffect } from 'react'
import './App.css'
import './insights.css'
import './test-results.css'

function App() {
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

  const API_BASE = 'http://localhost:3000'

  useEffect(() => {
    loadAuditHistory()
  }, [])

  const loadAuditHistory = async () => {
    try {
      const response = await fetch(`${API_BASE}/audits`)
      const data = await response.json()
      setAudits(data.audits || [])
    } catch (err) {
      console.error('Failed to load audit history', err)
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
            audit_mode: fullCrawl ? 'full_crawl' : 'single_page'
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
    try {
      const response = await fetch(`${API_BASE}/audits/${auditId}`)
      const data = await response.json()
      setCurrentAudit(data)
      setUrl(data.url)
      setExpandedCategories({})
      setSelectedPageId(data.all_pages?.[0]?.id || null)
    } catch (err) {
      setError('Failed to load audit')
    }
  }

  const deleteAudit = async (auditId, e) => {
    e.stopPropagation()
    if (!confirm('Delete this audit?')) return

    setDeletingAudits(prev => [...prev, auditId])

    try {
      await fetch(`${API_BASE}/audits/${auditId}`, { method: 'DELETE' })
      
      if (currentAudit?.id === auditId) {
        setCurrentAudit(null)
        setUrl('')
      }
      
      setTimeout(() => {
        setDeletingAudits(prev => prev.filter(id => id !== auditId))
        loadAuditHistory()
      }, 1000)
    } catch (err) {
      setError('Failed to delete audit')
    }
  }

  const startNewAudit = () => {
    setCurrentAudit(null)
    setUrl('')
    setError(null)
    setExpandedCategories({})
    setSelectedPageId(null)
  }

  const toggleCategory = (category) => {
    setExpandedCategories(prev => ({
      ...prev,
      [category]: !prev[category]
    }))
  }

  const getScoreColor = (score) => {
    if (score >= 80) return '#19C798'
    if (score >= 60) return '#F4C085'
    return '#CE6262'
  }

  const getCategoryIcon = (category) => {
    const icons = {
      nav: '🧭',
      structure: '🏗️',
      cro: '📈',
      design: '🎨',
      reviews: '⭐',
      price: '💰',
      speed: '⚡'
    }
    return icons[category] || '📋'
  }

  const formatDate = (dateString) => {
    const date = new Date(dateString)
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
  }

  const getStatusBadge = (status) => {
    const badges = {
      passed: { label: 'Passed', color: '#19C798' },
      failed: { label: 'Failed', color: '#CE6262' },
      warning: { label: 'Warning', color: '#F4C085' },
      not_applicable: { label: 'N/A', color: '#999' }
    }
    return badges[status] || badges.not_applicable
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
          {audits.map((audit) => (
            <div
              key={audit.id}
              className={`history-item ${currentAudit?.id === audit.id ? 'active' : ''} ${deletingAudits.includes(audit.id) ? 'deleting' : ''}`}
              onClick={() => !deletingAudits.includes(audit.id) && loadAudit(audit.id)}
            >
              <div className="history-item-content">
                <div className="history-item-url">{new URL(audit.url).hostname}</div>
                <div className="history-item-meta">
                  {audit.status === 'complete' && audit.overall_score && (
                    <span className="history-score" style={{ color: getScoreColor(audit.overall_score) }}>
                      {audit.overall_score}
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
          ))}
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
          {!currentAudit ? (
            // Input Form
            <div className="input-section">
              <h1>Website Audit Tool</h1>
              <p className="subtitle">Analyze your website for CRO, UX, design, and performance</p>
              
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
                  <label className="crawl-checkbox" title="Full crawl mode coming soon">
                    <input
                      type="checkbox"
                      checked={fullCrawl}
                      onChange={(e) => setFullCrawl(e.target.checked)}
                      disabled={true}
                    />
                    <span style={{ opacity: 0.5 }}>Full site crawl</span>
                  </label>
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
                  <div className="score-circle" style={{ borderColor: getScoreColor(currentAudit.overall_score) }}>
                    <div className="score-value">{currentAudit.overall_score}</div>
                    <div className="score-label">Score</div>
                  </div>
                </div>
              </div>

              {/* Category Scores */}
              <div className="category-scores">
                {Object.entries(currentAudit.category_scores || {}).map(([category, score]) => (
                  <div key={category} className="category-score-card">
                    <div className="category-icon">{getCategoryIcon(category)}</div>
                    <div className="category-info">
                      <div className="category-name">{category.replace('_', ' ').toUpperCase()}</div>
                      <div className="category-score" style={{ color: getScoreColor(score) }}>
                        {score}%
                      </div>
                    </div>
                  </div>
                ))}
              </div>

              {/* Test Results */}
              <div className="test-results">
                <h2>Test Results</h2>
                
                {currentAudit.test_results && Object.entries(currentAudit.test_results).map(([category, categoryData]) => (
                  <div key={category} className="category-section">
                    <div 
                      className="category-header"
                      onClick={() => toggleCategory(category)}
                    >
                      <div className="category-title">
                        <span className="category-icon">{getCategoryIcon(category)}</span>
                        <h3>{category.replace('_', ' ').toUpperCase()}</h3>
                        <span className="test-count">
                          {categoryData.passed} passed, {categoryData.failed} failed, {categoryData.warning} warnings
                        </span>
                      </div>
                      <span className="expand-icon">{expandedCategories[category] ? '−' : '+'}</span>
                    </div>

                    {expandedCategories[category] && (
                      <div className="tests-list">
                        {categoryData.tests.map((test) => (
                          <div key={test.test_key} className={`test-item test-${test.status}`}>
                            <div className="test-header">
                              <div className="test-info">
                                <div className="test-name">{test.test_name}</div>
                                <div className="test-summary">{test.summary}</div>
                              </div>
                              <div className="test-status">
                                <span 
                                  className="status-badge"
                                  style={{ backgroundColor: getStatusBadge(test.status).color }}
                                >
                                  {getStatusBadge(test.status).label}
                                </span>
                                {test.score !== null && (
                                  <span className="test-score">{test.score}/100</span>
                                )}
                              </div>
                            </div>

                            {test.recommendation && (
                              <div className="test-recommendation">
                                <strong>Recommendation:</strong> {test.recommendation}
                              </div>
                            )}

                            {test.details && Object.keys(test.details).length > 0 && (
                              <details className="test-details">
                                <summary>View Details</summary>
                                <pre>{JSON.stringify(test.details, null, 2)}</pre>
                              </details>
                            )}
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </main>
    </div>
  )
}

export default App
