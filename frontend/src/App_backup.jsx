import { useState, useEffect } from 'react'
import { ComprehensiveData } from './ComprehensiveData'
import './App.css'
import './insights_extra.css'
import './insights.css'

function App() {
  const [url, setUrl] = useState('')
  const [loading, setLoading] = useState(false)
  const [currentAudit, setCurrentAudit] = useState(null)
  const [audits, setAudits] = useState([])
  const [error, setError] = useState(null)
  const [polling, setPolling] = useState(false)
  const [sidebarOpen, setSidebarOpen] = useState(true)
  const [expandedTests, setExpandedTests] = useState({})
  const [selectedPageId, setSelectedPageId] = useState(null)
  const [lightboxImage, setLightboxImage] = useState(null)
  const [currentView, setCurrentView] = useState('summary') // 'summary' or 'pages'
  const [deletingAudits, setDeletingAudits] = useState([])

  const API_BASE = 'http://localhost:3000'

  // Load audit history on mount
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
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ audit: { url } }),
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.errors?.[0] || 'Failed to start audit')
      }

      // Start polling for results
      pollAuditStatus(data.id)
    } catch (err) {
      setError(err.message)
      setLoading(false)
    }
  }

  const pollAuditStatus = async (auditId) => {
    setPolling(true)
    const maxAttempts = 60
    let attempts = 0

    const poll = async () => {
      try {
        const response = await fetch(`${API_BASE}/audits/${auditId}`)
        const data = await response.json()

        if (data.status === 'complete') {
          setCurrentAudit(data)
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
        setError('Failed to fetch audit results')
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
      setExpandedTests({})
      // Select first page by default
      if (data.all_pages && data.all_pages.length > 0) {
        setSelectedPageId(data.all_pages[0].id)
      } else {
        setSelectedPageId(null)
      }
    } catch (err) {
      setError('Failed to load audit')
    }
  }

  const deleteAudit = async (auditId, e) => {
    e.stopPropagation()
    if (!confirm('Delete this audit?')) return

    // Start deletion animation
    setDeletingAudits(prev => [...prev, auditId])

    try {
      await fetch(`${API_BASE}/audits/${auditId}`, {
        method: 'DELETE',
      })
      
      if (currentAudit?.id === auditId) {
        setCurrentAudit(null)
        setUrl('')
      }
      
      // Wait for animation to complete before removing from list
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
    setExpandedTests({})
    setSelectedPageId(null)
  }

  const toggleTests = (pageId) => {
    setExpandedTests(prev => ({
      ...prev,
      [pageId]: !prev[pageId]
    }))
  }

  const selectPage = (pageId) => {
    setSelectedPageId(pageId)
    setCurrentView('pages')
  }

  const analyzePage = async (pageId) => {
    if (!currentAudit) return
    
    try {
      const response = await fetch(`${API_BASE}/audits/${currentAudit.id}/discovered_pages/${pageId}/analyze`, {
        method: 'POST'
      })
      
      if (!response.ok) {
        throw new Error('Failed to start analysis')
      }
      
      // Update page status in current audit
      setCurrentAudit(prev => ({
        ...prev,
        all_pages: prev.all_pages.map(p => 
          p.id === pageId ? { ...p, status: 'analyzing' } : p
        )
      }))
      
      // Start polling for this page
      pollPageAnalysis(pageId)
    } catch (err) {
      setError(err.message)
    }
  }

  const pollPageAnalysis = async (pageId) => {
    const maxAttempts = 40
    let attempts = 0

    const poll = async () => {
      try {
        const response = await fetch(`${API_BASE}/audits/${currentAudit.id}`)
        const data = await response.json()
        
        const page = data.all_pages?.find(p => p.id === pageId)
        
        if (page && page.status === 'complete') {
          setCurrentAudit(data)
          return
        }

        attempts++
        if (attempts < maxAttempts) {
          setTimeout(poll, 3000)
        }
      } catch (err) {
        console.error('Failed to poll page analysis', err)
      }
    }

    poll()
  }

  const getTestDetails = (pageUrl) => {
    if (!currentAudit?.page_test_details) return null
    return currentAudit.page_test_details.find(p => p.page_url === pageUrl)
  }

  const getScoreColor = (score) => {
    if (score >= 80) return '#19C798'
    if (score >= 60) return '#F4C085'
    return '#CE6262'
  }

  const formatDate = (dateString) => {
    const date = new Date(dateString)
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
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

      {/* Lightbox Modal */}
      {lightboxImage && (
        <div className="lightbox-overlay" onClick={() => setLightboxImage(null)}>
          <button className="lightbox-close" onClick={() => setLightboxImage(null)}>
            ×
          </button>
          <div className="lightbox-content" onClick={(e) => e.stopPropagation()}>
            <div className="lightbox-info">
              <span className="lightbox-device">
                {lightboxImage.device === 'desktop' ? 'Desktop' : 'Mobile'}
              </span>
              <span className="lightbox-viewport">{lightboxImage.viewport}</span>
            </div>
            <img 
              src={lightboxImage.url} 
              alt="Full size screenshot"
              className="lightbox-image"
            />
          </div>
        </div>
      )}

      {/* Main Content */}
      <main className="main-content">
        <div className="content-wrapper">
          {!currentAudit && !loading && (
            <div className="welcome-screen">
              <div className="welcome-content">
                <h1 className="welcome-title">Site Auditor</h1>
                <p className="welcome-subtitle">Comprehensive website analysis for digital agencies</p>

                <form onSubmit={startAudit} className="audit-form-center">
                  <div className="input-wrapper">
                    <input
                      type="url"
                      value={url}
                      onChange={(e) => setUrl(e.target.value)}
                      placeholder="Enter website URL (e.g., https://example.com)"
                      required
                      disabled={loading}
                      className="url-input-center"
                    />
                    <button type="submit" disabled={loading} className="submit-btn-center">
                      Analyze
                    </button>
                  </div>
                </form>

                {error && (
                  <div className="error-message-center">
                    {error}
                  </div>
                )}
              </div>
            </div>
          )}

          {loading && (
            <div className="loading-state">
              <div className="spinner"></div>
              <p className="loading-text">Running comprehensive audit...</p>
              <p className="loading-subtext">Analyzing pages, running tests, generating insights...</p>
            </div>
          )}

          {currentAudit && !loading && (
            <div className="results-view">
              <div className="results-header">
                <div className="results-header-content">
                  <h1 className="results-title">CRO Audit Report</h1>
                  <a href={currentAudit.url} target="_blank" rel="noopener noreferrer" className="audit-url-link">
                    {currentAudit.url}
                  </a>
                  <div className="audit-date">
                    {new Date(currentAudit.created_at).toLocaleDateString('en-US', { 
                      month: 'long', day: 'numeric', year: 'numeric' 
                    })}
                  </div>
                </div>
                {currentAudit.overall_score && (
                  <div className="header-score">
                    <div className="score-circle-small" style={{ borderColor: getScoreColor(currentAudit.overall_score) }}>
                      <span className="score-number">{currentAudit.overall_score}</span>
                    </div>
                  </div>
                )}
              </div>

              <div className="results-content-with-nav">
                {/* All Pages Navigation */}
                {currentAudit.all_pages && currentAudit.all_pages.length > 0 && (
                  <aside className="pages-navigation">
                    <div 
                      className={`summary-nav-link ${currentView === 'summary' ? 'active' : ''}`}
                      onClick={() => { setCurrentView('summary'); setSelectedPageId(null); }}
                    >
                      Summary
                    </div>
                    <div className="pages-nav-header">All Pages</div>
                    <ul className="pages-list">
                      {[...currentAudit.all_pages]
                        .sort((a, b) => (b.priority_score || 0) - (a.priority_score || 0))
                        .map(page => (
                        <li 
                          key={page.id} 
                          className={`page-nav-item ${page.priority_score >= 70 ? 'priority-page' : ''} ${selectedPageId === page.id ? 'selected' : ''}`}
                          onClick={() => selectPage(page.id)}
                        >
                          <div className="page-nav-content">
                            <span className="page-nav-path">
                              {new URL(page.url).pathname || '/'}
                            </span>
                            <span className={`page-nav-type ${page.page_type}`}>
                              {page.page_type}
                            </span>
                          </div>
                          <div className="page-nav-footer">
                            <span className="page-nav-backlinks">
                              {page.inbound_links || 0} links
                            </span>
                            {page.status === 'analyzing' && (
                              <span className="page-analyzing-badge">...</span>
                            )}
                            {page.status === 'complete' && (
                              <span className="page-analyzed-badge">✓</span>
                            )}
                          </div>
                        </li>
                      ))}
                    </ul>
                  </aside>
                )}

                <div className="results-content">
                  {/* Summary View */}
                  {currentView === 'summary' && currentAudit.all_pages && (
                    <section className="summary-view">
                      <h2>Website Analysis Summary</h2>
                      
                      <div className="summary-overview">
                        <div className="summary-stat">
                          <span className="stat-number">{currentAudit.all_pages.length}</span>
                          <span className="stat-label">Pages Discovered</span>
                        </div>
                        <div className="summary-stat">
                          <span className="stat-number">{currentAudit.all_pages.filter(p => p.status === 'complete').length}</span>
                          <span className="stat-label">Pages Analyzed</span>
                        </div>
                        <div className="summary-stat">
                          <span className="stat-number">{currentAudit.all_pages.filter(p => p.priority_score >= 70).length}</span>
                          <span className="stat-label">High Priority</span>
                        </div>
                      </div>

                      <div className="priority-pages-section">
                        <h3>Top Priority Pages</h3>
                        <div className="priority-pages-list">
                          {[...currentAudit.all_pages]
                            .sort((a, b) => (b.priority_score || 0) - (a.priority_score || 0))
                            .slice(0, 5)
                            .map(page => (
                              <div 
                                key={page.id} 
                                className="priority-page-card"
                                onClick={() => { setCurrentView('pages'); selectPage(page.id); }}
                              >
                                <div className="priority-card-header">
                                  <span className={`page-type-pill ${page.page_type}`}>{page.page_type}</span>
                                  <span className="priority-score" style={{ color: getScoreColor(page.priority_score) }}>
                                    {page.priority_score}
                                  </span>
                                </div>
                                <div className="priority-card-url">{page.url}</div>
                                <div className="priority-card-stats">
                                  <span>{page.inbound_links || 0} inbound links</span>
                                  {page.status === 'complete' && <span className="status-badge complete">✓ Analyzed</span>}
                                  {page.status === 'pending' && <span className="status-badge pending">Pending</span>}
                                </div>
                              </div>
                            ))}
                        </div>
                      </div>

                      {/* Overall insights from analyzed pages */}
                      {(() => {
                        const analyzedPages = currentAudit.all_pages.filter(p => p.comprehensive_metrics)
                        if (analyzedPages.length === 0) return null

                        // Aggregate data
                        const totalImages = analyzedPages.reduce((sum, p) => sum + (p.comprehensive_metrics?.asset_metrics?.image_count || 0), 0)
                        const imagesWithoutAlt = analyzedPages.reduce((sum, p) => sum + (p.comprehensive_metrics?.asset_metrics?.images_without_alt || 0), 0)
                        const pagesWithoutMeta = analyzedPages.filter(p => !p.comprehensive_metrics?.technical_metrics?.meta_description || p.comprehensive_metrics?.technical_metrics?.meta_description_length === 0).length
                        const pagesWithoutOg = analyzedPages.filter(p => !p.comprehensive_metrics?.technical_metrics?.og_tags_present).length
                        const avgH1Count = (analyzedPages.reduce((sum, p) => sum + (p.comprehensive_metrics?.content_metrics?.heading_counts?.h1 || 0), 0) / analyzedPages.length).toFixed(1)
                        const pagesWithMultipleH1 = analyzedPages.filter(p => (p.comprehensive_metrics?.content_metrics?.heading_counts?.h1 || 0) > 1).length
                        
                        return (
                          <div className="overall-insights">
                            <h3>Key Findings</h3>
                            <div className="findings-grid">
                              {imagesWithoutAlt > 0 && (
                                <div className="finding-card warning">
                                  <div className="finding-icon">⚠️</div>
                                  <div className="finding-content">
                                    <div className="finding-title">Accessibility Issue</div>
                                    <div className="finding-desc">{imagesWithoutAlt} of {totalImages} images missing alt text across {analyzedPages.length} pages</div>
                                  </div>
                                </div>
                              )}
                              {pagesWithoutMeta > 0 && (
                                <div className="finding-card warning">
                                  <div className="finding-icon">📝</div>
                                  <div className="finding-content">
                                    <div className="finding-title">SEO Issue</div>
                                    <div className="finding-desc">{pagesWithoutMeta} pages missing meta descriptions</div>
                                  </div>
                                </div>
                              )}
                              {pagesWithoutOg > 0 && (
                                <div className="finding-card info">
                                  <div className="finding-icon">🔗</div>
                                  <div className="finding-content">
                                    <div className="finding-title">Social Sharing</div>
                                    <div className="finding-desc">{pagesWithoutOg} pages without Open Graph tags</div>
                                  </div>
                                </div>
                              )}
                              {pagesWithMultipleH1 > 0 && (
                                <div className="finding-card warning">
                                  <div className="finding-icon">📊</div>
                                  <div className="finding-content">
                                    <div className="finding-title">Content Structure</div>
                                    <div className="finding-desc">{pagesWithMultipleH1} pages with multiple H1 tags (avg: {avgH1Count})</div>
                                  </div>
                                </div>
                              )}
                              {imagesWithoutAlt === 0 && totalImages > 0 && (
                                <div className="finding-card success">
                                  <div className="finding-icon">✓</div>
                                  <div className="finding-content">
                                    <div className="finding-title">Accessibility</div>
                                    <div className="finding-desc">All {totalImages} images have alt text</div>
                                  </div>
                                </div>
                              )}
                            </div>
                          </div>
                        )
                      })()}
                    </section>
                  )}

                  {/* Page-by-Page Insights */}
                  {currentView === 'pages' && currentAudit.all_pages && currentAudit.all_pages.length > 0 && selectedPageId && (() => {
                    const page = currentAudit.all_pages.find(p => p.id === selectedPageId)
                    if (!page) return null
                    
                    const pageInsight = currentAudit.page_insights?.find(p => p.page_url === page.url)
                    const testDetails = getTestDetails(page.url)
                    
                    return (
                      <section className="page-insights-section">
                        <h2>Page Analysis</h2>
                        <div className="page-insight-card">
                            <div className="page-insight-header">
                              <div className="page-insight-title">
                                <span className={`page-type-pill ${page.page_type}`}>
                                  {page.page_type}
                                </span>
                                <h3>{new URL(page.url).pathname || '/'}</h3>
                              </div>
                              {page.priority_score && (
                                <div className="page-priority-badge" style={{ color: getScoreColor(page.priority_score) }}>
                                  Priority: {page.priority_score}
                                </div>
                              )}
                            </div>
                            
                            <div className="page-url-small">{page.url}</div>

                            {/* Analyze Button for unanalyzed pages */}
                            {page.status === 'analyzing' && (
                              <div className="analyze-prompt analyzing">
                                <div className="spinner"></div>
                                <p>Analyzing page and capturing screenshots...</p>
                              </div>
                            )}
                            
                            {page.status !== 'complete' && page.status !== 'analyzing' && !page.comprehensive_metrics && (
                              <div className="analyze-prompt">
                                <p>This page hasn't been analyzed yet.</p>
                                <button 
                                  className="analyze-btn"
                                  onClick={() => analyzePage(page.id)}
                                  disabled={page.status === 'analyzing'}
                                >
                                  Generate Insights & Screenshots
                                </button>
                              </div>
                            )}

                            {/* AI Summary */}
                            {page.ai_summary && (
                              <div className="ai-summary-box">
                                <h4>Summary</h4>
                                <p>{page.ai_summary}</p>
                              </div>
                            )}

                            {/* Screenshots */}
                            {page.screenshots && page.screenshots.length > 0 && (
                              <div className="screenshots-section">
                                <h4>Screenshots</h4>
                                <div className="screenshots-grid">
                                  {page.screenshots.map((screenshot, idx) => (
                                    <div key={idx} className="screenshot-item">
                                      <div className="screenshot-label">
                                        {screenshot.device_type === 'desktop' ? 'Desktop' : 'Mobile'}
                                        <span className="viewport-size">
                                          {screenshot.viewport_width}×{screenshot.viewport_height}
                                        </span>
                                      </div>
                                      <img 
                                        src={`http://localhost:3000${screenshot.screenshot_url}`}
                                        alt={`${screenshot.device_type} screenshot`}
                                        className="screenshot-image clickable"
                                        onClick={() => setLightboxImage({
                                          url: `http://localhost:3000${screenshot.screenshot_url}`,
                                          device: screenshot.device_type,
                                          viewport: `${screenshot.viewport_width}×${screenshot.viewport_height}`
                                        })}
                                        onError={(e) => {
                                          e.target.style.display = 'none';
                                          e.target.nextElementSibling.style.display = 'flex';
                                        }}
                                      />
                                      <div className="screenshot-placeholder" style={{ display: 'none' }}>
                                        Screenshot not available
                                      </div>
                                    </div>
                                  ))}
                                </div>
                              </div>
                            )}

                            {/* Comprehensive Data */}
                            {page.comprehensive_metrics && (
                              <ComprehensiveData metrics={page.comprehensive_metrics} />
                            )}

                            {/* Simple Tests */}
                            {page.simple_tests && page.simple_tests.length > 0 && (
                              <div className="simple-tests-section">
                                <h4>Quality Checks</h4>
                                <div className="tests-grid">
                                  {page.simple_tests.map((test, idx) => (
                                    <div key={idx} className={`test-result ${test.passed ? 'passed' : 'failed'}`}>
                                      <div className="test-status-icon">
                                        {test.passed ? '✓' : '✗'}
                                      </div>
                                      <div className="test-content">
                                        <div className="test-name">{test.test}</div>
                                        <div className="test-message">{test.message}</div>
                                      </div>
                                    </div>
                                  ))}
                                </div>
                              </div>
                            )}

                            {/* Test Details (Collapsible) */}
                            {page.comprehensive_metrics && (
                              <div className="test-details-section">
                                <button 
                                  className="comprehensive-data-toggle"
                                  onClick={() => toggleTests(page.id)}
                                >
                                  <span className="toggle-icon">{expandedTests[page.id] ? '−' : '+'}</span>
                                  <span>Raw Data (JSON)</span>
                                </button>
                                {expandedTests[page.id] && (
                                  <div className="test-results">
                                    <pre>{JSON.stringify(page.comprehensive_metrics, null, 2)}</pre>
                                  </div>
                                )}
                              </div>
                            )}

                            {(!pageInsight?.insights || pageInsight.insights.length === 0) && !page.ai_summary && (
                              <div className="no-issues-found">
                                Page data collected. No insights generated yet.
                              </div>
                            )}
                          </div>
                        </section>
                      )
                  })()}
                </div>
              </div>
            </div>
          )}
        </div>
      </main>
    </div>
  )
}

export default App
