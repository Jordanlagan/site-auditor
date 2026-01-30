# frozen_string_literal: true

module AuditWorkflow
  class AdaptiveAnalyzer
    attr_reader :page

    def initialize(page)
      @page = page
    end

    def run_contextual_tests
      # Collect comprehensive page data instead of running selective tests

      client = Audits::HttpClient.new(page.url).fetch
      unless client&.success?
        Rails.logger.warn "Failed to fetch page #{page.url} for data collection"
        return
      end

      @doc = client.document
      unless @doc
        Rails.logger.warn "No document returned for page #{page.url}"
        return
      end

      # Collect all metrics
      collector = PageDataCollector.new(page, @doc, client.response&.body)
      all_metrics = collector.collect_all_metrics

      # Run simple verifiable tests
      test_runner = SimpleTestRunner.new(page, @doc, all_metrics)
      test_results = test_runner.run_all_tests

      # Generate AI summary
      summarizer = PageSummarizer.new(page, @doc, all_metrics)
      page_summary = summarizer.generate_summary

      # Store comprehensive metrics, test results, and summary
      page.update!(
        crawl_metadata: page.crawl_metadata.merge({
          comprehensive_metrics: all_metrics,
          simple_tests: test_results,
          ai_summary: page_summary,
          collected_at: Time.current
        })
      )

      Rails.logger.info "Collected comprehensive metrics and summary for #{page.url}"
    end

    private

    def decide_tests
      # Use AI to intelligently decide which tests to run
      user_context = gather_user_context
      ai_tests = ask_ai_for_test_strategy(user_context)

      if ai_tests && ai_tests.any?
        return ai_tests
      end

      # Fallback to heuristic decision-making
      fallback_test_selection(user_context)
    end

    def ask_ai_for_test_strategy(user_context)
      metadata = page.crawl_metadata

      system_prompt = <<~PROMPT
        You are a CRO expert deciding which technical tests to run on a webpage.

        Available tests:
        - contrast_analysis: Check WCAG color contrast ratios
        - cta_prominence: Measure CTA button size/visibility
        - trust_signals: Detect phone, reviews, security badges
        - layout_density: Analyze DOM complexity
        - form_friction: Evaluate form field count and usability
        - typography_scan: Check font sizes, line-height, hierarchy
        - color_palette: Analyze color usage and consistency

        Select 3-5 tests that will provide the most actionable insights for THIS specific page.
        Respond with JSON: { "tests": ["contrast_analysis", "cta_prominence"], "reasoning": "..." }
      PROMPT

      user_responses = user_context.map { |c| "Q: #{c[:type]} - A: #{c[:response]}" }.join("\n")

      user_prompt = <<~PROMPT
        Decide which tests to run:

        Page: #{page.url}
        Type: #{page.page_type}
        Forms: #{metadata['form_count']}
        Buttons: #{metadata['button_count']}

        User told us:
        #{user_responses.presence || '(No user input yet)'}

        Which tests will be most valuable?
      PROMPT

      result = OpenaiService.analyze_with_json(
        system_prompt: system_prompt,
        user_prompt: user_prompt
      )

      if result && result["tests"]
        Rails.logger.info("AI selected tests: #{result['tests']} - #{result['reasoning']}")
        return result["tests"]
      end

      nil
    rescue StandardError => e
      Rails.logger.error("AI test selection failed: #{e.message}")
      nil
    end

    def fallback_test_selection(user_context)
      tests = []

      # Always run core CRO checks
      tests << "contrast_analysis"
      tests << "cta_prominence"

      # Conditional tests based on page type
      case page.page_type
      when "homepage", "landing"
        tests << "trust_signals"
        tests << "layout_density"
      when "pricing", "checkout"
        tests << "form_friction" if page.crawl_metadata["form_count"] > 0
        tests << "trust_signals"
      when "product"
        tests << "cta_prominence"
        tests << "mobile_usability"
      end

      # Add tests based on user responses
      if competing_ctas_identified?(user_context)
        tests << "cta_conflict_analysis"
      end

      tests.uniq
    end

    def run_test(test_type)
      result = case test_type
      when "contrast_analysis"
                 run_contrast_test
      when "cta_prominence"
                 run_cta_test
      when "trust_signals"
                 run_trust_test
      when "layout_density"
                 run_density_test
      when "form_friction"
                 run_form_test
      else
                 { note: "Test #{test_type} not yet implemented" }
      end

      impact_score = calculate_impact(test_type, result)

      AdaptiveTest.create!(
        discovered_page: page,
        test_type: test_type,
        decision_reason: "Selected based on #{page.page_type} analysis and user context",
        results: result,
        impact_score: impact_score
      )
    end

    def run_contrast_test
      # Analyze contrast ratios directly
      issues = []

      @doc.css('button, input[type="submit"], input[type="button"], a.btn, a.button, [role="button"]').first(20).each do |btn|
        contrast = calculate_element_contrast(btn)
        if contrast && contrast[:ratio] < 4.5
          issues << {
            element: btn.name,
            text: btn.text.strip[0..50],
            ratio: contrast[:ratio].round(2)
          }
        end
      end

      {
        low_contrast_count: issues.size,
        examples: issues.first(3)
      }
    end

    def calculate_element_contrast(element)
      style = element["style"].to_s
      fg_color = extract_color_from_style(style, "color")
      bg_color = extract_color_from_style(style, "background-color") || "#FFFFFF"

      return nil unless fg_color || bg_color

      fg = parse_color(fg_color || "#000000")
      bg = parse_color(bg_color)

      ratio = calculate_contrast_ratio(fg, bg)
      { fg: fg_color, bg: bg_color, ratio: ratio }
    end

    def extract_color_from_style(style, property)
      match = style.match(/#{property}\s*:\s*([^;]+);?/)
      match ? match[1].strip : nil
    end

    def parse_color(color_string)
      if color_string.start_with?("#")
        hex = color_string[1..]
        hex = hex.chars.map { |c| c * 2 }.join if hex.length == 3
        { r: hex[0..1].to_i(16), g: hex[2..3].to_i(16), b: hex[4..5].to_i(16) }
      else
        { r: 0, g: 0, b: 0 }
      end
    end

    def calculate_contrast_ratio(fg, bg)
      l1 = relative_luminance(fg)
      l2 = relative_luminance(bg)
      lighter = [ l1, l2 ].max
      darker = [ l1, l2 ].min
      (lighter + 0.05) / (darker + 0.05)
    end

    def relative_luminance(color)
      r = linearize(color[:r] / 255.0)
      g = linearize(color[:g] / 255.0)
      b = linearize(color[:b] / 255.0)
      0.2126 * r + 0.7152 * g + 0.0722 * b
    end

    def linearize(val)
      val <= 0.03928 ? val / 12.92 : ((val + 0.055) / 1.055)**2.4
    end

    def run_cta_test
      buttons = @doc.css('button, input[type="submit"], input[type="button"], a.btn, a.button, [role="button"]')

      prominent_ctas = buttons.select do |btn|
        style = btn["style"].to_s
        width = style.match(/width\s*:\s*(\d+)/)&.captures&.first&.to_i || 0
        height = style.match(/height\s*:\s*(\d+)/)&.captures&.first&.to_i || 0
        width > 120 || height > 40 || btn.text.strip.length > 10
      end

      above_fold = buttons.first(10) # Approximate above fold

      {
        buttons_found: buttons.size,
        above_fold: above_fold.size,
        has_prominent: prominent_ctas.any?,
        competing: above_fold.size > 3
      }
    end

    def run_trust_test
      body_text = @doc.css("body").text

      {
        phone_visible: body_text.match?(/\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/),
        email_visible: body_text.match?(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/),
        ssl_badge: @doc.css("img").any? { |img| img["alt"].to_s.downcase.include?("secure") },
        payment_badges: @doc.css("img").any? { |img| img["alt"].to_s.downcase.match?(/visa|mastercard|paypal/) },
        review_elements: @doc.css('[class*="review"], [id*="review"]').any?,
        trust_signal_count: 0
      }.tap { |h| h[:trust_signal_count] = h.values.count(true) }
    end

    def run_density_test
      above_fold = @doc.css("body").first&.element_children&.first(10) || []
      total_elements = above_fold.sum { |section| section.css("*").size }

      {
        elements_above_fold: total_elements,
        max_nesting_depth: 0,
        excessive_density: total_elements > 500
      }
    end

    def run_form_test
      # Placeholder for form friction analysis
      { note: "Form friction analysis coming soon" }
    end

    def calculate_impact(test_type, result)
      base_scores = {
        "contrast_analysis" => 85,
        "cta_prominence" => 95,
        "trust_signals" => 90,
        "layout_density" => 70,
        "form_friction" => 88
      }

      base_scores[test_type] || 50
    end

    def gather_user_context
      page.audit_questions.answered.map do |q|
        { type: q.question_type, response: q.user_response }
      end
    end

    def competing_ctas_identified?(context)
      context.any? { |q| q[:type] == "competing_actions" && q[:response]&.include?("compete") }
    end

    def unclear_purpose?(context)
      context.any? { |q| q[:type] == "page_purpose" && q[:response]&.include?("Unsure") }
    end
  end
end
