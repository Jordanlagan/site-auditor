# frozen_string_literal: true

module AuditWorkflow
  class ResultsSynthesizer
    attr_reader :audit

    def initialize(audit)
      @audit = audit
    end

    def generate_report
      insights = generate_page_insights

      {
        summary: build_executive_summary(insights),
        score: calculate_overall_score(insights),
        page_insights: insights
      }
    end

    private

    def generate_page_insights
      audit.discovered_pages.high_priority.map do |page|
        tests = page.adaptive_tests.to_a
        screenshots = page.page_screenshots.to_a

        {
          page_url: page.url,
          page_type: page.page_type,
          priority_score: page.priority_score,
          insights: generate_specific_insights(page, tests),
          screenshots: screenshots.map do |ss|
            {
              device_type: ss.device_type,
              url: ss.screenshot_url,
              viewport_width: ss.viewport_width,
              viewport_height: ss.viewport_height
            }
          end
        }
      end
    end

    def generate_specific_insights(page, tests)
      # Gather all test data
      test_data = tests.map { |t| { type: t.test_type, results: t.results } }

      # Use AI to generate SPECIFIC, actionable insights
      ai_insights = ask_ai_for_specific_insights(page, test_data)

      return ai_insights if ai_insights.present?

      # Fallback: generate basic insights from test data
      generate_fallback_insights(page, tests)
    end

    def ask_ai_for_specific_insights(page, test_data)
      system_prompt = <<~PROMPT
        You are a CRO expert analyzing a webpage. Generate SPECIFIC, actionable insights.

        Rules:
        - Be SPECIFIC with numbers, colors, locations
        - Focus on what's MISSING or WRONG
        - Provide EXACT recommendations (don't say "improve CTA", say "Change button from gray to blue (#0066CC)")
        - Only mention issues that actually matter for conversions
        - Write 3-5 insights maximum, prioritized by impact

        Format each insight as:
        {
          "issue": "Specific problem found",
          "impact": "Why this hurts conversions",
          "recommendation": "Exact action to take",
          "priority": "critical|high|medium"
        }

        Return a JSON array of insights.
      PROMPT

      test_summary = test_data.map do |t|
        "#{t[:type]}: #{t[:results].to_json}"
      end.join("\n")

      user_prompt = <<~PROMPT
        Analyze this #{page.page_type} page:
        URL: #{page.url}

        Test Results:
        #{test_summary}

        Generate specific CRO insights in JSON array format.
      PROMPT

      response = OpenaiService.analyze_with_json(
        system_prompt: system_prompt,
        user_prompt: user_prompt
      )

      # Parse and validate response
      return nil unless response.is_a?(Array)

      response.map do |insight|
        {
          issue: insight["issue"],
          impact: insight["impact"],
          recommendation: insight["recommendation"],
          priority: insight["priority"] || "medium"
        }
      end
    rescue StandardError => e
      Rails.logger.error("AI insight generation failed: #{e.message}")
      nil
    end

    def generate_fallback_insights(page, tests)
      insights = []

      tests.each do |test|
        case test.test_type
        when "contrast_analysis"
          if test.results["low_contrast_count"].to_i > 0
            insights << {
              issue: "#{test.results['low_contrast_count']} buttons/CTAs have poor contrast ratios",
              impact: "Users with vision issues cannot see your calls-to-action",
              recommendation: "Increase button contrast to at least 4.5:1 (WCAG AA standard). Use a color contrast checker.",
              priority: "high"
            }
          end

        when "cta_prominence"
          if !test.results["has_prominent"]
            insights << {
              issue: "No prominent call-to-action detected above the fold",
              impact: "Visitors don't know what action to take first",
              recommendation: "Add a clear, high-contrast CTA button in the hero section (above 800px). Make it at least 200px wide.",
              priority: "critical"
            }
          elsif test.results["competing"]
            insights << {
              issue: "#{test.results['above_fold']} competing CTAs above the fold",
              impact: "Multiple options cause decision paralysis and split focus",
              recommendation: "Keep ONE primary CTA above fold. Move secondary actions below.",
              priority: "high"
            }
          end

        when "trust_signals"
          missing = []
          missing << "phone number" unless test.results["phone_visible"]
          missing << "email address" unless test.results["email_visible"]
          missing << "security badges" unless test.results["ssl_badge"]
          missing << "payment logos" unless test.results["payment_badges"]
          missing << "customer reviews" unless test.results["review_elements"]

          if missing.any?
            insights << {
              issue: "Missing key trust signals: #{missing.join(', ')}",
              impact: "80% of users check for trust indicators. Missing these loses 30-40% of potential conversions",
              recommendation: "Add: #{missing.map { |m| m.capitalize }.join(', ')}. Place in header (phone) and near CTAs (badges/reviews).",
              priority: missing.include?("phone number") ? "high" : "medium"
            }
          end

        when "layout_density"
          if test.results["excessive_density"]
            insights << {
              issue: "Page is overcrowded with #{test.results['elements_above_fold']} elements above fold",
              impact: "Cognitive overload reduces focus and conversions by 25%",
              recommendation: "Cut elements to under 300. Remove: redundant nav links, excessive copy, non-essential graphics.",
              priority: "medium"
            }
          end
        end
      end

      insights.sort_by { |i| priority_order(i[:priority]) }.first(5)
    end

    def priority_order(priority)
      { "critical" => 0, "high" => 1, "medium" => 2, "low" => 3 }[priority] || 4
    end

    def build_executive_summary(insights)
      critical_count = insights.sum { |p| p[:insights].count { |i| i[:priority] == "critical" } }
      high_count = insights.sum { |p| p[:insights].count { |i| i[:priority] == "high" } }

      # Use AI to write executive summary
      ai_summary = ask_ai_for_executive_summary(insights, critical_count, high_count)
      return ai_summary if ai_summary

      # Fallback summary
      <<~SUMMARY.strip
        Analyzed #{insights.count} high-priority pages and found #{critical_count} critical and #{high_count} high-priority conversion issues. Key issues: #{insights.flat_map { |p| p[:insights] }.sort_by { |i| priority_order(i[:priority]) }.first(3).map { |i| i[:issue] }.join("; ")}. These issues block users from converting and should be fixed immediately.
      SUMMARY
    end

    def ask_ai_for_executive_summary(insights, critical_count, high_count)
      top_issues = insights.flat_map { |p|
        p[:insights].map { |i| "- #{p[:page_type]} page: #{i[:issue]}" }
      }.first(5).join("\n")

      system_prompt = <<~PROMPT
        You are a CRO consultant writing an executive summary for a client.
        Write ONE paragraph (3-4 sentences) that:
        1. States what was analyzed
        2. Lists the top issues found (be specific)
        3. States why these matter (no made-up percentages)

        Be direct. No fluff. No emojis. No percentage claims you can't back up.
      PROMPT

      user_prompt = <<~PROMPT
        Site: #{audit.url}
        Pages analyzed: #{insights.count} high-priority pages
        Critical issues: #{critical_count}
        High-priority issues: #{high_count}

        Top issues:
        #{top_issues}

        Write executive summary.
      PROMPT

      OpenaiService.chat(
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt }
        ],
        temperature: 0.7,
        max_tokens: 400
      )
    rescue StandardError => e
      Rails.logger.error("AI executive summary failed: #{e.message}")
      nil
    end

    def calculate_overall_score(insights)
      return 100 if insights.empty?

      total_issues = insights.sum { |p| p[:insights].count }
      critical = insights.sum { |p| p[:insights].count { |i| i[:priority] == "critical" } }
      high = insights.sum { |p| p[:insights].count { |i| i[:priority] == "high" } }

      # Score: start at 100, deduct points
      score = 100
      score -= (critical * 20) # -20 per critical
      score -= (high * 10)     # -10 per high
      score -= ((total_issues - critical - high) * 5) # -5 per medium/low

      [ score, 0 ].max
    end
  end
end
