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
        page_data.page_content&.first(5000)
      when "page_html", "html_content" # Support both names
        # Smart HTML trimming - remove inline scripts/styles but keep structure
        trim_html_intelligently(page_data.html_content, max_length: 50000)

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
        }.first(30)
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
        }.first(30)

      # Visual sources
      when "colors"
        page_data.colors&.first(15)
      when "screenshots"
        # Note: Screenshots available but Claude vision API needed for analysis
        page_data.screenshots

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
      model = ai_config["model"] || ai_config[:model] || "gpt-4o"
      temperature = (ai_config["temperature"] || ai_config[:temperature] || 0.3).to_f

      # Compact AI request logging
      Rails.logger.info "  AI Request: #{model} (temp: #{temperature})"

      response = OpenaiService.chat(
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: full_prompt }
        ],
        model: model,
        temperature: temperature,
        max_tokens: 2000
      )

      return create_result(status: :not_applicable, summary: "AI analysis unavailable") unless response

      # Parse JSON response
      json_text = response.strip.gsub(/^```json\s*\n/, "").gsub(/\n```\s*$/, "")

      begin
        parsed = JSON.parse(json_text)

        Rails.logger.info "  Result: #{parsed['status']} - #{parsed['summary']}"

        create_result(
          status: parsed["status"],
          summary: parsed["summary"]
        )
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse AI response for test #{test.test_key}: #{e.message}"
        Rails.logger.error "Response was: #{response.first(500)}"

        create_result(
          status: :not_applicable,
          summary: response.first(200)
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
          "summary": "Brief one-sentence summary of the finding"
        }

        IMPORTANT:
        - Set status to "not_applicable" if this test doesn't apply to this website type
        - Set status to "passed" if the test criteria are met
        - Set status to "failed" if test criteria not met or critical issues are found
        - Be objective and specific in your analysis
        - Only respond with the JSON object, no other text
      PROMPT
    end

    def format_data_context(data_context)
      formatted = []

      data_context.each do |key, value|
        next if value.nil? || (value.respond_to?(:empty?) && value.empty?)

        formatted << "#{key.to_s.humanize}:"
        formatted << format_value(value)
        formatted << ""
      end

      formatted.join("\n")
    end

    def format_value(value)
      case value
      when String
        value.length > 1000 ? "#{value.first(1000)}..." : value
      when Array
        value.first(10).to_json
      when Hash
        JSON.pretty_generate(value).lines.first(20).join
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
        - Only mark tests as "failed" for significant issues that materially impact the user experience, conversion rates, or functionality
        - For subjective quality tests (like typos, grammar, design), use your judgment - minor imperfections should still pass unless they're particularly egregious or numerous
        - Reserve "failed" status for clear, objective failures or when the test asks for strict equivalency (e.g., "Does the page have an announcement bar?" requires a yes/no answer)
        - When in doubt between "passed" and "failed", lean toward "passed" if the issue is minor or debatable
        - Focus on actionable problems that genuinely need fixing, not nitpicking
      PROMPT
    end

    def create_result(status:, summary: nil)
      TestResult.create!(
        discovered_page: discovered_page,
        audit: audit,
        test_key: test.test_key,
        test_category: test.test_group.name.downcase.gsub(/\s+/, "_"),
        status: status,
        summary: summary
      )
    end

    def trim_html_intelligently(html, max_length: 50000)
      return nil if html.nil?
      return html if html.length <= max_length

      # Parse HTML and remove verbose inline content
      doc = Nokogiri::HTML(html)

      # Remove inline scripts (but keep src references)
      doc.css("script").each do |script|
        if script["src"].nil? && script.text.length > 100
          script.content = "/* inline script removed */"
        end
      end

      # Remove inline styles (but keep external references)
      doc.css("style").each do |style|
        if style.text.length > 100
          style.content = "/* inline styles removed */"
        end
      end

      # Get the cleaned HTML
      cleaned_html = doc.to_html

      # If still too long, truncate with indication
      if cleaned_html.length > max_length
        "#{cleaned_html.first(max_length)}\n<!-- HTML truncated at #{max_length} characters -->"
      else
        cleaned_html
      end
    rescue => e
      Rails.logger.warn "Failed to trim HTML intelligently: #{e.message}"
      # Fallback to simple truncation
      html.first(max_length)
    end
  end
end
