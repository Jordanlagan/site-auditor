class WireframeGenerator
  attr_reader :audit, :config

  def initialize(audit, config = {})
    @audit = audit
    @config = config.with_indifferent_access
  end

  def generate!
    page_data = extract_page_data
    return { error: "No page data available" } unless page_data

    inspiration_urls = config[:inspiration_urls] || []
    return { error: "No inspiration URLs provided" } unless inspiration_urls.any?

    # Track generation status in audit's ai_config
    variations_count = config[:variations_count] || inspiration_urls.length
    audit.ai_config ||= {}
    audit.ai_config["wireframes_generating"] = true
    audit.ai_config["wireframes_expected"] = variations_count
    audit.ai_config["wireframes_generated_at"] = Time.current.iso8601
    audit.save!

    # Queue async job to pre-extract patterns and then generate wireframes
    # This keeps the HTTP request non-blocking
    PreExtractPatternsJob.perform_later(audit.id, inspiration_urls, config.to_h)

    { message: "Wireframe generation started", queued: inspiration_urls.length }
  rescue => e
    Rails.logger.error "Wireframe generation failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { error: e.message }
  end

  def generate_single!
    page_data = extract_page_data
    return nil unless page_data

    design_system = extract_design_system(page_data)

    # Use pre-extracted patterns if available, otherwise extract them
    design_patterns = if config[:design_patterns]
      Rails.logger.info "Using pre-extracted design patterns"
      config[:design_patterns]
    else
      inspiration_data = config[:inspiration_data]
      Rails.logger.info "Phase 1: Extracting design patterns from #{inspiration_data[:url]}"
      extract_design_patterns(inspiration_data, use_sonnet: true)
    end

    if design_patterns.nil?
      Rails.logger.error "Failed to extract design patterns, aborting wireframe generation"
      return nil
    end

    # Phase 2: Generate wireframe using patterns + original content (use Opus for quality)
    Rails.logger.info "Phase 2: Generating wireframe with extracted patterns"

    # Get inspiration URL from either the pre-extracted config or the inspiration_data
    inspiration_url = config[:inspiration_url] || config[:inspiration_data]&.dig(:url)

    html_content = generate_wireframe_from_patterns(design_system, design_patterns, inspiration_url)

    save_single_wireframe(html_content, config[:variation_index])
  rescue => e
    Rails.logger.error "Single wireframe generation failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    nil
  end

  private

  def extract_page_data
    # Get first page with complete data collection
    page = audit.discovered_pages
                 .where(data_collection_status: "complete")
                 .joins(:page_data)
                 .first

    page&.page_data
  end

  def extract_design_system(page_data)
    {
      colors: extract_colors(page_data),
      fonts: extract_fonts(page_data),
      images: extract_images(page_data),
      page_url: audit.url,
      meta_title: page_data.meta_title,
      meta_description: page_data.meta_description,
      html_content: page_data.html_content
    }
  end

  def extract_colors(page_data)
    # Get selected colors from config, or top 6 from page data
    selected_colors = config[:primary_colors] || []

    if selected_colors.empty? && page_data.colors.present?
      selected_colors = page_data.colors.first(6).map { |c| c["color"] }
    end

    # Format colors with tags if they're objects, otherwise just return the color strings
    if selected_colors.is_a?(Array) && selected_colors.first.is_a?(Hash)
      selected_colors.map { |c| "#{c[:color] || c['color']} (#{c[:tag] || c['tag']})" }
    else
      selected_colors
    end
  end

  def extract_fonts(page_data)
    return [] unless page_data.fonts.present?

    fonts = []
    page_data.fonts.each do |font|
      if font["source"] == "google_fonts" && font["href"]
        fonts << { type: "google_fonts", href: font["href"] }
      elsif font["family"]
        fonts << { type: "custom", family: font["family"] }
      end
    end

    fonts.uniq
  end

  def extract_images(page_data)
    return [] unless page_data.images.present?

    page_data.images
      .select { |img| img["src"].present? && !img["src"].include?("data:image") }
      .map { |img| img["src"] }
  end

  def build_design_transfer_prompt(design_system, inspiration_data)
    # DEPRECATED - Replaced with two-phase generation
    # Keeping for reference
  end

  def extract_design_patterns(inspiration_data, use_sonnet: false)
    # Phase 1: Analyze inspiration site and extract structured design patterns
    # Use Sonnet for this phase to save costs (pattern extraction is simpler than generation)
    css_content = inspiration_data[:css][0..50000]
    html_content = inspiration_data[:html][0..100000]

    prompt = <<~PROMPT
      You are an expert web designer analyzing a website to extract its design system and layout patterns.

      INSPIRATION SITE TO ANALYZE:
      URL: #{inspiration_data[:url]}

      HTML STRUCTURE:
      #{html_content}

      CSS STYLES:
      #{css_content}

      TASK:
      Analyze this website and extract the following design patterns as a structured JSON object:

      {
        "layout": {
          "system": "grid" or "flex" or "hybrid",
          "container_max_width": "1200px",
          "columns": 12,
          "sections": [
            {
              "type": "navigation" | "hero" | "features" | "content" | "footer",
              "layout": "describe layout pattern",
              "key_classes": ["class1", "class2"]
            }
          ]
        },
        "typography": {
          "h1": { "size": "48px", "weight": "700", "line_height": "1.2" },
          "h2": { "size": "36px", "weight": "600", "line_height": "1.3" },
          "h3": { "size": "24px", "weight": "600", "line_height": "1.4" },
          "body": { "size": "16px", "weight": "400", "line_height": "1.6" },
          "font_family": "primary font stack"
        },
        "spacing": {
          "section_padding": "80px 0",
          "element_margin": "24px",
          "container_padding": "0 20px"
        },
        "colors": {
          "primary": "#hex",
          "secondary": "#hex",
          "background": "#hex",
          "text": "#hex"
        },
        "components": [
          {
            "name": "navigation",
            "structure": "describe HTML structure",
            "styling": "describe key CSS properties"
          },
          {
            "name": "hero",
            "structure": "describe HTML structure",
            "styling": "describe key CSS properties"
          }
        ],
        "responsive": {
          "breakpoints": ["768px", "1024px"],
          "mobile_patterns": "describe mobile layout changes"
        }
      }

      Return ONLY valid JSON. No markdown, no explanation, just the JSON object.
    PROMPT

    Rails.logger.info "="*80
    Rails.logger.info "PHASE 1: DESIGN PATTERN EXTRACTION PROMPT (#{prompt.length} chars)"
    Rails.logger.info "="*80

    # Use Sonnet for pattern extraction to save costs (75% cheaper than Opus)
    model = use_sonnet ? "claude-sonnet-4-5" : (audit.ai_config&.dig("model") || "claude-opus-4-6")
    result = call_ai(prompt, json_mode: true, override_model: model)

    # Check if result is nil before parsing
    if result.nil?
      Rails.logger.error "Design pattern extraction returned nil"
      return nil
    end

    # Strip markdown code blocks if present (```json ... ```)
    result = result.strip
    result = result.gsub(/^```json\s*/, "").gsub(/^```\s*/, "").gsub(/```$/, "").strip

    # Parse JSON response
    JSON.parse(result)
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse design patterns JSON: #{e.message}"
    Rails.logger.error "Response was: #{result}"
    nil
  rescue => e
    Rails.logger.error "Failed to extract design patterns: #{e.message}"
    nil
  end

  def generate_wireframe_from_patterns(design_system, design_patterns, inspiration_url)
    # Phase 2: Generate wireframe using extracted patterns + original content
    original_html = design_system[:html_content] || ""

    # Build custom instruction override if provided
    custom_instruction = if config[:custom_prompt].present?
      <<~CUSTOM
        ========================================
        🎯 PRIORITY CUSTOM INSTRUCTIONS:
        ========================================
        #{config[:custom_prompt]}

        (IMPORTANT: The above custom instructions have the highest priority and should override any conflicting instructions below)

      CUSTOM
    else
      ""
    end

    prompt = <<~PROMPT
      You are an expert web designer creating a wireframe by applying design patterns to original content.

      #{custom_instruction}========================================
      ORIGINAL SITE CONTENT:
      ========================================
      URL: #{design_system[:page_url]}
      Title: #{design_system[:meta_title]}
      Description: #{design_system[:meta_description]}

      COLORS (use these):
      #{design_system[:colors].join("\n")}

      FONTS (use these):
      #{format_fonts(design_system[:fonts])}

      IMAGES (use these):
      #{design_system[:images].join("\n")}

      HTML (extract text content from here):
      #{original_html[0..30000]}

      ========================================
      DESIGN PATTERNS (from #{inspiration_url}):
      ========================================
      #{JSON.pretty_generate(design_patterns)}

      ========================================
      YOUR TASK:
      ========================================

      Create a complete wireframe that:

      1. LAYOUT & STRUCTURE:
         - Use the layout system from design patterns (#{design_patterns['layout']['system']})
         - Mirror the section types and arrangements: #{design_patterns['layout']['sections'].map { |s| s['type'] }.join(', ')}
         - Apply container max-width: #{design_patterns['layout']['container_max_width']}

      2. TYPOGRAPHY:
         - Apply typography scale from patterns (h1: #{design_patterns['typography']['h1']['size']}, etc.)
         - Use original site's fonts: #{format_fonts(design_system[:fonts])}

      3. SPACING:
         - Use spacing system from patterns

      4. COLORS:
         - Use the colors from the original site according to their tagged purposes
         - Apply each color for its intended use (e.g., Primary Background, Text Primary, Accent/CTA, etc.)
         - Replace ALL inspiration colors with the appropriate original site colors based on their semantic tags

      5. CONTENT:
         - Extract ALL text content from the original HTML (headings, paragraphs, links)
         - Use the original site's title and description
         - Use the original site's images

      6. COMPONENTS:
         - Build components following the patterns' structure descriptions
         - Example: #{design_patterns['components'].first(2).map { |c| "#{c['name']}: #{c['structure']}" }.join('; ')}

      7. ICONS & GRAPHICS:
         - Use simple inline SVG icons instead of emoji characters for better display consistency
         - SVGs provide better cross-platform consistency and professional appearance

      CRITICAL OUTPUT FORMAT:
      - Start with: <style>...all CSS here...</style>
      - Then your HTML content
      - Do NOT include <html>, <head>, or <body> tags
      - Do NOT use markdown or code blocks
      - Include ALL CSS inline in the <style> tag
      - Ensure proper UTF-8 encoding for all special characters

      SIGNATURE ANIMATION (ALWAYS ADD):
      At the END of your <style> tag, add:

      @keyframes unveilFromBlack {
        0% { opacity: 0; filter: brightness(0); }
        50% { opacity: 1; filter: brightness(0.5); }
        100% { opacity: 1; filter: brightness(1); }
      }
      * { animation: unveilFromBlack 1.5s ease-out; }

      Return ONLY the raw HTML starting with <style>.
    PROMPT

    Rails.logger.info "="*80
    custom_prompt_info = config[:custom_prompt].present? ? " + CUSTOM PROMPT (#{config[:custom_prompt].length} chars)" : ""
    Rails.logger.info "PHASE 2: WIREFRAME GENERATION PROMPT (#{prompt.length} chars)#{custom_prompt_info}"
    Rails.logger.info "="*80

    call_ai(prompt, json_mode: false)
  end

  def call_ai(prompt, json_mode: false, override_model: nil)
    # Use audit's AI config for model and temperature
    model = override_model || audit.ai_config&.dig("model") || "claude-opus-4-6"
    temperature = audit.ai_config&.dig("temperature") || 0.7

    # Use the model alias directly - these are the correct API names
    # claude-opus-4-6 and claude-sonnet-4-5 are the official aliases
    model_mapping = {
      "claude-opus-4-6" => "claude-opus-4-6",
      "claude-sonnet-4-5" => "claude-sonnet-4-5",
      "claude-sonnet-3-5" => "claude-3-5-sonnet-20241022",
      "gpt-4o" => "gpt-4o"
    }

    api_model = model_mapping[model] || "claude-opus-4-6"

    Rails.logger.info "Using AI model: #{api_model} (temp: #{temperature})"

    system_message = if json_mode
      "You are an expert web designer. Return ONLY valid JSON. No markdown, no explanation."
    else
      "You are an expert web designer. Return only raw HTML code, no markdown, no JSON."
    end

    Rails.logger.info "Calling AI with model=#{api_model}, temp=#{temperature}, max_tokens=16384"

    response = OpenaiService.chat(
      messages: [
        { role: "system", content: system_message },
        { role: "user", content: prompt }
      ],
      model: api_model,
      temperature: temperature,
      max_tokens: 16384
    )

    Rails.logger.info "AI response received: #{response&.length || 0} characters"

    # Check if response is nil
    if response.nil?
      Rails.logger.error "AI returned nil response"
      return json_mode ? nil : generate_fallback_html
    end

    # Clean up response (remove markdown code blocks if present)
    response = response.strip
    if json_mode
      # Strip ```json markers
      response = response.gsub(/^```json\s*/, "").gsub(/^```\s*/, "").gsub(/```$/, "").strip
    else
      # Strip ```html markers
      response = response.gsub(/^```html\s*/, "").gsub(/^```\s*/, "").gsub(/```$/, "").strip
    end

    response
  rescue => e
    Rails.logger.error "AI call failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    json_mode ? nil : generate_fallback_html
  end

  def format_fonts(fonts)
    return "Default system fonts" if fonts.empty?

    fonts.map do |font|
      if font[:type] == "google_fonts"
        "Google Fonts: #{font[:href]}"
      elsif font[:family]
        font[:family]
      end
    end.compact.join(", ")
  end

  def save_single_wireframe(html_content, index)
    return nil unless html_content.present?

    # Ensure wireframes directory exists
    wireframes_dir = Rails.root.join("public", "wireframes")
    FileUtils.mkdir_p(wireframes_dir)

    # Try new format (pre-extracted patterns) first, then fall back to old format
    inspiration_url = config[:inspiration_url] || config[:inspiration_data]&.dig(:url) || "unknown"
    title = "Variation #{index + 1} (#{URI.parse(inspiration_url).host rescue 'inspiration'})"

    # Generate filename
    timestamp = Time.current.to_i
    filename = "#{audit.id}_#{timestamp}_#{index}.html"
    filepath = wireframes_dir.join(filename)

    # Wrap content with proper HTML structure and UTF-8 meta tag
    full_html = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{title}</title>
      </head>
      <body>
      #{html_content}
      </body>
      </html>
    HTML

    # Write HTML file with explicit UTF-8 encoding
    File.write(filepath, full_html, encoding: "UTF-8")

    # Create wireframe record
    wireframe = audit.wireframes.create!(
      title: title,
      file_path: "/wireframes/#{filename}",
      config_used: config.to_h
    )

    Rails.logger.info "✓ Saved wireframe: #{title} (#{filename})"
    wireframe
  rescue => e
    Rails.logger.error "Failed to save wireframe: #{e.message}"
    nil
  end

  def generate_fallback_html
    <<~HTML
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
        .hero { padding: 100px 20px; text-align: center; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }
        .hero h1 { font-size: 3rem; margin-bottom: 1rem; }
        .hero p { font-size: 1.2rem; margin-bottom: 2rem; }
        .cta { padding: 15px 40px; background: white; color: #667eea; border: none; border-radius: 5px; font-size: 1.1rem; cursor: pointer; }
      </style>
      <div class="hero">
        <h1>Welcome to Your Site</h1>
        <p>This is a fallback wireframe. Something went wrong with AI generation.</p>
        <button class="cta">Get Started</button>
      </div>
    HTML
  end
end
