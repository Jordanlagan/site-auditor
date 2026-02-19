import { useState, useEffect } from 'react'
import './WireframeConfigModal.css'
import WireframeStreamingModal from './WireframeStreamingModal'
import Icon from './components/Icon'

function WireframeConfigModal({ isOpen, onClose, auditId, pageData, audit, onGenerate }) {
  const [currentStep, setCurrentStep] = useState(1)
  const [showStreamingModal, setShowStreamingModal] = useState(false)
  const [config, setConfig] = useState({
    variations_count: 1,
    primary_colors: [], // Array of { color: '#fff', tag: 'Primary Background' }
    selected_images: [], // Array of { src: 'url', label: 'optional' } (empty = all included by default)
    inspiration_urls: [''],
    custom_prompt: '',
    save_as_default_colors: false,
    save_as_default_images: false
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

  // Extract available colors and images from page data
  const availableColors = pageData?.colors?.slice(0, 10) || []
  
  // Deduplicate images by src URL
  const availableImages = (() => {
    const imageMap = new Map()
    const allImages = pageData?.images || []
    
    allImages.forEach(img => {
      if (img.src && !imageMap.has(img.src)) {
        imageMap.set(img.src, img)
      }
    })
    
    return Array.from(imageMap.values())
  })()

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
      
      // Check if there's a saved default color profile
      const defaultColorProfile = audit?.ai_config?.default_color_profile
      const defaultImageProfile = audit?.ai_config?.default_image_profile
      
      if (defaultColorProfile && defaultColorProfile.length > 0) {
        // Use saved default color profile
        setConfig(prev => ({
          ...prev,
          primary_colors: defaultColorProfile,
          selected_images: defaultImageProfile || [],
          custom_prompt: extractRecommendations()
        }))
      } else if (availableColors.length > 0) {
        // Pre-select top 3 colors with default tags if no saved profile
        const defaultTags = ['Primary Background', 'Text Primary', 'Accent/CTA']
        setConfig(prev => ({
          ...prev,
          primary_colors: availableColors.slice(0, 3).map((c, idx) => ({
            color: c.color,
            tag: defaultTags[idx] || 'Primary Background'
          })),
          selected_images: defaultImageProfile || [],
          custom_prompt: extractRecommendations()
        }))
      } else {
        setConfig(prev => ({
          ...prev,
          selected_images: defaultImageProfile || [],
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

  const handleImageToggle = (imageSrc) => {
    setConfig(prev => {
      const isSelected = prev.selected_images.find(img => img.src === imageSrc)
      if (isSelected) {
        // Remove from selection
        return {
          ...prev,
          selected_images: prev.selected_images.filter(img => img.src !== imageSrc)
        }
      } else {
        // Add to selection with empty label
        return {
          ...prev,
          selected_images: [...prev.selected_images, { src: imageSrc, label: '' }]
        }
      }
    })
  }

  const handleImageLabelChange = (imageSrc, label) => {
    setConfig(prev => ({
      ...prev,
      selected_images: prev.selected_images.map(img => 
        img.src === imageSrc ? { ...img, label } : img
      )
    }))
  }

  const toggleAllImages = () => {
    setConfig(prev => {
      const allExplicitlySelected = prev.selected_images.length === availableImages.length
      const defaultAllSelected = prev.selected_images.length === 0
      
      if (allExplicitlySelected || defaultAllSelected) {
        // Deselect all - select just first image to break "default all" behavior
        // User can then deselect this one manually if they want zero images
        if (availableImages.length > 0) {
          return { ...prev, selected_images: [{ src: availableImages[0].src, label: '' }] }
        }
        return prev
      } else {
        // Select all explicitly
        return { ...prev, selected_images: availableImages.map(img => ({ src: img.src, label: '' })) }
      }
    })
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
    if (currentStep < 5) {
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
          <div className={`progress-step ${currentStep >= 3 ? 'active' : ''}`}>3. Images</div>
          <div className={`progress-step ${currentStep >= 4 ? 'active' : ''}`}>4. Inspiration</div>
          <div className={`progress-step ${currentStep >= 5 ? 'active' : ''}`}>5. Custom</div>
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
                  
                  <div className="save-default-checkbox">
                    <label>
                      <input
                        type="checkbox"
                        checked={config.save_as_default_colors}
                        onChange={(e) => setConfig(prev => ({ 
                          ...prev, 
                          save_as_default_colors: e.target.checked 
                        }))}
                      />
                      <span>Save as default color profile</span>
                    </label>
                    <p className="checkbox-description">
                      Save this color selection for future wireframe generations
                    </p>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Step 3: Images */}
          {currentStep === 3 && (
            <div className="wireframe-step">
              <h3>Select Images (Optional)</h3>
              <p className="step-description">
                Choose which images to include in the wireframe. All images are included by default.
              </p>
              
              {availableImages.length > 0 ? (
                <>
                  <div className="image-selection-controls">
                    <button
                      type="button"
                      onClick={toggleAllImages}
                      className="toggle-all-btn"
                    >
                      {config.selected_images.length === availableImages.length || config.selected_images.length === 0
                        ? '☑ Deselect All' 
                        : '☐ Select All'}
                    </button>
                    <span className="image-count">
                      {config.selected_images.length === 0 
                        ? `All ${availableImages.length} images included` 
                        : `${config.selected_images.length} of ${availableImages.length} images selected`}
                    </span>
                  </div>
                  
                  <div className="image-grid">
                    {availableImages.map((imageData, idx) => {
                      // When selected_images is empty, all are considered selected (default)
                      const selectedImage = config.selected_images.find(img => img.src === imageData.src)
                      const isIncluded = config.selected_images.length === 0 || selectedImage
                      const imageSrc = imageData.src
                      
                      // Skip images without valid src
                      if (!imageSrc || imageSrc === '' || imageSrc === 'null') {
                        return null
                      }
                      
                      return (
                        <div
                          key={idx}
                          className={`image-option ${isIncluded ? 'selected' : ''}`}
                          onClick={() => handleImageToggle(imageSrc)}
                        >
                          <img
                            src={imageSrc}
                            alt={imageData.alt || `Image ${idx + 1}`}
                            className="image-thumbnail"
                            onError={(e) => {
                              e.target.style.display = 'none'
                              e.target.nextSibling.style.display = 'flex'
                            }}
                          />
                          <div className="image-placeholder" style={{ display: 'none' }}>
                            <Icon name="image" size={32} color="#6b7280" />
                          </div>
                          <div className="image-checkbox">
                            {isIncluded ? <Icon name="check" size={16} /> : <div className="checkbox-empty" />}
                          </div>
                          {imageData.alt && (
                            <div className="image-alt" title={imageData.alt}>
                              {imageData.alt.substring(0, 30)}{imageData.alt.length > 30 ? '...' : ''}
                            </div>
                          )}
                        </div>
                      )
                    })}
                  </div>
                  
                  {/* Image Labels Section */}
                  {config.selected_images.length > 0 && (
                    <div className="selected-images-section">
                      <h4>Image Labels (Optional):</h4>
                      <p className="section-note">Add descriptive labels to help the AI use images appropriately (e.g., "Hero Image", "Product Photo", "Team Photo")</p>
                      <div className="selected-images-list">
                        {config.selected_images.map((imageObj, idx) => (
                          <div key={idx} className="selected-image-row">
                            <img
                              src={imageObj.src}
                              alt={`Selected ${idx + 1}`}
                              className="selected-image-thumb"
                              onError={(e) => {
                                e.target.style.display = 'none'
                              }}
                            />
                            <input
                              type="text"
                              className="image-label-input"
                              placeholder="Optional label (e.g., Hero Image)"
                              value={imageObj.label || ''}
                              onChange={(e) => handleImageLabelChange(imageObj.src, e.target.value)}
                              onClick={(e) => e.stopPropagation()}
                            />
                            <button
                              className="remove-image-btn"
                              onClick={(e) => {
                                e.stopPropagation()
                                handleImageToggle(imageObj.src)
                              }}
                              title="Remove"
                            >
                              ×
                            </button>
                          </div>
                        ))}
                      </div>
                      
                      <div className="save-default-checkbox">
                        <label>
                          <input
                            type="checkbox"
                            checked={config.save_as_default_images}
                            onChange={(e) => setConfig(prev => ({ 
                              ...prev, 
                              save_as_default_images: e.target.checked 
                            }))}
                          />
                          <span>Save as default image selection</span>
                        </label>
                        <p className="checkbox-description">
                          Save this image selection for future wireframe generations
                        </p>
                      </div>
                    </div>
                  )}
                  
                  <div className="image-note">
                    💡 Tip: By default, all images are included. Deselect images you don't want in the wireframe.
                  </div>
                </>
              ) : (
                <div className="no-images">No images available from page data</div>
              )}
            </div>
          )}

          {/* Step 4: Inspiration URLs */}
          {currentStep === 4 && (
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

          {/* Step 5: Custom Prompt */}
          {currentStep === 5 && (
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
          <div className="footer-actions">
            {currentStep > 1 && (
              <button className="btn-secondary" onClick={handleBack} disabled={generating}>
                Back
              </button>
            )}
            {currentStep < 5 ? (
              <div style={{ marginLeft: 'auto' }}>
                <button className="btn-primary" onClick={handleNext}>
                  Next
                </button>
              </div>
            ) : (
              <div className="footer-generate-section">
                <div className="generate-buttons-grid">
                  <button
                    className="btn-secondary btn-background"
                    onClick={handleGenerate}
                    disabled={generating || config.primary_colors.length === 0 || config.inspiration_urls.filter(u => u.trim()).length === 0}
                  >
                    {generating ? 'Generating...' : 'Generate (Background)'}
                  </button>
                  <button
                    className="btn-primary btn-live-preview"
                    onClick={() => {
                      if (config.primary_colors.length === 0) {
                        setError('Please select at least one color')
                        return
                      }
                      const validUrls = config.inspiration_urls.filter(url => url.trim() !== '')
                      if (validUrls.length === 0) {
                        setError('Please add at least one inspiration website URL')
                        return
                      }
                      setShowStreamingModal(true)
                    }}
                    disabled={generating || config.primary_colors.length === 0 || config.inspiration_urls.filter(u => u.trim()).length === 0}
                  >
                    Generate with Live Preview
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
      
      {/* Streaming Modal */}
      <WireframeStreamingModal
        isOpen={showStreamingModal}
        onClose={(success) => {
          setShowStreamingModal(false)
          if (success) {
            onGenerate(1) // Refresh the wireframe list
            onClose()
          }
        }}
        auditId={auditId}
        config={config}
      />
    </div>
  )
}

export default WireframeConfigModal
