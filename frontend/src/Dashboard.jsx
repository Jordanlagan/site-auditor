import { useState, useEffect } from 'react'
import './Dashboard.css'
import Icon from './components/Icon'

function Dashboard({ auditId, onClose }) {
  const [status, setStatus] = useState(null)
  const [logs, setLogs] = useState([])
  const API_BASE = 'http://localhost:3000'

  useEffect(() => {
    const poll = async () => {
      try {
        const response = await fetch(`${API_BASE}/audits/${auditId}/status`)
        const data = await response.json()
        setStatus(data)

        // Add log entry for phase changes
        if (data.current_phase) {
          setLogs(prev => {
            const lastLog = prev[prev.length - 1]
            if (!lastLog || lastLog.phase !== data.current_phase) {
              return [...prev, { 
                phase: data.current_phase, 
                status: data.status,
                time: new Date().toLocaleTimeString() 
              }]
            }
            return prev
          })
        }

        // Stop polling if complete or failed
        if (data.status === 'complete' || data.status === 'failed') {
          return
        }

        setTimeout(poll, 2000)
      } catch (err) {
        console.error('Failed to fetch status', err)
        setTimeout(poll, 2000)
      }
    }

    poll()
  }, [auditId])

  if (!status) return <div className="dashboard-loading">Loading...</div>

  const getPhaseIcon = (phase) => {
    const icons = {
      crawling: '🕷️',
      prioritizing: '🎯',
      collecting: '📊',
      testing: '🧪',
      synthesizing: '🔬'
    }
    return icons[phase] || '⚙️'
  }

  const getStatusColor = (status) => {
    const colors = {
      pending: '#9ca3af',
      crawling: '#3b82f6',
      collecting: '#8b5cf6',
      testing: '#f59e0b',
      complete: '#10b981',
      failed: '#ef4444'
    }
    return colors[status] || '#9ca3af'
  }

  return (
    <div className="dashboard-overlay" onClick={onClose}>
      <div className="dashboard-panel" onClick={(e) => e.stopPropagation()}>
        <div className="dashboard-header">
          <h2>🔴 Live Audit Progress</h2>
          <button onClick={onClose} className="dashboard-close">×</button>
        </div>

        <div className="dashboard-content">
          {/* Current Status */}
          <div className="status-card" style={{ borderColor: getStatusColor(status.status) }}>
            <div className="status-main">
              <span className="status-icon" style={{ color: getStatusColor(status.status) }}>
                {getPhaseIcon(status.current_phase)}
              </span>
              <div className="status-info">
                <div className="status-label">Status</div>
                <div className="status-value" style={{ color: getStatusColor(status.status) }}>
                  {status.status.toUpperCase()}
                </div>
                {status.current_phase && (
                  <div className="status-phase">Phase: {status.current_phase}</div>
                )}
              </div>
            </div>
          </div>

          {/* Progress Metrics */}
          <div className="metrics-grid">
            {status.discovered_pages_count > 0 && (
              <div className="metric-card">
                <div className="metric-label">Pages Found</div>
                <div className="metric-value">{status.discovered_pages_count}</div>
              </div>
            )}
            
            {status.priority_pages_count > 0 && (
              <div className="metric-card">
                <div className="metric-label">Priority Pages</div>
                <div className="metric-value">{status.priority_pages_count}</div>
              </div>
            )}

            {status.tests_passed > 0 && (
              <div className="metric-card metric-success">
                <div className="metric-label">Tests Passed</div>
                <div className="metric-value">{status.tests_passed}</div>
              </div>
            )}

            {status.tests_failed > 0 && (
              <div className="metric-card metric-failed">
                <div className="metric-label">Tests Failed</div>
                <div className="metric-value">{status.tests_failed}</div>
              </div>
            )}

            {status.tests_warning > 0 && (
              <div className="metric-card metric-warning">
                <div className="metric-label">Warnings</div>
                <div className="metric-value">{status.tests_warning}</div>
              </div>
            )}

            {status.overall_score && (
              <div className="metric-card metric-highlight">
                <div className="metric-label">Overall Score</div>
                <div className="metric-value">{status.overall_score}</div>
              </div>
            )}
          </div>

          {/* Activity Log */}
          <div className="activity-log">
            <h3>Activity Log</h3>
            <div className="log-entries">
              {logs.map((log, idx) => (
                <div key={idx} className="log-entry">
                  <span className="log-time">{log.time}</span>
                  <span className="log-phase">{getPhaseIcon(log.phase)} {log.phase}</span>
                  <span className="log-status" style={{ color: getStatusColor(log.status) }}>
                    {log.status}
                  </span>
                </div>
              ))}
              {logs.length === 0 && (
                <div className="log-empty">Waiting for activity...</div>
              )}
            </div>
          </div>

          {/* Status Messages */}
          {status.status === 'complete' && (
            <div className="status-message status-success">
              <Icon name="checkCircle" size={20} />
              <span>Audit completed successfully!</span>
            </div>
          )}
          
          {status.status === 'failed' && (
            <div className="status-message status-error">
              <Icon name="alertCircle" size={20} />
              <span>Audit failed. Check logs for details.</span>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

export default Dashboard
