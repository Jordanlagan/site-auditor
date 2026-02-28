import { useState, useEffect, useRef } from 'react'
import './WireframeStreamingModal.css'
import Icon from './components/Icon'
import HexLoader from './components/HexLoader'

function WireframeStreamingModal({ isOpen, onClose, auditId, config, regenerateWireframeId, sectionSelector }) {
  const [phase, setPhase] = useState('connecting')
  const [message, setMessage] = useState('Connecting...')
  const [htmlContent, setHtmlContent] = useState('')
  const [error, setError] = useState(null)
  const iframeRef = useRef(null)
  const eventSourceRef = useRef(null)
  const lastUpdateRef = useRef(0)
  const pendingUpdateRef = useRef(null)
  const latestHtmlRef = useRef('')
  const abortControllerRef = useRef(null)

  // Keep prop refs up-to-date without adding them to the effect deps
  const configRef = useRef(config)
  const auditIdRef = useRef(auditId)
  const regenerateWireframeIdRef = useRef(regenerateWireframeId)
  const sectionSelectorRef = useRef(sectionSelector)
  const onCloseRef = useRef(onClose)
  useEffect(() => { configRef.current = config }, [config])
  useEffect(() => { auditIdRef.current = auditId }, [auditId])
  useEffect(() => { regenerateWireframeIdRef.current = regenerateWireframeId }, [regenerateWireframeId])
  useEffect(() => { sectionSelectorRef.current = sectionSelector }, [sectionSelector])
  useEffect(() => { onCloseRef.current = onClose }, [onClose])

  useEffect(() => {
    if (!isOpen) return

    // Cancel any previous in-flight request
    if (abortControllerRef.current) {
      abortControllerRef.current.abort()
    }
    const abortController = new AbortController()
    abortControllerRef.current = abortController

    // Reset state
    setPhase('connecting')
    setMessage('Connecting...')
    setHtmlContent('')
    setError(null)
    latestHtmlRef.current = ''
    lastUpdateRef.current = 0

    // Snapshot props at the moment the effect fires
    const _config = configRef.current
    const _auditId = auditIdRef.current
    const _regenerateWireframeId = regenerateWireframeIdRef.current
    const _sectionSelector = sectionSelectorRef.current
    const _onClose = onCloseRef.current

    // Start streaming
    const startStreaming = async () => {
      try {
        // For partial section regen: pre-load existing wireframe HTML into iframe first
        if (_sectionSelector && _regenerateWireframeId) {
          try {
            setMessage('Loading existing wireframe...')
            const wfRes = await fetch(`http://localhost:3000/wireframes/${_regenerateWireframeId}`, { signal: abortController.signal })
            const wfData = await wfRes.json()
            if (wfData.html_content) {
              performIframeUpdate(wfData.html_content)
              latestHtmlRef.current = wfData.html_content
              setHtmlContent(wfData.html_content)
            }
          } catch (e) {
            if (e.name === 'AbortError') return
            // Non-fatal — proceed with streaming
          }
        }

        // Determine URL based on regeneration mode
        const url = _regenerateWireframeId
          ? `http://localhost:3000/wireframes/${_regenerateWireframeId}/regenerate`
          : `http://localhost:3000/audits/${_auditId}/wireframes/stream`

        const body = _regenerateWireframeId
          ? { custom_prompt: _config?.custom_prompt || '', ...(_sectionSelector ? { css_selector: _sectionSelector } : {}) }
          : _config

        const response = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
          signal: abortController.signal
        })

        if (!response.ok) {
          throw new Error('Failed to start streaming')
        }

        const reader = response.body.getReader()
        const decoder = new TextDecoder()
        let buffer = ''

        while (true) {
          const { done, value } = await reader.read()

          if (done) {
            console.log('Stream completed')
            break
          }

          // Append new chunk to buffer
          buffer += decoder.decode(value, { stream: true })

          // Process complete SSE messages (terminated by \n\n)
          const messages = buffer.split('\n\n')

          // Keep the incomplete message in the buffer
          buffer = messages.pop() || ''

          for (const message of messages) {
            if (!message.trim()) continue

            // Extract data from SSE format
            const lines = message.split('\n')
            for (const line of lines) {
              if (line.startsWith('data: ')) {
                try {
                  const data = JSON.parse(line.substring(6))

                  if (data.error) {
                    setError(data.error)
                    setPhase('error')
                    return
                  }

                  if (data.phase) {
                    setPhase(data.phase)
                    setMessage(data.message || '')
                  }

                  if (data.type === 'content') {
                    if (_sectionSelector) {
                      // Show the streaming section fragment inside a minimal page wrapper
                      latestHtmlRef.current = data.accumulated
                      const preview = `<div style="padding:24px;background:#f9f9f9;min-height:100vh"><div style="font:12px/1.4 sans-serif;color:#888;margin-bottom:16px;padding:8px 12px;background:#fff;border:1px solid #e5e7eb;border-radius:6px;display:inline-block">↻ Regenerating: <code style="color:#6366f1">${_sectionSelector}</code></div>${data.accumulated}</div>`
                      updateIframe(preview)
                    } else {
                      latestHtmlRef.current = data.accumulated
                      setHtmlContent(data.accumulated)
                      updateIframe(data.accumulated)
                    }
                  }

                  if (data.done || data.phase === 'complete') {
                    // Force final iframe update with latest content
                    if (pendingUpdateRef.current) {
                      clearTimeout(pendingUpdateRef.current)
                    }
                    if (data.full_html) {
                      // Section patch mode: show the full patched page
                      performIframeUpdate(data.full_html)
                    } else if (latestHtmlRef.current) {
                      performIframeUpdate(latestHtmlRef.current)
                    }

                    setPhase('complete')
                    setMessage(_sectionSelector ? 'Section updated successfully!' : 'Wireframe generated successfully!')
                    setTimeout(() => {
                      _onClose(true) // Pass true to indicate success and refresh list
                    }, 2000)
                    return
                  }
                } catch (parseErr) {
                  console.error('Failed to parse SSE data:', line, parseErr)
                }
              }
            }
          }
        }
      } catch (err) {
        if (err.name === 'AbortError') return // Cancelled — ignore silently
        console.error('Streaming error:', err)
        setError(err.message)
        setPhase('error')
      }
    }

    startStreaming()

    return () => {
      abortController.abort()
      if (pendingUpdateRef.current) {
        clearTimeout(pendingUpdateRef.current)
      }
      if (eventSourceRef.current) {
        eventSourceRef.current.close()
      }
    }
  }, [isOpen])

  const updateIframe = (html) => {
    // Throttle iframe updates to prevent browser hangs
    const now = Date.now()
    const timeSinceLastUpdate = now - lastUpdateRef.current
    
    // Update immediately if it's been more than 500ms
    if (timeSinceLastUpdate >= 500) {
      performIframeUpdate(html)
      lastUpdateRef.current = now
    } else {
      // Schedule an update
      if (pendingUpdateRef.current) {
        clearTimeout(pendingUpdateRef.current)
      }
      pendingUpdateRef.current = setTimeout(() => {
        performIframeUpdate(html)
        lastUpdateRef.current = Date.now()
      }, 500 - timeSinceLastUpdate)
    }
  }

  const performIframeUpdate = (html) => {
    if (iframeRef.current && iframeRef.current.contentWindow) {
      const doc = iframeRef.current.contentWindow.document
      doc.open()
      doc.write(`
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Preview</title>
        </head>
        <body>
        ${html}
        </body>
        </html>
      `)
      doc.close()
      
      // Auto-scroll to bottom to show new content
      try {
        const iframeWindow = iframeRef.current.contentWindow
        if (iframeWindow) {
          iframeWindow.scrollTo({
            top: iframeWindow.document.documentElement.scrollHeight,
            behavior: 'smooth'
          })
        }
      } catch (e) {
        // Ignore scroll errors
      }
    }
  }

  if (!isOpen) return null

  return (
    <div className="streaming-modal-overlay" onClick={(e) => {
      if (e.target === e.currentTarget && phase !== 'generating') {
        onClose(false)
      }
    }}>
      <div className="streaming-modal">
        <div className="streaming-modal-header">
          <h2>{sectionSelector ? 'Regenerating Section' : 'Generating Wireframe'}</h2>
          {phase !== 'generating' && (
            <button className="streaming-modal-close" onClick={() => onClose(false)}>×</button>
          )}
        </div>

        <div className="streaming-modal-status">
          <div className={`status-indicator status-${phase}`}>
            {(phase === 'extracting' || phase === 'generating' || phase === 'connecting') && <HexLoader size={48} />}
            {phase === 'saving' && <Icon name="save" size={32} />}
            {phase === 'complete' && <Icon name="checkCircle" size={32} />}
            {phase === 'error' && <Icon name="alertCircle" size={32} />}
          </div>
          <div className="status-message">{message}</div>
          {error && <div className="status-error">{error}</div>}
        </div>

        <div className="streaming-modal-preview">
          <div className="preview-label">Live Preview:</div>
          <div className="preview-container">
            <iframe
              ref={iframeRef}
              className="preview-iframe"
              title="Wireframe Preview"
              sandbox="allow-same-origin"
            />
            {!htmlContent && (
              <div className="preview-placeholder">
                <div className="preview-placeholder-icon">
                  <HexLoader size={160} />
                </div>
                <div className="preview-placeholder-text">
                  Wireframe will appear here as it generates...
                </div>
              </div>
            )}
          </div>
        </div>

        {phase === 'complete' && (
          <div className="streaming-modal-footer">
            <button className="btn-primary" onClick={() => onClose(true)}>
              Done
            </button>
          </div>
        )}
      </div>
    </div>
  )
}

export default WireframeStreamingModal
