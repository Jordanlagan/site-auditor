# frozen_string_literal: true

module AuditWorkflow
  class AiPrioritizer
    attr_reader :audit, :reasoning

    def initialize(audit)
      @audit = audit
      @reasoning = []
    end

    def score_pages
      audit.discovered_pages.each do |page|
        score = calculate_priority_score(page)
        page.update!(priority_score: score)
      end

      generate_reasoning
    end

    private

    def calculate_priority_score(page)
      # Homepage always gets maximum priority
      return 100 if page.page_type == "homepage"
      
      # Use AI to intelligently score page importance
      ai_score = ask_ai_to_score_page(page)
      return ai_score if ai_score

      # Fallback to heuristics if AI fails
      fallback_heuristic_score(page)
    end

    def ask_ai_to_score_page(page)
      metadata = page.crawl_metadata

      system_prompt = <<~PROMPT
        You are an expert CRO consultant analyzing website pages for conversion impact.
        Score pages 0-100 based on their likely influence on business outcomes.

        High scores (80-100): Direct revenue impact (homepage, pricing, checkout, key landing pages)
        Medium scores (50-79): Supporting conversion (product pages, contact, trust-building)
        Low scores (0-49): Informational/utility (blog, help docs, legal pages)

        Consider: page type, conversion elements (forms/CTAs), site depth, content signals.
        Respond with JSON: { "score": 85, "reasoning": "..." }
      PROMPT

      user_prompt = <<~PROMPT
        Analyze this page:

        URL: #{page.url}
        Type: #{page.page_type}
        Depth: #{metadata['depth']} levels from homepage
        Title: #{metadata['title']}
        Forms: #{metadata['form_count']}
        Buttons/CTAs: #{metadata['button_count']}
        Word count: #{metadata['word_count']}
        Has navigation: #{metadata['has_nav']}

        What priority score (0-100) should this page receive?
      PROMPT

      result = OpenaiService.analyze_with_json(
        system_prompt: system_prompt,
        user_prompt: user_prompt
      )

      if result && result["score"]
        @reasoning << {
          page: page.url,
          ai_score: result["score"],
          ai_reasoning: result["reasoning"]
        }
        result["score"].to_i
      end
    rescue StandardError => e
      Rails.logger.error("AI scoring failed for #{page.url}: #{e.message}")
      nil
    end

    def fallback_heuristic_score(page)
      score = 0
      metadata = page.crawl_metadata

      # Page type weights
      type_scores = {
        "homepage" => 100,
        "pricing" => 95,
        "product" => 90,
        "checkout" => 95,
        "landing" => 85,
        "contact" => 70,
        "about" => 50,
        "blog" => 40,
        "other" => 30
      }

      score += type_scores[page.page_type] || 30
      score -= (metadata["depth"] * 10)
      score += (metadata["form_count"] * 5)
      score += (metadata["button_count"] * 2)
      score += 10 if metadata["has_nav"]

      [ [ score, 100 ].min, 0 ].max
    end

    def generate_reasoning
      high_priority = audit.discovered_pages.high_priority.order(priority_score: :desc)

      # Ask AI to synthesize prioritization strategy
      ai_summary = ask_ai_for_strategy_summary(high_priority)

      @reasoning = {
        summary: ai_summary || build_summary(high_priority),
        focus_pages: high_priority.limit(5).map { |p| page_reasoning(p) },
        ai_insights: @reasoning.select { |r| r.is_a?(Hash) && r[:ai_reasoning] }
      }
    end

    def ask_ai_for_strategy_summary(pages)
      return nil if pages.empty?

      page_list = pages.limit(10).map do |p|
        "- #{p.url} (#{p.page_type}, score: #{p.priority_score})"
      end.join("\n")

      system_prompt = <<~PROMPT
        You are a CRO strategist explaining audit priorities to a client.
        Write a 2-3 sentence summary explaining which pages matter most and why.
        Be specific and business-focused. No jargon.
      PROMPT

      user_prompt = <<~PROMPT
        I've identified these high-priority pages for audit:

        #{page_list}

        Explain to the client why we're focusing on these pages first.
      PROMPT

      OpenaiService.chat(
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt }
        ],
        temperature: 0.8,
        max_tokens: 300
      )
    rescue StandardError => e
      Rails.logger.error("AI summary generation failed: #{e.message}")
      nil
    end

    def build_summary(pages)
      return "No high-priority pages identified." if pages.empty?

      types = pages.pluck(:page_type).uniq

      "Based on site structure and conversion potential, #{pages.count} high-impact pages identified. " \
      "Focus areas: #{types.join(', ')}. These pages are most likely to influence visitor decisions."
    end

    def page_reasoning(page)
      reasons = []

      case page.page_type
      when "homepage"
        reasons << "Homepage is the primary entry point and sets first impressions"
      when "pricing"
        reasons << "Pricing page directly influences purchase decisions"
      when "checkout"
        reasons << "Checkout page is the final conversion step"
      when "product"
        reasons << "Product pages drive purchasing decisions"
      when "landing"
        reasons << "Landing page designed for conversion"
      end

      metadata = page.crawl_metadata
      reasons << "Contains #{metadata['form_count']} forms" if metadata["form_count"] > 0
      reasons << "Multiple CTAs detected" if metadata["button_count"] > 3

      {
        url: page.url,
        type: page.page_type,
        score: page.priority_score,
        reasoning: reasons.join(". ")
      }
    end
  end
end
