# frozen_string_literal: true

module AuditWorkflow
  class ResultsSynthesizer
    attr_reader :audit

    def initialize(audit)
      @audit = audit
    end

    def generate_report
      {
        summary: build_summary,
        score: calculate_overall_score,
        prioritized_findings: prioritize_findings,
        evidence: gather_evidence
      }
    end

    private

    def build_summary
      priority_pages = audit.discovered_pages.high_priority
      all_tests = AdaptiveTest.joins(:discovered_page)
                              .where(discovered_pages: { audit_id: audit.id })
                              .high_impact

      critical_issues = all_tests.select { |t| issue_is_critical?(t) }

      # Use AI to synthesize findings into executive summary
      ai_summary = ask_ai_for_executive_summary(priority_pages, critical_issues)

      return ai_summary if ai_summary

      # Fallback to template summary
      generate_template_summary(priority_pages, critical_issues)
    end

    def ask_ai_for_executive_summary(pages, issues)
      findings_text = issues.first(5).map do |test|
        "- #{test.discovered_page.page_type}: #{describe_issue(test)}"
      end.join("\n")

      system_prompt = <<~PROMPT
        You are a CRO consultant writing an executive summary for a client.
        Synthesize audit findings into a clear, actionable 3-4 paragraph summary.

        Include:
        1. What we analyzed
        2. Top 3 critical issues found
        3. Expected business impact
        4. Recommended priority order

        Write in professional but conversational tone. Be specific.
      PROMPT

      user_prompt = <<~PROMPT
        Create executive summary:

        Pages Analyzed: #{pages.count} high-priority pages from #{audit.discovered_pages.count} total
        Critical Issues Found: #{issues.count}

        Top Findings:
        #{findings_text}

        Write the executive summary.
      PROMPT

      OpenaiService.chat(
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt }
        ],
        temperature: 0.7,
        max_tokens: 600
      )
    rescue StandardError => e
      Rails.logger.error("AI summary synthesis failed: #{e.message}")
      nil
    end

    def generate_template_summary(priority_pages, critical_issues)
      summary = []
      summary << "Analyzed #{priority_pages.count} high-priority pages from #{audit.discovered_pages.count} discovered pages."
      summary << ""
      summary << "Critical findings: #{critical_issues.count}"
      summary << ""

      # Top 3 issues
      critical_issues.first(3).each do |test|
        summary << format_finding(test)
      end

      summary << ""
      summary << "Next steps: Address critical issues first. See detailed findings below."

      summary.join("\n")
    end

    def calculate_overall_score
      tests = AdaptiveTest.joins(:discovered_page)
                          .where(discovered_pages: { audit_id: audit.id })

      return 100 if tests.empty?

      # Weight by impact score
      weighted_sum = tests.sum { |t| t.impact_score * test_success_rate(t) }
      total_weight = tests.sum(&:impact_score)

      (weighted_sum / total_weight.to_f).round
    end

    def test_success_rate(test)
      # Determine if test passed/failed
      case test.test_type
      when "contrast_analysis"
        test.results["low_contrast_count"] == 0 ? 1.0 : [ 1.0 - (test.results["low_contrast_count"] * 0.1), 0.3 ].max
      when "cta_prominence"
        test.results["has_prominent"] ? 1.0 : 0.4
      when "trust_signals"
        trust_count = test.results["trust_signal_count"] || 0
        (trust_count / 6.0).clamp(0, 1)
      else
        0.8 # Default
      end
    end

    def prioritize_findings
      tests = AdaptiveTest.joins(:discovered_page)
                          .where(discovered_pages: { audit_id: audit.id })
                          .by_impact

      findings = []

      tests.each do |test|
        if issue_is_critical?(test)
          findings << {
            priority: "CRITICAL",
            page_url: test.discovered_page.url,
            page_type: test.discovered_page.page_type,
            issue: describe_issue(test),
            impact: "#{test.impact_score}/100",
            recommendation: recommend_fix(test)
          }
        end
      end

      findings
    end

    def issue_is_critical?(test)
      return true if test.impact_score >= 85

      case test.test_type
      when "cta_prominence"
        !test.results["has_prominent"]
      when "contrast_analysis"
        test.results["low_contrast_count"] > 5
      when "trust_signals"
        (test.results["trust_signal_count"] || 0) < 2
      else
        false
      end
    end

    def describe_issue(test)
      case test.test_type
      when "cta_prominence"
        "No prominent call-to-action detected"
      when "contrast_analysis"
        "#{test.results['low_contrast_count']} elements with insufficient contrast"
      when "trust_signals"
        "Only #{test.results['trust_signal_count']} trust signals present"
      when "layout_density"
        "Excessive DOM complexity: #{test.results['elements_above_fold']} elements above fold"
      else
        test.test_type.humanize
      end
    end

    def recommend_fix(test)
      case test.test_type
      when "cta_prominence"
        "Add a prominent CTA button (120px+ wide, high contrast) above the fold with action-oriented text."
      when "contrast_analysis"
        "Increase text contrast to meet WCAG AA standard (4.5:1 ratio). Use darker colors."
      when "trust_signals"
        "Add phone number, customer reviews, security badges, or payment logos to build credibility."
      when "layout_density"
        "Simplify page structure. Remove unnecessary wrapper divs. Focus on essential content."
      else
        "Review and optimize this element."
      end
    end

    def format_finding(test)
      "❌ #{test.discovered_page.page_type.upcase}: #{describe_issue(test)}"
    end

    def gather_evidence
      screenshots = PageScreenshot.joins(:discovered_page)
                                  .where(discovered_pages: { audit_id: audit.id })

      {
        screenshot_count: screenshots.count,
        screenshots_by_page: screenshots.group_by { |s| s.discovered_page.url }
      }
    end
  end
end
