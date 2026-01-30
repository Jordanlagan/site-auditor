# frozen_string_literal: true

module AuditWorkflow
  class PageSummarizer
    attr_reader :page, :html_doc, :metrics

    def initialize(page, html_doc, metrics)
      @page = page
      @html_doc = html_doc
      @metrics = metrics
    end

    def generate_summary
      # Extract key visual and structural elements
      context = build_context_for_ai

      # Ask AI for 1-paragraph summary
      ai_summary = ask_ai_for_summary(context)

      return ai_summary if ai_summary

      # Fallback summary
      generate_fallback_summary
    end

    private

    def build_context_for_ai
      {
        url: page.url,
        page_type: page.page_type,
        title: metrics.dig(:technical_metrics, :meta_description) || html_doc.css("title").text,
        word_count: metrics.dig(:content_metrics, :word_count),
        headings: extract_heading_structure,
        primary_ctas: metrics.dig(:ux_metrics, :cta_buttons)&.first(3),
        has_forms: metrics.dig(:technical_metrics, :form_count) > 0,
        has_nav: metrics.dig(:ux_metrics, :has_nav),
        key_sections: identify_key_sections
      }
    end

    def extract_heading_structure
      headings = []
      html_doc.css("h1, h2, h3").first(5).each do |h|
        headings << { level: h.name, text: h.text.strip }
      end
      headings
    end

    def identify_key_sections
      sections = []

      # Look for common section patterns
      html_doc.css('section, div[class*="section"], article').first(3).each do |section|
        heading = section.css("h1, h2, h3").first
        if heading
          sections << {
            heading: heading.text.strip,
            word_count: section.text.split.size
          }
        end
      end

      sections
    end

    def ask_ai_for_summary(context)
      system_prompt = <<~PROMPT
        You are analyzing a webpage. Write a 1-paragraph summary (3-4 sentences) that describes:
        1. What this page is (its purpose)
        2. Key content/sections present
        3. Main call-to-action or goal

        Be factual and descriptive. No marketing fluff.
      PROMPT

      user_prompt = <<~PROMPT
        Page: #{context[:url]}
        Type: #{context[:page_type]}
        Title: #{context[:title]}

        Heading Structure:
        #{context[:headings].map { |h| "#{h[:level].upcase}: #{h[:text]}" }.join("\n")}

        #{context[:has_forms] ? "Contains #{metrics.dig(:technical_metrics, :form_count)} form(s)" : "No forms"}
        #{context[:primary_ctas].any? ? "Primary CTAs: #{context[:primary_ctas].map { |c| c[:text] }.join(", ")}" : ""}

        Key Sections:
        #{context[:key_sections].map { |s| "- #{s[:heading]} (#{s[:word_count]} words)" }.join("\n")}

        Write a 1-paragraph summary of this page.
      PROMPT

      response = OpenaiService.chat(
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt }
        ],
        model: "gpt-4o-mini",
        temperature: 0.3
      )

      response
    rescue StandardError => e
      Rails.logger.error("AI summary generation failed: #{e.message}")
      nil
    end

    def generate_fallback_summary
      type_desc = case page.page_type
      when "homepage" then "main landing page"
      when "product" then "product page"
      when "pricing" then "pricing information page"
      when "contact" then "contact page"
      when "blog" then "blog post or article"
      else "page"
      end

      title = metrics.dig(:technical_metrics, :meta_description) || html_doc.css("title").text || "Untitled"
      word_count = metrics.dig(:content_metrics, :word_count) || 0
      form_count = metrics.dig(:technical_metrics, :form_count) || 0

      summary = "This #{type_desc} (#{title}) contains #{word_count} words"

      if form_count > 0
        summary += " and includes #{form_count} form#{'s' if form_count > 1} for user input"
      end

      ctas = metrics.dig(:ux_metrics, :cta_buttons)
      if ctas && ctas.any?
        summary += ". Primary calls-to-action include: #{ctas.first(3).map { |c| c[:text] }.join(", ")}"
      end

      summary += "."
      summary
    end
  end
end
