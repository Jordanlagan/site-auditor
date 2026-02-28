import { useState } from 'react'

function GoogleSlidesExportModal({ 
  isOpen, 
  onClose, 
  failedTests, 
  auditUrl, 
  onExport 
}) {
  const [generating, setGenerating] = useState(false)
  const [showPrompt, setShowPrompt] = useState(false)
  const [editedPrompt, setEditedPrompt] = useState(null)
  const [generatedContent, setGeneratedContent] = useState(null)
  const [copied, setCopied] = useState(false)

  if (!isOpen) return null

  const buildExportPrompt = () => {
    const failedTestsText = failedTests.map(test => 
      `**${test.test_name}** (${test.status.toUpperCase()})\n` +
      `Summary: ${test.summary}\n` +
      (test.details?.length > 0 ? 
        `Details:\n${test.details.map(d => `- ${typeof d === 'string' ? d : d?.issue || JSON.stringify(d)}`).join('\n')}\n` : 
        '') +
      `Data Sources: ${test.data_sources?.join(', ') || 'None'}\n`
    ).join('\n---\n\n')

    return `You are a Conversion Rate Optimization and UX analysis assistant. Your job is to take audit results from website testing and return a structured, actionable triage document for Google Slides presentation.

**Website:** ${auditUrl}
**Today's Date:** ${new Date().toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })}
**Failed Test Results:**

${failedTestsText}

**Output Structure (follow this order exactly):**

1. Audit Summary (first)
2. Individual slides (after)

---

**Audit Summary (output this FIRST, before any slides):**

**Audit Summary**

**UX / CRO**
[1-2 sentences. Name the most critical conversion or UX issue only. No lists, no elaboration.]

**Responsiveness**
[1-2 sentences. Name the most critical mobile or cross-device issue only. If none found, say so briefly.]

**Page Speed**
[1-2 sentences. Name the most critical performance issue only. No lists, no elaboration.]

---

**Then output the slides:**

Treat each category bucket as a "slide." Each slide contains a title, a grouped list of Issues, and a grouped list of Recommendations. Issues and Recommendations should correspond by position (first issue maps to first recommendation, etc.).

Standard category buckets (add others only if clearly necessary):
- Navigation & Information Architecture
- Page Layout & Visual Hierarchy
- Copy & Messaging Clarity
- Forms & Input Fields
- CTAs & Conversion Points
- Trust & Social Proof
- Page Speed & Technical Performance
- Mobile Usability
- Accessibility

**Slide Format (follow exactly):**

**Slide Title: [Category Bucket Name]**

Issues:
  [Clear, 1-sentence restatement of problem. Be specific about what is wrong and where.]
  [Next issue]

Recommendations:
  [1-sentence actionable fix. State what to do. Be concrete enough that a designer or developer could act on it without follow-up.]
  [Next recommendation, corresponding to the second issue above]

**Writing Rules:**
- Each issue is one sentence. Be specific about what is wrong and where.
- Each recommendation is one sentence. State what to do, not why it matters.
- Be concrete enough that a designer or developer could act on it without follow-up questions.
- Never use em dashes. Use commas or rewrite the sentence instead.
- No filler, no intros, no summaries other than the Audit Summary above.
- Page Speed slides always come last.`
  }

  const getPrompt = () => editedPrompt !== null ? editedPrompt : buildExportPrompt()

  const handleTogglePrompt = () => {
    if (!showPrompt && editedPrompt === null) {
      setEditedPrompt(buildExportPrompt())
    }
    setShowPrompt(!showPrompt)
  }

  const handleGenerate = async () => {
    setGenerating(true)
    try {
      const content = await onExport({ prompt: getPrompt() })
      setGeneratedContent(content)
      setShowPrompt(false)
    } catch (error) {
      alert('Generation failed: ' + (error.message || 'Unknown error'))
    } finally {
      setGenerating(false)
    }
  }

  const handleDownload = () => {
    const hostname = auditUrl ? new URL(auditUrl).hostname.replace('www.', '') : 'audit'
    const filename = `${hostname}-slides-outline.txt`
    const blob = new Blob([generatedContent], { type: 'text/plain' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = filename
    a.click()
    URL.revokeObjectURL(url)
  }

  const handleCopy = async () => {
    await navigator.clipboard.writeText(generatedContent)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  const handleReset = () => {
    setGeneratedContent(null)
    setCopied(false)
  }

  return (
    <div className="modal-overlay">
      <div className="slides-export-modal" onClick={e => e.stopPropagation()}>
        <div className="modal-header">
          <h3>Export to Google Slides</h3>
          <button className="modal-close-btn" onClick={onClose}>&times;</button>
        </div>

        {!generatedContent ? (
          <>
            <div className="modal-body">
              <div className="export-summary">
                <p><strong>{failedTests.length} failed tests</strong> from <strong>{auditUrl}</strong></p>
              </div>

              <div className="form-group">
                <button 
                  className={`toggle-prompt-btn ${showPrompt ? 'active' : ''}`}
                  onClick={handleTogglePrompt}
                  type="button"
                >
                  {showPrompt ? '− Hide' : '+ Edit'} AI Prompt
                </button>
                
                {showPrompt && (
                  <textarea
                    className="prompt-edit-textarea"
                    value={getPrompt()}
                    onChange={e => setEditedPrompt(e.target.value)}
                    rows={20}
                    disabled={generating}
                  />
                )}
              </div>
            </div>

            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={onClose} disabled={generating}>
                Cancel
              </button>
              <button className="btn btn-primary" onClick={handleGenerate} disabled={generating}>
                {generating ? (
                  <>
                    <div className="spinner-small"></div>
                    Generating...
                  </>
                ) : (
                  `Generate Slides Outline`
                )}
              </button>
            </div>
          </>
        ) : (
          <>
            <div className="modal-body">
              <div className="slides-result-actions">
                <button className="btn btn-primary" onClick={handleDownload}>
                  Download .txt
                </button>
                <button className="btn btn-secondary" onClick={handleCopy}>
                  {copied ? 'Copied!' : 'Copy to Clipboard'}
                </button>
                <button className="btn btn-ghost" onClick={handleReset}>
                  Regenerate
                </button>
              </div>
              <textarea
                className="slides-result-textarea"
                value={generatedContent}
                onChange={e => setGeneratedContent(e.target.value)}
                rows={28}
                spellCheck={false}
              />
            </div>

            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={onClose}>
                Close
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}

export default GoogleSlidesExportModal