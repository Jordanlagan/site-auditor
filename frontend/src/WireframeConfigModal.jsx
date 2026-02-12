import { useState, useEffect } from 'react'
import './WireframeConfigModal.css'

function WireframeConfigModal({ isOpen, onClose, auditId, pageData, audit, onGenerate }) {
  const [currentStep, setCurrentStep] = useState(1)
  const [config, setConfig] = useState({
    variations_count: 1,
    primary_colors: [], // Array of { color: '#fff', tag: 'Primary Background' }
    inspiration_urls: [''],
    custom_prompt: ''
  })

  const colorTags = [
    'Primary Background',
    'Secondary Background',
    'Accent/CTA',
    'Text Primary',
    'Text Secondary',
    'Heading',
    'Link',
    'Border',
    'Success/Positive',
    'Error/Warning'
  ]
  const [customColor, setCustomColor] = useState('')
  const [generating, setGenerating] = useState(false)
  const [error, setError] = useState(null)

  // Extract available colors from page data
  const availableColors = pageData?.colors?.slice(0, 10) || []

  // Extract recommendations from audit test results
  const extractRecommendations = () => {
    if (!audit?.test_results) return ''
    
    const failedTests = audit.test_results.filter(test => 
      test.status === 'failed' || test.status === 'warning'
    )
    
    if (failedTests.length === 0) return ''
    
    const recommendations = failedTests
      .map(test => `${test.test_name}: ${test.summary}`)
      .join('\n\n')
    
    return `Based on audit findings, please address these issues in the wireframe:\n\n${recommendations}`
  }

  useEffect(() => {
    // Reset state when modal opens
    if (isOpen) {
      setCurrentStep(1)
      setError(null)
      setGenerating(false)
      // Pre-select top 3 colors with default tags
      if (availableColors.length > 0) {
        const defaultTags = ['Primary Background', 'Text Primary', 'Accent/CTA']
        setConfig(prev => ({
          ...prev,
          primary_colors: availableColors.slice(0, 3).map((c, idx) => ({
            color: c.color,
            tag: defaultTags[idx] || 'Primary Background'
          })),
          custom_prompt: extractRecommendations()
        }))
      } else {
        setConfig(prev => ({
          ...prev,
          custom_prompt: extractRecommendations()
        }))
      }
    }
  }, [isOpen])

  if (!isOpen) return null

  const handleColorToggle = (color) => {
    // Always add the color with a default tag (allow duplicates with different tags)
    setConfig(prev => ({
      ...prev,
      primary_colors: [...prev.primary_colors, { color, tag: 'Primary Background' }]
    }))
  }

  const handleColorTagChange = (index, newTag) => {
    setConfig(prev => ({
      ...prev,
      primary_colors: prev.primary_colors.map((c, idx) => 
        idx === index ? { ...c, tag: newTag } : c
      )
    }))
  }

  const handleRemoveColor = (index) => {
    setConfig(prev => ({
      ...prev,
      primary_colors: prev.primary_colors.filter((_, idx) => idx !== index)
    }))
  }

  const handleAddCustomColor = () => {
    const color = customColor.trim()
    if (!color) return
    
    // Validate color format (hex, rgb, or named)
    if (!/^(#[0-9A-Fa-f]{3,6}|rgb\(.+\)|[a-z]+)$/i.test(color)) {
      alert('Please enter a valid color (hex, rgb, or color name)')
      return
    }
    
    // Allow adding the same color multiple times with different tags
    setConfig(prev => ({
      ...prev,
      primary_colors: [...prev.primary_colors, { color, tag: 'Primary Background' }]
    }))
    setCustomColor('')
  }

  const handleInspirationUrlChange = (index, value) => {
    setConfig(prev => {
      const urls = [...prev.inspiration_urls]
      urls[index] = value
      return { ...prev, inspiration_urls: urls }
    })
  }

  const addInspirationUrl = () => {
    if (config.inspiration_urls.length < config.variations_count) {
      setConfig(prev => ({
        ...prev,
        inspiration_urls: [...prev.inspiration_urls, '']
      }))
    }
  }

  const removeInspirationUrl = (index) => {
    if (config.inspiration_urls.length > 1) {
      setConfig(prev => ({
        ...prev,
        inspiration_urls: prev.inspiration_urls.filter((_, i) => i !== index)
      }))
    }
  }

  const handleNext = () => {
    if (currentStep < 4) {
      setCurrentStep(currentStep + 1)
    }
  }

  const handleBack = () => {
    if (currentStep > 1) {
      setCurrentStep(currentStep - 1)
    }
  }

  const handleGenerate = async () => {
    if (config.primary_colors.length === 0) {
      setError('Please select at least one color')
      return
    }
    
    // Filter out empty inspiration URLs
    const validInspirationUrls = config.inspiration_urls.filter(url => url.trim() !== '')
    
    if (validInspirationUrls.length === 0) {
      setError('Please add at least one inspiration website URL')
      return
    }

    setGenerating(true)
    setError(null)

    try {
      const response = await fetch(`http://localhost:3000/audits/${auditId}/wireframes`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(config)
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || 'Failed to generate wireframes')
      }

      const data = await response.json()
      // Show success message - wireframes will generate in background
      alert(`${data.queued} wireframe(s) are being generated. They will appear below when ready.`)
      
      // Only start polling if generation succeeded
      if (data.queued > 0) {
        onGenerate(data.queued)  // Pass actual queued count to parent for placeholders
      }
      
      onClose()
    } catch (err) {
      setError(err.message)
      setGenerating(false)
      // Don't close modal on error so user can see the error
      setGenerating(false)
      // Don't close modal on error so user can see the error
    }
  }

  return (
    <div className="wireframe-modal-overlay" onClick={onClose}>
      <div className="wireframe-modal" onClick={(e) => e.stopPropagation()}>
        <div className="wireframe-modal-header">
          <h2>Generate Wireframe Variations</h2>
          <button className="wireframe-modal-close" onClick={onClose}>×</button>
        </div>

        <div className="wireframe-modal-progress">
          <div className={`progress-step ${currentStep >= 1 ? 'active' : ''}`}>1. Count</div>
          <div className={`progress-step ${currentStep >= 2 ? 'active' : ''}`}>2. Colors</div>
          <div className={`progress-step ${currentStep >= 3 ? 'active' : ''}`}>3. Inspiration</div>
          <div className={`progress-step ${currentStep >= 4 ? 'active' : ''}`}>4. Custom Prompt</div>
        </div>

        <div className="wireframe-modal-body">
          {/* Step 1: Variations Count */}
          {currentStep === 1 && (
            <div className="wireframe-step">
              <h3>How many variations?</h3>
              <p className="step-description">Generate up to 3 wireframe variations at once</p>
              
              <div className="variations-slider">
                <input
                  type="range"
                  min="1"
                  max="3"
                  value={config.variations_count}
                  onChange={(e) => setConfig({ ...config, variations_count: parseInt(e.target.value) })}
                  className="slider"
                />
                <div className="slider-value">{config.variations_count} variation{config.variations_count > 1 ? 's' : ''}</div>
              </div>
            </div>
          )}

          {/* Step 2: Colors */}
          {currentStep === 2 && (
            <div className="wireframe-step">
              <h3>Select Primary Colors</h3>
              <p className="step-description">Choose up to 6 colors from your site (top 10 most used shown)</p>
              
              <div className="color-grid">
                {availableColors.map((colorData, idx) => {
                  const isSelected = config.primary_colors.find(c => c.color === colorData.color)
                  return (
                    <div
                      key={idx}
                      className={`color-option ${isSelected ? 'selected' : ''}`}
                      onClick={() => handleColorToggle(colorData.color)}
                    >
                      <div
                        className="color-swatch"
                        style={{ backgroundColor: colorData.color }}
                        title={colorData.color}
                      />
                      <div className="color-label">{colorData.color}</div>
                      <div className="color-usage">{colorData.usage_count} uses</div>
                    </div>
                  )
                })}
              </div>
              
              {availableColors.length === 0 && (
                <div className="no-colors">No colors available from page data</div>
              )}
              
              <div className="custom-color-input">
                <input
                  type="text"
                  value={customColor}
                  onChange={(e) => setCustomColor(e.target.value)}
                  onKeyPress={(e) => e.key === 'Enter' && handleAddCustomColor()}
                  placeholder="Add custom color (e.g., #3b82f6, rgb(59,130,246))"
                  className="custom-color-field"
                />
                <button
                  type="button"
                  onClick={handleAddCustomColor}
                  className="add-custom-color-btn"
                  disabled={!customColor.trim()}
                >
                  Add
                </button>
              </div>
              
              <div className="selected-count">
                {config.primary_colors.length} color{config.primary_colors.length !== 1 ? 's' : ''} selected (click any color to add it again with a different purpose)
              </div>

              {/* Selected Colors with Tags */}
              {config.primary_colors.length > 0 && (
                <div className="selected-colors-section">
                  <h4>Selected Colors & Their Purpose:</h4>
                  <div className="selected-colors-list">
                    {config.primary_colors.map((colorObj, idx) => (
                      <div key={idx} className="selected-color-row">
                        <div
                          className="selected-color-swatch"
                          style={{ backgroundColor: colorObj.color }}
                        />
                        <span className="selected-color-code">{colorObj.color}</span>
                        <select
                          className="color-tag-select"
                          value={colorObj.tag}
                          onChange={(e) => handleColorTagChange(idx, e.target.value)}
                          onClick={(e) => e.stopPropagation()}
                        >
                          {colorTags.map(tag => (
                            <option key={tag} value={tag}>{tag}</option>
                          ))}
                        </select>
                        <button
                          className="remove-color-btn"
                          onClick={() => handleRemoveColor(idx)}
                          title="Remove"
                        >
                          ×
                        </button>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Step 3: Inspiration URLs */}
          {currentStep === 3 && (
            <div className="wireframe-step">
              <h3>Add Inspiration Websites</h3>
              <p className="step-description">
                Add URLs of websites whose design/layout you want to use as inspiration. 
                We'll analyze their structure and apply it to your content.
              </p>
              
              <div className="inspiration-urls-list">
                {config.inspiration_urls.map((url, index) => (
                  <div key={index} className="inspiration-url-row">
                    <div className="inspiration-url-number">{index + 1}</div>
                    <input
                      type="url"
                      className="inspiration-url-input"
                      placeholder="https://example.com"
                      value={url}
                      onChange={(e) => handleInspirationUrlChange(index, e.target.value)}
                    />
                    {config.inspiration_urls.length > 1 && (
                      <button
                        className="remove-url-btn"
                        onClick={() => removeInspirationUrl(index)}
                        title="Remove"
                      >
                        ×
                      </button>
                    )}
                  </div>
                ))}
              </div>
              
              {config.inspiration_urls.length < config.variations_count && (
                <button className="add-url-btn" onClick={addInspirationUrl}>
                  + Add Another Inspiration URL
                </button>
              )}
              
              <div className="inspiration-note">
                💡 Tip: Add up to {config.variations_count} inspiration {config.variations_count === 1 ? 'URL' : 'URLs'} (one per variation)
              </div>
            </div>
          )}

          {/* Step 4: Custom Prompt */}
          {currentStep === 4 && (
            <div className="wireframe-step">
              <h3>Custom AI Prompt (Optional)</h3>
              <p className="step-description">
                Add custom instructions for the AI. This will override default instructions and have the highest priority.
                Example: "Make the design minimalist with lots of white space" or "Use a bold, magazine-style layout"
              </p>
              
              <textarea
                className="custom-prompt-textarea"
                placeholder="Enter custom instructions for the AI (optional)..."
                value={config.custom_prompt}
                onChange={(e) => setConfig({ ...config, custom_prompt: e.target.value })}
                rows={8}
              />
              
              <div className="prompt-tips">
                <strong>Tips:</strong>
                <ul>
                  <li>Be specific about layout preferences (grid, single column, etc.)</li>
                  <li>Mention desired spacing, typography style, or visual hierarchy</li>
                  <li>Specify what to emphasize (CTA buttons, images, text, etc.)</li>
                </ul>
              </div>
            </div>
          )}

          {error && (
            <div className="wireframe-error">
              {error}
            </div>
          )}
        </div>

        <div className="wireframe-modal-footer">
          <button className="btn-secondary" onClick={onClose} disabled={generating}>
            Cancel
          </button>
          <div className="footer-actions">
            {currentStep > 1 && (
              <button className="btn-secondary" onClick={handleBack} disabled={generating}>
                Back
              </button>
            )}
            {currentStep < 4 ? (
              <button className="btn-primary" onClick={handleNext}>
                Next
              </button>
            ) : (
              <button
                className="btn-primary"
                onClick={handleGenerate}
                disabled={generating || config.primary_colors.length === 0 || config.inspiration_urls.filter(u => u.trim()).length === 0}
              >
                {generating ? 'Generating...' : 'Generate Wireframes'}
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

export default WireframeConfigModal
