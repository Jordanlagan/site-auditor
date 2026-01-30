module Tests
  module V1
    class BaseTest
      attr_reader :discovered_page, :page_data, :audit

      def initialize(discovered_page)
        @discovered_page = discovered_page
        @page_data = discovered_page.page_data
        @audit = discovered_page.audit
      end

      def run!
        raise NotImplementedError, "Subclasses must implement #run!"
      end

      protected

      # Create a test result
      def create_result(status:, score: nil, summary: nil, details: {}, ai_reasoning: nil, recommendation: nil, priority: 3)
        TestResult.create!(
          discovered_page: discovered_page,
          audit: audit,
          test_key: test_key,
          test_category: test_category,
          status: status,
          score: score,
          summary: summary,
          details: details,
          ai_reasoning: ai_reasoning,
          recommendation: recommendation,
          priority: priority
        )
      end

      # Call OpenAI for analysis
      def analyze_with_ai(prompt, data_context)
        full_prompt = build_full_prompt(prompt, data_context)

        # Get AI config from audit or use defaults
        ai_config = audit.ai_config.presence || {}
        model = ai_config["model"] || ai_config[:model] || "gpt-4o"
        temperature = (ai_config["temperature"] || ai_config[:temperature] || 0.3).to_f
        custom_system_prompt = ai_config["systemPrompt"] || ai_config[:systemPrompt]

        response = OpenaiService.chat(
          messages: [
            { role: "system", content: custom_system_prompt || system_prompt },
            { role: "user", content: full_prompt }
          ],
          model: model,
          temperature: temperature,
          max_tokens: 2000
        )

        return not_applicable(summary: "AI analysis unavailable") unless response

        # Parse JSON response (strip markdown code blocks if present)
        json_text = response.strip
        json_text = json_text.gsub(/^```json\s*\n/, "").gsub(/\n```\s*$/, "") # Remove ```json wrappers

        begin
          parsed = JSON.parse(json_text)

          create_result(
            status: parsed["status"],
            score: parsed["score"],
            summary: parsed["summary"],
            details: parsed["details"] || {},
            ai_reasoning: parsed["reasoning"],
            recommendation: parsed["recommendation"],
            priority: 3
          )
        rescue JSON::ParserError => e
          Rails.logger.error "Failed to parse AI response: #{e.message}"
          Rails.logger.error "Response was: #{response.first(500)}"

          # Fallback: use raw response
          create_result(
            status: :not_applicable,
            summary: response.first(200),
            details: { ai_response: response, parse_error: e.message }
          )
        end
      end

      def build_full_prompt(prompt, data_context)
        <<~PROMPT
          You are analyzing a webpage for conversion rate optimization and user experience.

          Page URL: #{discovered_page.url}

          AVAILABLE DATA:
          #{format_data_context(data_context)}

          FIRST: Determine if this test is relevant for this specific website type.
          Consider:
          - Is this feature typically expected for this type of website?
          - Does the website's purpose/industry make this test applicable?
          - If clearly not applicable (e.g., testing e-commerce features on a blog), set status to "not_applicable"

          TASK:
          #{prompt}

          Provide your analysis in JSON format with the following structure:
          {
            "status": "passed" | "failed" | "warning" | "not_applicable",
            "score": 0-100,
            "summary": "Brief 1-2 sentence summary",
            "details": {
              "findings": ["specific finding 1", "specific finding 2"],
              "evidence": ["quote or observation 1", "quote or observation 2"]
            },
            "reasoning": "Detailed explanation of your assessment",
            "recommendation": "Specific actionable recommendation if status is failed or warning"
          }
        PROMPT
      end

      def format_data_context(data)
        data.map { |key, value| "#{key.to_s.upcase}:\n#{format_value(value)}" }.join("\n\n")
      end

      def format_value(value)
        case value
        when Hash
          JSON.pretty_generate(value)
        when Array
          value.take(50).map { |v| "- #{v.is_a?(Hash) ? JSON.generate(v) : v}" }.join("\n")
        else
          value.to_s
        end
      end

      def system_prompt
        <<~PROMPT
          You are an expert in conversion rate optimization (CRO), user experience (UX), and web design.
          Your role is to analyze websites and provide actionable, specific feedback.

          When analyzing:
          - Be specific and cite evidence from the provided data
          - Consider industry best practices and modern web standards
          - Prioritize user experience and conversion optimization
          - Be critical but fair in your assessment
          - Provide actionable recommendations

          Always respond with valid JSON matching the requested structure.
        PROMPT
      end

      def test_key
        self.class.name.demodulize.underscore
      end

      def test_category
        # Override in subclasses
        "general"
      end

      # Helper to return not_applicable result
      def not_applicable(summary: "Test not applicable", details: {})
        create_result(
          status: :not_applicable,
          summary: summary,
          details: details
        )
      end

      # Helper to find the primary navigation element
      def find_primary_nav
        return nil unless page_data&.html_content.present?

        doc = Nokogiri::HTML(page_data.html_content)

        # Strategy 1: Look for nav with role="navigation" in header
        primary_nav = doc.at_css('header nav[role="navigation"]') || doc.at_css('header nav[aria-label*="main" i]')
        return primary_nav if primary_nav

        # Strategy 2: Find the nav with the most links in the header
        header = doc.at_css("header")
        if header
          navs = header.css("nav")
          primary_nav = navs.max_by { |nav| nav.css("a").count }
          return primary_nav if primary_nav && primary_nav.css("a").count > 2
        end

        # Strategy 3: First nav element in the document with substantial links
        navs = doc.css("nav")
        primary_nav = navs.find { |nav| nav.css("a").count >= 3 && nav.css("a").count <= 20 }
        return primary_nav if primary_nav

        # Fallback: First nav or header
        doc.at_css("nav") || doc.at_css("header")
      end

      # Helper to get primary nav HTML snippet
      def primary_nav_html
        nav = find_primary_nav
        nav ? nav.to_html.first(3000) : ""
      end

      # Helper to get primary nav links
      def primary_nav_links
        nav = find_primary_nav
        return [] unless nav

        nav.css("a").map { |a| { text: a.text.strip, href: a["href"] } }.take(20)
      end
    end
  end
end
