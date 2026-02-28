module Tests
  class DynamicTestExecutor
    attr_reader :discovered_page, :page_data, :audit, :test

    def initialize(discovered_page, test)
      @discovered_page = discovered_page
      @page_data = discovered_page.page_data
      @audit = discovered_page.audit
      @test = test
    end

    def execute!
      Rails.logger.info "  Executing dynamic test: #{test.test_key}"

      unless test.active
        return create_result(
          status: :not_applicable,
          summary: "Test is not currently active"
        )
      end

      data_context = build_data_context

      if data_context.values.compact.empty?
        return create_result(
          status: :not_applicable,
          summary: "Required data sources not available for this page"
        )
      end

      analyze_with_ai(test.test_details, data_context)
    rescue => e
      Rails.logger.error "Dynamic test #{test.test_key} failed: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      create_result(
        status: :not_applicable,
        summary: "Test execution failed: #{e.message}"
      )
    end

    private

    def build_data_context
      context = {}

      Rails.logger.info "Building data context for test: #{test.test_key}"

      # Collect data silently, only log summary
      data_summary = []
      test.data_sources.each do |source|
        data = extract_data_source(source)
        context[source.to_sym] = data

        # Build compact summary
        if data.nil?
          data_summary << "#{source}: NO DATA"
        elsif data.is_a?(String)
          data_summary << "#{source}: #{data.length} chars"
        elsif data.is_a?(Array)
          data_summary << "#{source}: #{data.length} items"
        elsif data.is_a?(Hash)
          data_summary << "#{source}: #{data.keys.join(', ')}"
        else
          data_summary << "#{source}: #{data.class.name}"
        end
      end

      Rails.logger.info "  Data sources: #{data_summary.join(', ')}"

      # Always include URL
      context[:url] = discovered_page.url

      context
    end

    def extract_data_source(source)
      return nil unless page_data

      case source
      # Core content sources
      when "page_content"
        truncate_at_word_boundary(page_data.page_content, 5000)
      when "page_html", "html_content" # Support both names — legacy, returns truncated full page
        trim_html_intelligently(page_data.html_content, max_length: 50000)

      # Split HTML data sources for targeted analysis
      when "head_html"
        extract_head_html(page_data.html_content)
      when "nav_html"
        extract_nav_html(page_data.html_content)
      when "body_html"
        extract_body_html(page_data.html_content)

      # Structure sources
      when "headings"
        page_data.headings

      # Asset sources - consolidated
      when "asset_urls"
        # Combine all asset URLs into one comprehensive list
        {
          images: (page_data.images&.first(20) || []).map { |img| { type: "image", src: img["src"], alt: img["alt"] } },
          scripts: (page_data.scripts&.first(10) || []).map { |s| { type: "script", src: s["src"], async: s["async"], defer: s["defer"] } },
          stylesheets: (page_data.stylesheets&.first(10) || []).map { |s| { type: "stylesheet", href: s["href"] } },
          fonts: (page_data.fonts || []).map { |f| { type: "font", href: f["href"] || f["src"], family: f["family"] } }
        }

      # Link sources - split into internal/external
      when "internal_links"
        all_links = page_data.links || []
        page_url = URI.parse(discovered_page.url)
        all_links.select { |link|
          begin
            link_url = URI.parse(link["href"])
            link_url.host.nil? || link_url.host == page_url.host
          rescue
            true # Assume relative URLs are internal
          end
        }.first(20)
      when "external_links"
        all_links = page_data.links || []
        page_url = URI.parse(discovered_page.url)
        all_links.select { |link|
          begin
            link_url = URI.parse(link["href"])
            link_url.host.present? && link_url.host != page_url.host
          rescue
            false
          end
        }.first(20)

      # Visual sources
      when "colors"
        page_data.colors&.first(15)
      when "screenshots"
        # Return screenshot file paths for Claude Vision API analysis
        collect_screenshot_paths

      # Performance sources
      when "performance_data", "performance_metrics" # Support both names
        page_data.performance_metrics

      # Legacy support - map old names to new consolidated sources
      when "fonts", "images", "scripts", "stylesheets"
        extract_data_source("asset_urls")
      when "links"
        # Return both internal and external if generic "links" requested
        {
          internal: extract_data_source("internal_links"),
          external: extract_data_source("external_links")
        }
      when "asset_distribution", "total_page_weight"
        # Now part of performance_data
        extract_data_source("performance_data")
      when "meta_tags", "structured_data", "meta_title", "meta_description"
        # Deprecated - return nil to indicate not available
        nil
      else
        nil
      end
    end

    def analyze_with_ai(prompt, data_context)
      full_prompt = build_full_prompt(prompt, data_context)

      # Get AI config from audit (simplified - no test.ai_config anymore)
      ai_config = audit.ai_config.presence || {}
      model = ai_config["model"] || ai_config[:model] || "claude-opus-4-6"
      temperature = (ai_config["temperature"] || ai_config[:temperature] || 0.3).to_f

      # Check if this test uses screenshots — route to Vision API
      screenshot_paths = data_context[:screenshots]
      use_vision = screenshot_paths.is_a?(Array) && screenshot_paths.any?

      # Compact AI request logging
      Rails.logger.info "  AI Request: #{model} (temp: #{temperature})#{use_vision ? " [VISION: #{screenshot_paths.length} images]" : ""}"

      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: full_prompt }
      ]

      response = if use_vision
        OpenaiService.chat_with_images(
          messages: messages,
          image_paths: screenshot_paths,
          model: model,
          temperature: temperature,
          max_tokens: 2000
        )
      else
        OpenaiService.chat(
          messages: messages,
          model: model,
          temperature: temperature,
          max_tokens: 2000
        )
      end

      return create_result(
        status: :not_applicable,
        summary: "AI analysis unavailable",
        ai_prompt: full_prompt,
        data_context: data_context
      ) unless response

      # Parse JSON response
      json_text = response.strip.gsub(/^```json\s*\n/, "").gsub(/\n```\s*$/, "")

      begin
        parsed = JSON.parse(json_text)

        Rails.logger.info "  Result: #{parsed['status']} - #{parsed['summary']}"
        if parsed['details'].is_a?(Array)
          Rails.logger.info "  Details: #{parsed['details'].length} findings"
        end

        create_result(
          status: parsed["status"],
          summary: parsed["summary"],
          details: parsed["details"],
          ai_prompt: full_prompt,
          data_context: data_context,
          ai_response: response
        )
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse AI response for test #{test.test_key}: #{e.message}"
        Rails.logger.error "Response was: #{response.first(500)}"

        create_result(
          status: :not_applicable,
          summary: response.first(200),
          ai_prompt: full_prompt,
          data_context: data_context,
          ai_response: response
        )
      end
    end

    def build_full_prompt(prompt, data_context)
      <<~PROMPT
        You are analyzing a webpage for conversion rate optimization and user experience.

        Page URL: #{discovered_page.url}

        AVAILABLE DATA:
        #{format_data_context(data_context)}

        TEST INSTRUCTIONS:
        #{prompt}

        RESPONSE FORMAT:
        You must respond with a valid JSON object with the following structure:
        {
          "status": "passed" | "failed" | "not_applicable",
          "summary": "Brief one-sentence summary of the overall finding",
          "details": []
        }

        IMPORTANT:
        - Set status to "not_applicable" if this test doesn't apply to this website type
        - Set status to "passed" if the test criteria are met
        - Set status to "failed" if test criteria not met or critical issues are found
        - Only respond with the JSON object, no other text

        STRICT RULES FOR "details":
        - If status is "passed" or "not_applicable", details MUST be an empty array []. Do NOT list positive observations.
        - If status is "failed", details should list ONLY the specific issues found — nothing else.
        - One issue = one detail. Do NOT combine or inflate. If there's 1 problem, return 1 detail.
        - Every detail MUST be a concrete, verifiable issue you can point to in the data — not a general impression or opinion.
        - Do NOT include anything outside the scope of the TEST INSTRUCTIONS above.
      PROMPT
    end

    def format_data_context(data_context)
      formatted = []

      data_context.each do |key, value|
        next if value.nil? || (value.respond_to?(:empty?) && value.empty?)

        # Screenshots are sent as images via the Vision API, not as text
        if key.to_s == "screenshots"
          count = value.is_a?(Array) ? value.length : 0
          formatted << "Screenshots: #{count} screenshot image(s) attached above for visual analysis"
          formatted << ""
          next
        end

        formatted << "#{key.to_s.humanize}:"
        formatted << format_value(value)
        formatted << ""
      end

      formatted.join("\n")
    end

    def format_value(value)
      case value
      when String
        # HTML and pre-truncated content passes through as-is
        # Data sources already handle their own size limits
        value
      when Array
        value.first(10).to_json
      when Hash
        # Don't truncate hashes - let full content through
        JSON.pretty_generate(value)
      else
        value.to_s
      end
    end

    def system_prompt
      current_date = Time.current.strftime("%B %d, %Y")

      # Get custom system prompt from audit config, or use default
      ai_config = audit.ai_config.presence || {}
      custom_prompt = ai_config["systemPrompt"] || ai_config[:systemPrompt]

      base_prompt = if custom_prompt.present?
        custom_prompt
      else
        # Default prompt
        "You are an expert website auditor analyzing conversion optimization, user experience, design quality, and technical performance. Provide actionable, specific feedback."
      end

      # Add date awareness and test evaluation guidance
      <<~PROMPT
        #{base_prompt.strip}

        Current date: #{current_date}

        IMPORTANT TEST EVALUATION GUIDELINES:
        - Be a critical, objective auditor. Base every judgment on verifiable evidence from the provided data.
        - ONLY evaluate what the specific test instructions ask for. Do not expand scope or cross into other audit areas.
        - Mark "failed" when there are concrete, demonstrable issues — things you can point to in the HTML or screenshots.
        - Mark "passed" only when the specific criteria in the test instructions are genuinely met based on evidence.
        - Do NOT pad findings. If only 1-2 things are relevant, report only those.
        - Every claim must be backed by something observable in the data. No assumptions, no extrapolation.
      PROMPT
    end

    def create_result(status:, summary: nil, details: nil, ai_prompt: nil, data_context: nil, ai_response: nil)
      TestResult.create!(
        discovered_page: discovered_page,
        audit: audit,
        test_key: test.test_key,
        test_category: test.test_group.name.downcase.gsub(/\s+/, "_"),
        status: status,
        summary: summary,
        details: details,
        ai_prompt: ai_prompt,
        data_context: data_context,
        ai_response: ai_response
      )
    end

    # Collect screenshot file paths from both page_data.screenshots and page_screenshots records
    def collect_screenshot_paths
      paths = []

      # From page_data.screenshots (JSONB hash like { desktop: "/screenshots/...", mobile: "/screenshots/..." })
      if page_data&.screenshots.is_a?(Hash)
        page_data.screenshots.each_value do |path|
          paths << path if path.present? && screenshot_file_exists?(path)
        end
      end

      # From page_screenshots records (separate model with screenshot_url)
      discovered_page.page_screenshots.each do |ps|
        if ps.screenshot_url.present? && screenshot_file_exists?(ps.screenshot_url) && !paths.include?(ps.screenshot_url)
          paths << ps.screenshot_url
        end
      end

      if paths.empty?
        Rails.logger.warn "  No screenshot files found for page #{discovered_page.id}"
        return nil
      end

      Rails.logger.info "  Found #{paths.length} screenshot(s): #{paths.join(', ')}"
      paths
    end

    def screenshot_file_exists?(relative_path)
      filepath = Rails.root.join("public", relative_path.sub(%r{^/}, ""))
      File.exist?(filepath)
    end

    # ── Truncation helpers ────────────────────────────────────────────────

    def truncate_at_word_boundary(text, max_length)
      return nil if text.nil?
      return text if text.length <= max_length

      # Cut at max_length then backtrack to the last space
      truncated = text[0...max_length]
      last_space = truncated.rindex(/\s/)
      truncated = truncated[0...last_space] if last_space && last_space > max_length * 0.8
      truncated << "\n[content truncated at #{max_length} chars]"
    end

    # ── Shared attribute stripping ────────────────────────────────────────────

    NOISY_ATTRIBUTES = %w[
      srcset sizes loading decoding fetchpriority
      onclick onload onerror onmouseover onmouseout onfocus onblur onchange onsubmit
      onkeydown onkeyup onkeypress ontouchstart ontouchmove ontouchend
      tabindex draggable contenteditable spellcheck autocomplete autocapitalize
      translate inputmode enterkeyhint
    ].freeze

    def strip_noisy_attributes!(root)
      root.traverse do |node|
        next unless node.element?
        attrs_to_remove = []
        node.attributes.each do |name, attr|
          # Remove ALL data-* attributes (data-swiper-slide-index, data-testid, etc.)
          if name.start_with?("data-")
            attrs_to_remove << name
            next
          end
          # Remove known noisy attributes
          if NOISY_ATTRIBUTES.include?(name)
            attrs_to_remove << name
            next
          end
          # Remove any attribute with a very long value (base64 images, inline JSON, etc.)
          if attr.value && attr.value.length > 200
            attrs_to_remove << name
          end
        end
        attrs_to_remove.each { |a| node.remove_attribute(a) }
      end
    end

    # ── Split HTML data sources ──────────────────────────────────────────────

    def extract_head_html(html)
      return nil if html.nil?
      doc = Nokogiri::HTML(html)
      head = doc.at_css("head")
      return nil unless head

      # Remove all scripts and inline styles from head
      head.css("script", "style", "noscript").each(&:remove)
      head.css('link[rel="preload"], link[rel="prefetch"], link[rel="dns-prefetch"], link[rel="preconnect"]').each(&:remove)
      strip_noisy_attributes!(head)

      result = head.inner_html.squeeze(" \n").strip
      Rails.logger.info "  head_html: #{result.length} chars"
      result.first(10000) # Head should never need more than 10K
    rescue => e
      Rails.logger.warn "Failed to extract head HTML: #{e.message}"
      nil
    end

    def extract_nav_html(html)
      return nil if html.nil?
      doc = Nokogiri::HTML(html)

      # Find nav elements: <nav>, <header>, or elements with role="navigation"
      nav_elements = doc.css("nav, header, [role='navigation']")
      return nil if nav_elements.empty?

      # Clean each nav element
      nav_elements.each do |nav_el|
        nav_el.css("script, style, noscript, svg").each(&:remove)
        nav_el.css("[style]").each { |el| el.remove_attribute("style") }
        strip_noisy_attributes!(nav_el)
        # Strip class attributes to essentials
        nav_el.css("[class]").each do |el|
          classes = el["class"].split
          el["class"] = classes.first(2).join(" ") if classes.length > 2
        end
      end

      result = nav_elements.map(&:to_html).join("\n")
      Rails.logger.info "  nav_html: #{result.length} chars (#{nav_elements.length} elements)"
      result.first(15000) # Nav should never need more than 15K
    rescue => e
      Rails.logger.warn "Failed to extract nav HTML: #{e.message}"
      nil
    end

    def extract_body_html(html)
      return nil if html.nil?
      doc = Nokogiri::HTML(html)
      body = doc.at_css("body")
      return nil unless body

      # Remove nav/header elements entirely (they have their own data source)
      body.css("nav, header, [role='navigation']").each(&:remove)

      # Remove all scripts, styles, noscript, large SVGs
      body.css("script", "noscript", "style").each(&:remove)
      body.css("svg").each { |svg| svg.remove if svg.to_html.length > 500 }

      # Remove hidden elements
      body.css("[aria-hidden='true'], [hidden], .visually-hidden, .sr-only").each do |el|
        el.remove if el.to_html.length > 200
      end

      # Strip noise attributes
      body.css("[style]").each { |el| el.remove_attribute("style") }
      strip_noisy_attributes!(body)
      body.css("[class]").each do |el|
        classes = el["class"].split
        el["class"] = classes.first(3).join(" ") if classes.length > 3
      end

      # Collapse whitespace
      body.traverse do |node|
        if node.text? && node.content.strip.empty? && node.content.length > 1
          node.content = " "
        end
      end

      result = body.inner_html.squeeze("\n").strip
      Rails.logger.info "  body_html (no nav): #{result.length} chars"
      result.first(80000) # Body gets the lion's share
    rescue => e
      Rails.logger.warn "Failed to extract body HTML: #{e.message}"
      nil
    end

    def trim_html_intelligently(html, max_length: 50000)
      return nil if html.nil?

      doc = Nokogiri::HTML(html)

      # ── Clean <head>: keep only essential meta/link tags ──────────────────
      head = doc.at_css("head")
      if head
        # Remove ALL inline scripts and styles from head entirely
        head.css("script", "style", "noscript").each(&:remove)

        # Remove JSON-LD, preload/prefetch hints, and other bloat
        head.css('link[rel="preload"], link[rel="prefetch"], link[rel="dns-prefetch"], link[rel="preconnect"]').each(&:remove)
      end

      # ── Clean <body>: strip inline JS/CSS content, keep structure ────────
      body = doc.at_css("body")
      if body
        # Remove all script tags entirely (we have asset_urls data source for those)
        body.css("script", "noscript").each(&:remove)

        # Remove inline style tags but keep external stylesheet links
        body.css("style").each(&:remove)

        # Remove SVG sprites / hidden SVG blocks (often huge)
        body.css("svg").each do |svg|
          svg.remove if svg.to_html.length > 2000
        end

        # ── Collapse mega-navs: keep top-level links, remove nested dropdowns ──
        # Shopify mega-navs can be 30K+ chars of nested <li> items
        body.css("nav, header, [role='navigation']").each do |nav_el|
          # Find deeply nested lists (3+ levels deep) and replace with a summary
          nav_el.css("ul ul, ol ol").each do |nested_list|
            link_count = nested_list.css("a").length
            if link_count > 3
              placeholder = doc.create_element("li")
              placeholder.content = "<!-- #{link_count} dropdown links collapsed -->"
              nested_list.replace(placeholder)
            end
          end
        end

        # ── Remove hidden elements (display:none, aria-hidden, etc.) ──────
        body.css("[aria-hidden='true'], [hidden], .visually-hidden, .sr-only").each do |el|
          el.remove if el.to_html.length > 500
        end

        # Strip style attributes to reduce noise (layout info is in screenshots)
        body.css("[style]").each { |el| el.remove_attribute("style") }

        # Strip all noisy/non-semantic attributes (data-*, srcset, event handlers, etc.)
        strip_noisy_attributes!(body)

        # Strip verbose class attributes (keep first 3 classes max)
        body.css("[class]").each do |el|
          classes = el["class"].split
          el["class"] = classes.first(3).join(" ") if classes.length > 3
        end

        # Remove excessive whitespace between tags
        body.traverse do |node|
          if node.text? && node.content.strip.empty? && node.content.length > 1
            node.content = " "
          end
        end

        # Flatten deeply nested elements: anything more than 4 levels deep from <body> gets unwrapped
        # (keeps text content but removes the wrapper tags)
        # Collect first, then modify — avoids mutating tree during traversal
        deep_nodes = []
        body.traverse do |node|
          next unless node.element?
          next if node == body
          depth = 0
          ancestor = node.parent
          while ancestor && ancestor.element? && ancestor != body
            depth += 1
            ancestor = ancestor.parent
          end
          deep_nodes << node if depth > 4
        end
        deep_nodes.reverse_each do |node|
          node.replace(Nokogiri::HTML::DocumentFragment.parse(node.inner_html))
        end
      end

      cleaned_html = doc.to_html

      # Log the compression ratio
      Rails.logger.info "  HTML cleaned: #{html.length} → #{cleaned_html.length} chars (#{((1 - cleaned_html.length.to_f / html.length) * 100).round(1)}% reduction)"

      # Hard cap to stay within Claude's 200K token limit (~4 chars/token, leave room for system prompt + other data)
      if cleaned_html.length > max_length
        # Prioritize <body> content over <head> by extracting body and truncating from the end
        body_match = cleaned_html.match(/<body[^>]*>(.*)<\/body>/mi)
        head_match = cleaned_html.match(/<head[^>]*>(.*)<\/head>/mi)
        
        if body_match && head_match
          head_budget = [head_match[1].length, 5000].min  # Cap <head> at 5K
          body_budget = max_length - head_budget - 500     # Rest for <body>
          head_html = head_match[1].first(head_budget)
          body_html = body_match[1].first(body_budget)
          cleaned_html = "<html><head>#{head_html}</head><body>#{body_html}\n<!-- HTML truncated at #{max_length} chars --></body></html>"
        else
          cleaned_html = "#{cleaned_html.first(max_length)}\n<!-- HTML truncated at #{max_length} chars -->"
        end
        Rails.logger.info "  HTML capped to #{cleaned_html.length} chars (max: #{max_length})"
      end

      cleaned_html
    rescue => e
      Rails.logger.warn "Failed to trim HTML intelligently: #{e.message}"
      # Fallback: just strip script/style tags with regex
      fallback = html.gsub(/<script[^>]*>.*?<\/script>/mi, "")
                      .gsub(/<style[^>]*>.*?<\/style>/mi, "")
      Rails.logger.info "  Fallback HTML cleaning: #{html.length} → #{fallback.length} chars"
      fallback
    end
  end
end
