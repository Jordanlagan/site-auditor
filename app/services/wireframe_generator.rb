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

  def generate_with_streaming!(&block)
    page_data = extract_page_data
    raise "No page data available" unless page_data

    inspiration_urls = config[:inspiration_urls] || []
    raise "No inspiration URLs provided" unless inspiration_urls.any?

    inspiration_url = inspiration_urls.first
    
    # Extract design patterns first (not streamed, this is quick)
    block.call({ phase: "extracting", message: "Analyzing inspiration site..." })
    
    inspiration_crawler = InspirationCrawler.new(inspiration_url)
    inspiration_data = inspiration_crawler.crawl!
    
    design_patterns = extract_design_patterns(inspiration_data, use_sonnet: true)
    raise "Failed to extract design patterns" unless design_patterns
    
    block.call({ phase: "generating", message: "Generating wireframe..." })
    
    # Generate wireframe with streaming
    design_system = extract_design_system(page_data)
    html_content = generate_wireframe_from_patterns_streaming(design_system, design_patterns, inspiration_url, &block)
    
    raise "Failed to generate wireframe" unless html_content.present?
    
    # Save the wireframe
    block.call({ phase: "saving", message: "Saving wireframe..." })
    wireframe = save_single_wireframe(html_content, 0, inspiration_url, design_patterns)
    
    block.call({ phase: "complete", wireframe_id: wireframe.id, url: wireframe.url })
    
    wireframe
  rescue => e
    Rails.logger.error "Streaming wireframe generation failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    block.call({ phase: "error", error: e.message })
    nil
  end

  def regenerate_with_streaming!(source_wireframe, &block)
    page_data = extract_page_data
    raise "No page data available" unless page_data

    existing_html = source_wireframe.html_content
    raise "Source wireframe has no HTML content" unless existing_html.present?

    design_system = extract_design_system(page_data)
    custom_prompt = config[:custom_prompt] || ""
    css_selector = config[:css_selector].presence

    source_design_patterns = source_wireframe.config_used&.dig("design_patterns")
    inspiration_url = source_wireframe.config_used&.dig("inspiration_urls")&.first || "unknown"

    if css_selector
      # ── Partial section regeneration ────────────────────────────────────────
      block.call({ phase: "generating", message: "Regenerating section '#{css_selector}'..." })

      section_html = regenerate_section_streaming(design_system, existing_html, custom_prompt, css_selector, source_wireframe, &block)
      raise "Failed to regenerate section" unless section_html.present?

      # Splice the new section back into the full document
      doc = Nokogiri::HTML::DocumentFragment.parse(existing_html)
      element = doc.at_css(css_selector)
      if element
        element.replace(Nokogiri::HTML::DocumentFragment.parse(section_html))
      else
        Rails.logger.warn "css_selector '#{css_selector}' not found when splicing — saving section as full content"
      end
      patched_html = doc.to_html

      regen_count = audit.wireframes.where("title LIKE 'Regeneration %'").count + 1
      regen_title = "Regeneration #{regen_count}#{css_selector ? " (#{css_selector})" : ''}"

      block.call({ phase: "saving", message: "Saving wireframe..." })
      wireframe = save_single_wireframe(patched_html, audit.wireframes.count, inspiration_url, source_design_patterns, title: regen_title)

      block.call({ phase: "complete", wireframe_id: wireframe.id, url: wireframe.url,
                   patch_selector: css_selector, full_html: patched_html })
      wireframe
    else
      # ── Full page regeneration ───────────────────────────────────────────────
      block.call({ phase: "generating", message: "Regenerating wireframe..." })

      html_content = regenerate_wireframe_streaming(design_system, existing_html, custom_prompt, source_wireframe, &block)
      raise "Failed to regenerate wireframe" unless html_content.present?

      regen_count = audit.wireframes.where("title LIKE 'Regeneration %'").count + 1
      block.call({ phase: "saving", message: "Saving wireframe..." })
      wireframe = save_single_wireframe(html_content, audit.wireframes.count, inspiration_url, source_design_patterns, title: "Regeneration #{regen_count}")

      block.call({ phase: "complete", wireframe_id: wireframe.id, url: wireframe.url })
      wireframe
    end
  rescue => e
    Rails.logger.error "Streaming wireframe regeneration failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    block.call({ phase: "error", error: e.message })
    nil
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

    save_single_wireframe(html_content, config[:variation_index], inspiration_url, design_patterns)
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

    all_images = page_data.images
      .select { |img| img["src"].present? && !img["src"].include?("data:image") }

    # Filter by selected images if provided, otherwise use all (default)
    selected_images_data = config[:selected_images] || []
    
    result = if selected_images_data.empty?
      # No selection made - use all images (default behavior)
      all_images.map { |img| img["src"] }
    else
      # Filter to only selected images and apply their labels
      # selected_images_data format: [{ src: 'url', label: 'Hero Image' }, ...]
      selected_srcs = selected_images_data.map { |img| img[:src] || img["src"] }
      all_images
        .select { |img| selected_srcs.include?(img["src"]) }
        .map do |img|
          # Find label if provided
          selected = selected_images_data.find { |s| (s[:src] || s["src"]) == img["src"] }
          label = selected&.dig(:label) || selected&.dig("label")
          label.present? ? "#{img['src']} (#{label})" : img["src"]
        end
    end
    
    result
  end

  def build_design_transfer_prompt(design_system, inspiration_data)
    # DEPRECATED - Replaced with two-phase generation
    # Keeping for reference
  end

  def extract_text_from_html(html)
    # Extract clean text content from HTML for prompt efficiency
    text = html.to_s
              .gsub(/<script[^>]*>.*?<\/script>/im, "")  # Remove scripts
              .gsub(/<style[^>]*>.*?<\/style>/im, "")    # Remove styles
              .gsub(/<[^>]+>/, " ")                       # Remove all tags
              .gsub(/\s+/, " ")                           # Collapse whitespace
              .strip
    text[0..15000]  # Limit to 15K chars - captures more product details, features, CTAs
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
        "design_philosophy": "A 2-3 sentence plain-English description of the overall aesthetic intent. Describe the why behind the design choices, not raw CSS values. Example: Uses generous negative space and restrained typography to communicate premium durability. Warm neutral palette creates approachability. Layout favors large imagery with minimal text overlay.",
        "font_pairing_strategy": "Describe how fonts are paired. Example: Serif display headings at heavy weight paired with light sans-serif body text for editorial contrast.",
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
    # Use legacy single-pass generation by default (modular split loses context cohesion)
    use_modular = config.fetch(:use_modular_generation, false)
    
    if use_modular
      Rails.logger.info "Using modular section-by-section generation"
      generate_wireframe_modular(design_system, design_patterns, inspiration_url)
    else
      Rails.logger.info "Using legacy single-pass generation"
      generate_wireframe_legacy(design_system, design_patterns, inspiration_url)
    end
  end

  def generate_wireframe_modular(design_system, design_patterns, inspiration_url)
    # Phase 2A: Generate CSS only
    Rails.logger.info "Phase 2A: Generating CSS styles"
    css_content = generate_css(design_system, design_patterns, inspiration_url)
    
    return nil unless css_content.present?

    # Phase 2B: Generate sections separately
    Rails.logger.info "Phase 2B: Generating HTML sections"
    sections = generate_sections(design_system, design_patterns, inspiration_url)
    
    return nil unless sections.present?

    # Combine CSS and HTML
    html_body = sections.join("\n\n")
    
    "<style>\n#{css_content}\n</style>\n\n#{html_body}"
  end

  def generate_css(design_system, design_patterns, inspiration_url)
    design_philosophy = design_patterns['design_philosophy'] || design_patterns[:design_philosophy] ||
      "Modern, professional design with clear hierarchy and purposeful use of space."
    
    font_pairing_strategy = design_patterns['font_pairing_strategy'] || design_patterns[:font_pairing_strategy] ||
      "Create clear hierarchy using font weight and size variations."

    prompt = <<~PROMPT
      You are generating CSS styles for a wireframe based on design patterns.

      DESIGN PHILOSOPHY: #{design_philosophy}

      COLORS (use these):
      #{design_system[:colors].join("\n")}

      FONTS (use these):
      #{format_fonts(design_system[:fonts])}

      DESIGN PATTERNS:
      #{JSON.generate(design_patterns)}

      FONT PAIRING STRATEGY: #{font_pairing_strategy}

      YOUR TASK:
      Generate ONLY the CSS styles (<style> tag content) that implements:

      1. CSS Custom Properties (at :root):
         - Build semantic color variables from the client's tagged colors
         - Define: --bg-primary, --bg-secondary, --text-primary, --text-secondary, --text-muted, --accent, --accent-light, --border-color, --shadow-color
         - Ensure WCAG AA contrast ratios
         
      2. Typography System:
         - Apply font_pairing_strategy: #{font_pairing_strategy}
         - Use client's fonts: #{format_fonts(design_system[:fonts])}
         - Define complete type scale: display (hero), h1, h2, h3, body, small/caption, label/eyebrow
         - Eyebrow text: 10-11px, font-weight 600, uppercase, letter-spacing 1-1.5px
         - Never use generic fonts (Arial, Helvetica, system-ui as primary)

      3. Layout System:
         - System: #{design_patterns['layout']['system']}
         - Container max-width: #{design_patterns['layout']['container_max_width']}
         - Spacing from patterns: #{JSON.generate(design_patterns['spacing'])}

      4. Components:
         - Base styles for: navigation, hero, features, content sections, footer
         - Button styles with hover states
         - Card/section styles

      5. Transitions:
         - Define: --transition: .25s cubic-bezier(.4, 0, .2, 1)
         - Subtle hovers only: opacity, translateY(-1px to -3px), border-color, box-shadow
         - No global page animations

      6. Responsive:
         - Breakpoints: #{design_patterns['responsive']['breakpoints'].join(', ')}
         - Mobile-first approach

      OUTPUT FORMAT:
      - Return ONLY the CSS code (no <style> tags, no markdown)
      - MINIFY output (remove unnecessary whitespace)
      - Use compact selectors

      Return ONLY minified CSS code, no explanation.
    PROMPT

    Rails.logger.info "Generating CSS (prompt: #{prompt.length} chars)"
    
    result = call_ai(prompt, json_mode: false, max_tokens: 8000)
    return nil unless result

    # Clean up any markdown or HTML tags
    result.gsub(/<\/?style[^>]*>/, '').strip
  end

  def generate_sections(design_system, design_patterns, inspiration_url)
    original_html = design_system[:html_content] || ""
    text_content = extract_text_from_html(original_html)
    
    # Define sections to generate based on design patterns
    section_types = design_patterns['layout']['sections'].map { |s| s['type'] }.uniq
    
    # Ensure we have at least the basic sections
    section_types = ['navigation', 'hero', 'content', 'footer'] if section_types.empty?
    
    sections_html = []
    
    section_types.each do |section_type|
      Rails.logger.info "Generating #{section_type} section"
      section_html = generate_section(section_type, design_system, design_patterns, text_content, inspiration_url)
      sections_html << section_html if section_html.present?
    end
    
    sections_html
  end

  def generate_section(section_type, design_system, design_patterns, text_content, inspiration_url)
    # Get section-specific pattern if available
    section_pattern = design_patterns['layout']['sections'].find { |s| s['type'] == section_type }
    component_pattern = design_patterns['components'].find { |c| c['name'] == section_type }

    prompt = <<~PROMPT
      Generate the #{section_type.upcase} section HTML for a wireframe.

      #{config[:custom_prompt].present? ? "CUSTOM INSTRUCTIONS: #{config[:custom_prompt]}\n\n" : ""}
      DESIGN PHILOSOPHY: #{design_patterns['design_philosophy'] || design_patterns[:design_philosophy]}

      TEXT CONTENT TO USE:
      #{text_content[0..5000]}

      IMAGES AVAILABLE:
      #{design_system[:images].first(10).join("\n")}

      SECTION PATTERN:
      #{section_pattern ? JSON.generate(section_pattern) : "Create appropriate #{section_type} layout"}

      COMPONENT PATTERN:
      #{component_pattern ? JSON.generate(component_pattern) : "Standard #{section_type} structure"}

      YOUR TASK:
      Generate ONLY the HTML for the #{section_type} section that:

      1. Uses the provided text content from the original site
      2. Follows the pattern structure: #{section_pattern&.dig('layout') || 'standard layout'}
      3. Uses CSS classes that match the generated styles
      4. #{section_type == 'navigation' ? 'Includes logo/brand, main navigation links' : ''}
      5. #{section_type == 'hero' ? 'Includes main headline, subheadline, CTA button, hero image' : ''}
      6. #{section_type == 'content' || section_type == 'features' ? 'Includes multiple content cards/sections with images, headings, descriptions' : ''}
      7. #{section_type == 'footer' ? 'Includes footer links, copyright, social links, contact info' : ''}
      8. Uses inline SVG icons (stroke-only, viewBox="0 0 24 24", no emoji)
      9. Uses provided images from the original site
      10. Uses semantic HTML5 tags

      OUTPUT FORMAT:
      - Return ONLY HTML code (no markdown, no style tags, no explanations)
      - MINIFY output (remove unnecessary whitespace)
      - Start with a semantic tag like <nav>, <header>, <main>, <section>, or <footer>

      Return ONLY minified HTML, no explanation.
    PROMPT

    Rails.logger.info "Generating #{section_type} section (prompt: #{prompt.length} chars)"
    
    result = call_ai(prompt, json_mode: false, max_tokens: 4000)
    return nil unless result

    # Clean up any markdown
    result.gsub(/^```html\s*/, "").gsub(/^```\s*/, "").gsub(/```$/, "").strip
  end

  def generate_wireframe_legacy(design_system, design_patterns, inspiration_url)
    # Phase 2: Generate wireframe using extracted patterns + original content
    original_html = design_system[:html_content] || ""

    # Provide fallbacks for new Phase 1 fields if missing (backward compatibility)
    design_philosophy = design_patterns['design_philosophy'] || design_patterns[:design_philosophy] ||
      "Modern, professional design with clear hierarchy and purposeful use of space."
    
    font_pairing_strategy = design_patterns['font_pairing_strategy'] || design_patterns[:font_pairing_strategy] ||
      "Create clear hierarchy using font weight and size variations."
    
    # Log if fallbacks were used (helps identify if Phase 1 needs updating)
    if design_patterns['design_philosophy'].nil? && design_patterns[:design_philosophy].nil?
      Rails.logger.warn "⚠️ design_philosophy missing from patterns, using fallback"
    end
    if design_patterns['font_pairing_strategy'].nil? && design_patterns[:font_pairing_strategy].nil?
      Rails.logger.warn "⚠️ font_pairing_strategy missing from patterns, using fallback"
    end

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
      CREATIVE DIRECTION:
      ========================================
      #{design_philosophy}

      Use this as the guiding aesthetic intent for all design decisions below. Every choice — layout density, spacing generosity, color warmth, typographic weight — should reinforce this philosophy. Do not just copy the inspiration site's CSS values; embody its design intent using the client's brand assets.

      ========================================
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

      TEXT CONTENT (use this text in your wireframe):
      #{extract_text_from_html(original_html)}

      ========================================
      DESIGN PATTERNS (from #{inspiration_url}):
      ========================================
      #{JSON.generate(design_patterns)}

      ========================================
      YOUR TASK:
      ========================================

      Create a COMPLETE, FULL-PAGE wireframe that includes ALL sections from top to bottom:

      1. LAYOUT & STRUCTURE:
         - Use the layout system from design patterns (#{design_patterns['layout']['system']})
         - Mirror ALL section types in order: #{design_patterns['layout']['sections'].map { |s| s['type'] }.join(', ')}
         - Apply container max-width: #{design_patterns['layout']['container_max_width']}
         - CRITICAL: Generate EVERY section including the footer. Do not stop until all sections are complete.

      2. TYPOGRAPHY:
         - Use the font_pairing_strategy from the design patterns: #{font_pairing_strategy}
         - Assign the client's fonts to clear roles: one for display/headings, one for body text.
         - Client's fonts: #{format_fonts(design_system[:fonts])}
         - If the client only has one font or their fonts lack weight range for hierarchy, suggest and import a complementary Google Font.
         - Establish a clear type scale with these levels: display (hero text), h1, h2, h3, body, small/caption, label/eyebrow (uppercase, tracked).
         - Eyebrow/label text should be: 10-11px, font-weight 600, uppercase, letter-spacing 1-1.5px.
         - Never use fonts that look generic or default (Arial, Helvetica, system-ui as primary choices).

      3. SPACING:
         - Use spacing system from patterns: #{JSON.generate(design_patterns['spacing'])}

      4. COLORS:
         - Use EXACTLY the client's tagged colors provided above. These are carefully selected brand colors.
         - Build CSS custom properties at :root: --bg-primary, --bg-secondary, --text-primary, --text-secondary, --text-muted, --accent, --accent-light, --border-color, --shadow-color
         - Map the client's tagged colors (Secondary Background → --bg-secondary, Text Primary → --text-primary, Accent/CTA → --accent, etc.)
         - IMPORTANT: Use these exact colors. Don't generate new colors from the inspiration site patterns.
         - Ensure WCAG AA contrast ratios between text and background colors.
         - Use the CSS variables throughout all styles. Never use raw hex codes in component styles.

      5. CONTENT:
         - Extract ALL text content from the original HTML (headings, paragraphs, links)
         - Use the original site's title and description
         - Use the original site's images with their labels when provided

      6. COMPONENTS:
         - Build components following the patterns' structure descriptions
         - Component patterns: #{design_patterns['components'].map { |c| c['name'] }.join(', ')}

      7. ICONS & GRAPHICS:
         - Use inline SVG icons exclusively. Never use emoji characters under any circumstances.
         - SVGs should be simple line-art style: stroke-only, no fill, stroke-width between 1.5 and 2.
         - Icons should feel intentionally curated, not decorative filler.
         - For common UI icons (search, cart, user, chevron, checkmark, truck, shield), write clean <svg> elements with viewBox="0 0 24 24".
         - Match icon stroke color to the semantic text color variables.

      8. NAVIGATION:
         - If ANY image in the IMAGES list has a label or filename containing "logo", embed it as an <img> tag inside the <nav> element. Do NOT use text or an SVG placeholder as the logo when a logo image was provided.
         - NEVER render a hamburger/toggle menu on desktop (viewport ≥ 768px)

      CRITICAL OUTPUT FORMAT:
      - Start with: <style>...all CSS here...</style>
      - Then ALL HTML sections from navigation through footer
      - Do NOT include <html>, <head>, or <body> tags
      - Do NOT use markdown or code blocks
      - Include ALL CSS inline in the <style> tag
      - Ensure proper UTF-8 encoding for all special characters
      - COMPLETE THE FULL PAGE - do not stop mid-page or before the footer

      OPTIMIZATION:
      - Prioritize completeness over brevity
      - Use compact CSS selectors where possible
      - Keep SVG icons simple and compact
      - If approaching token limits, prioritize including all sections over verbose CSS comments

      ANIMATION & TRANSITIONS:
      - Do not add any global page entrance animations.
      - Define a shared transition timing: --transition: .25s cubic-bezier(.4, 0, .2, 1)
      - Apply subtle hover transitions to interactive elements only: opacity, transform (translateY -1px to -3px), border-color, box-shadow.
      - Cards on hover: translateY(-3px) with a soft box-shadow.
      - Links/buttons on hover: opacity or underline reveal.
      - No animations on static content. No fade-ins on load.

      MANDATORY: Return the COMPLETE page with ALL sections including footer. Return ONLY the raw HTML starting with <style>.
    PROMPT

    Rails.logger.info "="*80
    custom_prompt_info = config[:custom_prompt].present? ? " + CUSTOM PROMPT (#{config[:custom_prompt].length} chars)" : ""
    Rails.logger.info "PHASE 2: WIREFRAME GENERATION PROMPT (#{prompt.length} chars)#{custom_prompt_info}"
    Rails.logger.info "="*80

    # Use higher token limit for complete page generation
    call_ai(prompt, json_mode: false, max_tokens: 20000)
  end

  def generate_wireframe_from_patterns_streaming(design_system, design_patterns, inspiration_url, &block)
    # Use the same prompt as legacy but stream the response
    original_html = design_system[:html_content] || ""

    design_philosophy = design_patterns['design_philosophy'] || design_patterns[:design_philosophy] ||
      "Modern, professional design with clear hierarchy and purposeful use of space."
    
    font_pairing_strategy = design_patterns['font_pairing_strategy'] || design_patterns[:font_pairing_strategy] ||
      "Create clear hierarchy using font weight and size variations."

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
      CREATIVE DIRECTION:
      ========================================
      #{design_philosophy}

      Use this as the guiding aesthetic intent for all design decisions below. Every choice — layout density, spacing generosity, color warmth, typographic weight — should reinforce this philosophy. Do not just copy the inspiration site's CSS values; embody its design intent using the client's brand assets.

      ========================================
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

      TEXT CONTENT (use this text in your wireframe):
      #{extract_text_from_html(original_html)}

      ========================================
      DESIGN PATTERNS (from #{inspiration_url}):
      ========================================
      #{JSON.generate(design_patterns)}

      ========================================
      YOUR TASK:
      ========================================

      Create a COMPLETE, FULL-PAGE wireframe that includes ALL sections from top to bottom:

      1. LAYOUT & STRUCTURE:
         - Use the layout system from design patterns (#{design_patterns['layout']['system']})
         - Mirror ALL section types in order: #{design_patterns['layout']['sections'].map { |s| s['type'] }.join(', ')}
         - Apply container max-width: #{design_patterns['layout']['container_max_width']}
         - CRITICAL: Generate EVERY section including the footer. Do not stop until all sections are complete.

      2. TYPOGRAPHY:
         - Use the font_pairing_strategy from the design patterns: #{font_pairing_strategy}
         - Assign the client's fonts to clear roles: one for display/headings, one for body text.
         - Client's fonts: #{format_fonts(design_system[:fonts])}
         - If the client only has one font or their fonts lack weight range for hierarchy, suggest and import a complementary Google Font.
         - Establish a clear type scale with these levels: display (hero text), h1, h2, h3, body, small/caption, label/eyebrow (uppercase, tracked).
         - Eyebrow/label text should be: 10-11px, font-weight 600, uppercase, letter-spacing 1-1.5px.
         - Never use fonts that look generic or default (Arial, Helvetica, system-ui as primary choices).

      3. SPACING:
         - Use spacing system from patterns: #{JSON.generate(design_patterns['spacing'])}

      4. COLORS:
         - Use EXACTLY the client's tagged colors provided above. These are carefully selected brand colors.
         - Build CSS custom properties at :root: --bg-primary, --bg-secondary, --text-primary, --text-secondary, --text-muted, --accent, --accent-light, --border-color, --shadow-color
         - Map the client's tagged colors (Secondary Background → --bg-secondary, Text Primary → --text-primary, Accent/CTA → --accent, etc.)
         - IMPORTANT: Use these exact colors. Don't generate new colors from the inspiration site patterns.
         - Ensure WCAG AA contrast ratios between text and background colors.
         - Use the CSS variables throughout all styles. Never use raw hex codes in component styles.

      5. CONTENT:
         - Extract ALL text content from the original HTML (headings, paragraphs, links)
         - Use the original site's title and description
         - Use the original site's images with their labels when provided

      6. COMPONENTS:
         - Build components following the patterns' structure descriptions
         - Component patterns: #{design_patterns['components'].map { |c| c['name'] }.join(', ')}

      7. ICONS & GRAPHICS:
         - Use inline SVG icons exclusively. Never use emoji characters under any circumstances.
         - SVGs should be simple line-art style: stroke-only, no fill, stroke-width between 1.5 and 2.
         - Icons should feel intentionally curated, not decorative filler.
         - For common UI icons (search, cart, user, chevron, checkmark, truck, shield), write clean <svg> elements with viewBox="0 0 24 24".
         - Match icon stroke color to the semantic text color variables.

      8. NAVIGATION:
         - If ANY image in the IMAGES list has a label or filename containing "logo", embed it as an <img> tag inside the <nav> element. Do NOT use text or an SVG placeholder as the logo when a logo image was provided.
         - NEVER render a hamburger/toggle menu on desktop (viewport ≥ 768px). All navigation links must be fully visible on desktop at all times.
         - A hamburger icon and its associated mobile menu toggle are ONLY permitted inside a CSS @media query scoped to mobile breakpoints (max-width: 767px or similar). At desktop widths the hamburger element must be hidden (display: none) and the full nav links must be visible.

      CRITICAL OUTPUT FORMAT:
      - Start with: <style>...all CSS here...</style>
      - Then ALL HTML sections from navigation through footer
      - Do NOT include <html>, <head>, or <body> tags
      - Do NOT use markdown or code blocks
      - Include ALL CSS inline in the <style> tag
      - Ensure proper UTF-8 encoding for all special characters
      - COMPLETE THE FULL PAGE - do not stop mid-page or before the footer

      OPTIMIZATION:
      - Prioritize completeness over brevity
      - Use compact CSS selectors where possible
      - Keep SVG icons simple and compact
      - If approaching token limits, prioritize including all sections over verbose CSS comments

      ANIMATION & TRANSITIONS:
        - Do not add any global page entrance animations.
        - Define a shared transition timing: --transition: .25s cubic-bezier(.4, 0, .2, 1)
        - Apply subtle hover transitions to interactive elements only: opacity, transform (translateY -1px to -3px), border-color, box-shadow.
        - Cards on hover: translateY(-3px) with a soft box-shadow.
        - Links/buttons on hover: opacity or underline reveal.
        - No animations on static content. No fade-ins on load.

      MANDATORY: Return the COMPLETE page with ALL sections including footer. Return ONLY the raw HTML starting with <style>.
    PROMPT

    Rails.logger.info "Streaming wireframe generation with prompt: #{prompt.length} chars"
    
    result = call_ai_streaming(prompt, &block)
    
    Rails.logger.info "Streaming result length: #{result&.length || 0} chars"
    
    result
  end

  def regenerate_section_streaming(design_system, existing_html, custom_prompt, css_selector, source_wireframe, &block)
    doc = Nokogiri::HTML::DocumentFragment.parse(existing_html)
    element = doc.at_css(css_selector)
    raise "No element found matching CSS selector: '#{css_selector}'" unless element

    fragment_html = element.to_html
    element_tag = element.name

    # Extract the <style> block from the existing wireframe so the AI knows
    # exactly which CSS variables and classes are defined on the page
    style_match = existing_html.match(/<style[^>]*>(.*?)<\/style>/im)
    existing_style = style_match ? style_match[1].strip : ""

    # Pull rich context from the original wireframe's saved config
    saved_config     = source_wireframe.config_used || {}
    design_patterns  = saved_config["design_patterns"] || saved_config[:design_patterns] || {}
    design_philosophy = saved_config["design_philosophy"] || design_patterns["design_philosophy"] || ""
    font_pairing     = design_patterns["font_pairing_strategy"] || ""

    prompt = <<~PROMPT
      You are an expert web designer. Revise the following HTML section from an existing wireframe.
      The rest of the page is unchanged — your output will be spliced back in, so it MUST visually
      match the existing page's design system exactly.

      ========================================
      REVISION INSTRUCTIONS:
      ========================================
      #{custom_prompt.presence || "Improve the design quality and visual appeal of this section."}

      ========================================
      EXISTING SECTION HTML (CSS selector: #{css_selector}):
      ========================================
      #{fragment_html}

      ========================================
      EXISTING PAGE STYLESHEET (already on the page — do NOT redefine these):
      ========================================
      #{existing_style.first(8000)}

      ========================================
      ORIGINAL SITE CONTENT:
      ========================================
      URL: #{design_system[:page_url]}
      Title: #{design_system[:meta_title]}

      COLORS (tagged brand colors — match the existing page exactly):
      #{design_system[:colors].join("\n")}

      FONTS (use only these — must match what's imported in the stylesheet):
      #{format_fonts(design_system[:fonts])}

      IMAGES (use these with their labels):
      #{design_system[:images].join("\n")}

      ========================================
      DESIGN SYSTEM CONTEXT:
      ========================================
      #{design_philosophy.present? ? "Design philosophy: #{design_philosophy}" : ""}
      #{font_pairing.present? ? "Font pairing strategy: #{font_pairing}" : ""}
      #{design_patterns["typography"] ? "Typography scale: #{JSON.generate(design_patterns['typography'])}" : ""}
      #{design_patterns["spacing"] ? "Spacing system: #{JSON.generate(design_patterns['spacing'])}" : ""}
      #{design_patterns["components"].present? ? "Component patterns: #{design_patterns['components'].map { |c| c['name'] }.join(', ')}" : ""}

      ========================================
      CRITICAL RULES:
      ========================================
      - Return ONLY the revised HTML for this specific element
      - The outermost element MUST be <#{element_tag}> (same tag as original)
      - Use ONLY CSS custom properties and class names already defined in the stylesheet above (var(--...))
      - Do NOT add a <style> block — the stylesheet is already on the page
      - Do NOT include <html>, <head>, <body>, or wrapping <style> tags
      - Do NOT use markdown, code fences, or backticks
      - Colors, fonts, and spacing MUST be consistent with the rest of the page
      - Return ONLY raw HTML starting with <#{element_tag}>
      - If a logo image was present in the original, keep it
      - Never show a hamburger menu at desktop widths (≥ 768px)
    PROMPT

    Rails.logger.info "Streaming section regeneration for selector '#{css_selector}', prompt #{prompt.length} chars"
    result = call_ai_streaming(prompt, &block)
    Rails.logger.info "Section regen result length: #{result&.length || 0} chars"
    result
  end

  def regenerate_wireframe_streaming(design_system, existing_html, custom_prompt, source_wireframe, &block)
    prompt = <<~PROMPT
      You are an expert web designer. You are given an existing wireframe that was previously generated.
      Your task is to create an IMPROVED version of this wireframe based on the feedback below.

      ========================================
      🎯 REVISION INSTRUCTIONS:
      ========================================
      #{custom_prompt}

      ========================================
      EXISTING WIREFRAME HTML:
      ========================================
      #{existing_html}

      ========================================
      ORIGINAL SITE DATA (for reference):
      ========================================
      URL: #{design_system[:page_url]}
      Title: #{design_system[:meta_title]}

      COLORS (use these):
      #{design_system[:colors].join("\n")}

      FONTS (use these):
      #{format_fonts(design_system[:fonts])}

      IMAGES (use these):
      #{design_system[:images].join("\n")}

      ========================================
      YOUR TASK:
      ========================================
      Regenerate the wireframe incorporating the revision instructions above.
      Keep the overall structure and design patterns from the existing wireframe,
      but apply the requested changes. If no specific changes are requested,
      create a fresh variation with improved design quality.

      NAVIGATION RULES:
      - If ANY image in the IMAGES list has a label or filename containing "logo", embed it as an <img> tag inside the <nav> element. Do NOT use text or an SVG placeholder as the logo when a logo image was provided.
      - NEVER render a hamburger/toggle menu on desktop (viewport ≥ 768px). All navigation links must be fully visible on desktop at all times.
      - A hamburger icon and its associated mobile menu toggle are ONLY permitted inside a CSS @media query scoped to mobile breakpoints (max-width: 767px or similar). At desktop widths the hamburger element must be hidden (display: none) and the full nav links must be visible.

      CRITICAL OUTPUT FORMAT:
      - Start with: <style>...all CSS here...</style>
      - Then ALL HTML sections from navigation through footer
      - Do NOT include <html>, <head>, or <body> tags
      - Do NOT use markdown or code blocks
      - Include ALL CSS inline in the <style> tag
      - COMPLETE THE FULL PAGE - do not stop mid-page or before the footer

      MANDATORY: Return the COMPLETE page with ALL sections including footer. Return ONLY the raw HTML starting with <style>.
    PROMPT

    Rails.logger.info "Streaming wireframe regeneration with prompt: #{prompt.length} chars"

    result = call_ai_streaming(prompt, &block)

    Rails.logger.info "Streaming regeneration result length: #{result&.length || 0} chars"

    result
  end

  def call_ai(prompt, json_mode: false, override_model: nil, max_tokens: 16384)
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

    Rails.logger.info "Calling AI with model=#{api_model}, temp=#{temperature}, max_tokens=#{max_tokens}"

    response = OpenaiService.chat(
      messages: [
        { role: "system", content: system_message },
        { role: "user", content: prompt }
      ],
      model: api_model,
      temperature: temperature,
      max_tokens: max_tokens
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

  def call_ai_streaming(prompt, &block)
    model = audit.ai_config&.dig("model") || "claude-opus-4-6"
    temperature = audit.ai_config&.dig("temperature") || 0.7

    model_mapping = {
      "claude-opus-4-6" => "claude-opus-4-6",
      "claude-sonnet-4-5" => "claude-sonnet-4-5",
      "claude-sonnet-3-5" => "claude-3-5-sonnet-20241022",
      "gpt-4o" => "gpt-4o"
    }

    api_model = model_mapping[model] || "claude-opus-4-6"

    Rails.logger.info "Streaming AI with model=#{api_model}, temp=#{temperature}, max_tokens=32000"

    system_message = "You are an expert web designer. Return only raw HTML code, no markdown, no JSON."
    
    accumulated_html = ""
    event_count = 0
    
    # Use Anthropic's streaming API
    anthropic_client = Anthropic::Client.new(
      api_key: ENV.fetch("ANTHROPIC_API_KEY", Rails.application.credentials.dig(:anthropic, :api_key))
    )
    
    Rails.logger.info "🔄 Starting Anthropic stream..."
    
    # Create the stream object (not passing a block here)
    stream = anthropic_client.messages.stream(
      model: api_model,
      messages: [
        { role: "user", content: prompt }
      ],
      system: system_message,
      temperature: temperature,
      max_tokens: 32000
    )
    
    # Use the text stream helper which automatically handles all event types
    stream.text.each do |text_chunk|
      event_count += 1
      
      if event_count <= 5
        Rails.logger.info "Text chunk #{event_count}: #{text_chunk.length} chars"
      end
      
      if text_chunk && !text_chunk.empty?
        accumulated_html += text_chunk
        block.call({ type: "content", chunk: text_chunk, accumulated: accumulated_html })
      end
    end
    
    Rails.logger.info "✅ Streaming complete: #{accumulated_html.length} characters (#{event_count} chunks)"

    Rails.logger.info "Stream loop finished. Accumulated: #{accumulated_html.length} chars"
    
    # Clean up response
    accumulated_html = accumulated_html.strip
    accumulated_html = accumulated_html.gsub(/^```html\s*/, "").gsub(/^```\s*/, "").gsub(/```$/, "").strip
    
    Rails.logger.info "After cleanup: #{accumulated_html.length} chars"
    
    if accumulated_html.empty?
      Rails.logger.error "⚠️  Stream completed but accumulated HTML is empty!"
      Rails.logger.error "Total events received: #{event_count}"
      raise "Streaming completed with no content"
    end
    
    accumulated_html
  rescue IOError, Errno::EPIPE => e
    # Client disconnected - log but don't treat as error
    Rails.logger.warn "Client disconnected during streaming: #{e.message}"
    accumulated_html.presence || generate_fallback_html
  rescue => e
    Rails.logger.error "AI streaming failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    block.call({ type: "error", error: e.message }) rescue nil
    generate_fallback_html
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

  def save_single_wireframe(html_content, index, inspiration_url_param = nil, design_patterns = nil, title: nil)
    return nil unless html_content.present?

    # Ensure wireframes directory exists
    wireframes_dir = Rails.root.join("public", "wireframes")
    FileUtils.mkdir_p(wireframes_dir)

    # Use passed inspiration URL or fall back to config
    inspiration_url = inspiration_url_param || config[:inspiration_url] || config[:inspiration_data]&.dig(:url) || "unknown"
    inspiration_host = URI.parse(inspiration_url).host rescue 'inspiration'
    title ||= "Variation #{index + 1} (#{inspiration_host})"

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

    # Create wireframe record, saving full design_patterns for the design brief
    config_with_patterns = config.to_h
    if design_patterns.present?
      config_with_patterns[:design_patterns] = design_patterns
      config_with_patterns[:design_philosophy] = design_patterns['design_philosophy'] || design_patterns[:design_philosophy]
    end

    wireframe = audit.wireframes.create!(
      title: title,
      file_path: "/wireframes/#{filename}",
      config_used: config_with_patterns
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
