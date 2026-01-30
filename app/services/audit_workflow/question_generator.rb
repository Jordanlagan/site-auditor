# frozen_string_literal: true

module AuditWorkflow
  class QuestionGenerator
    attr_reader :audit

    def initialize(audit)
      @audit = audit
    end

    def create_contextual_questions
      audit.discovered_pages.high_priority.each do |page|
        generate_page_questions(page)
      end
    end

    private

    def generate_page_questions(page)
      # Use AI to generate smart, contextual questions
      ai_questions = ask_ai_for_questions(page)

      if ai_questions && ai_questions.any?
        ai_questions.each do |q|
          create_question(
            page: page,
            type: q["type"],
            text: q["question"],
            options: q["options"]
          )
        end
      else
        # Fallback to static questions
        generate_static_questions(page)
      end
    end

    def ask_ai_for_questions(page)
      metadata = page.crawl_metadata

      system_prompt = <<~PROMPT
        You are a CRO expert auditing a website. Generate 2-3 smart questions to ask the site owner
        that will help you understand conversion optimization opportunities.

        Questions should be:
        - Specific to the page type and context
        - Focused on conversion elements (CTAs, goals, friction points)
        - Answerable by someone who knows their business

        Respond with JSON array:
        [
          {
            "type": "cta_identification",
            "question": "Which button should visitors click first?",
            "options": ["Get Started", "Learn More", "Contact Us", "Other"]
          }
        ]

        Question types: cta_identification, page_purpose, competing_actions, target_audience, conversion_goal, clarity_check
      PROMPT

      user_prompt = <<~PROMPT
        Generate questions for this page:

        URL: #{page.url}
        Page Type: #{page.page_type}
        Title: #{metadata['title']}
        Has Forms: #{metadata['form_count'] > 0}
        Button Count: #{metadata['button_count']}
        Word Count: #{metadata['word_count']}

        What should I ask the site owner to better understand this page's conversion strategy?
      PROMPT

      result = OpenaiService.analyze_with_json(
        system_prompt: system_prompt,
        user_prompt: user_prompt
      )

      result["questions"] if result
    rescue StandardError => e
      Rails.logger.error("AI question generation failed for #{page.url}: #{e.message}")
      nil
    end

    def generate_static_questions(page)
      metadata = page.crawl_metadata

      # Fallback static questions
      create_question(
        page: page,
        type: "cta_identification",
        text: "On #{page.page_type} (#{truncate_url(page.url)}), which element is the primary call-to-action?",
        options: generate_cta_options(metadata)
      )

      if ambiguous_purpose?(page)
        create_question(
          page: page,
          type: "page_purpose",
          text: "What is the primary purpose of this page?",
          options: [ "Sell product", "Capture leads", "Educate visitors", "Provide support", "Other" ]
        )
      end
    end

    def create_question(page:, type:, text:, options:)
      AuditQuestion.create!(
        audit: audit,
        discovered_page: page,
        question_type: type,
        question_text: text,
        options: options ? { choices: options } : nil
      )
    end

    def generate_cta_options(metadata)
      options = [ "Enter CSS selector manually" ]

      if metadata["button_count"] > 0
        options << "Primary button (largest/most prominent)"
        options << "Form submit button"
      end

      options << "Text link"
      options << "No clear CTA"

      options
    end

    def ambiguous_purpose?(page)
      page.page_type == "other" ||
      (page.page_type == "product" && page.crawl_metadata["form_count"] == 0)
    end

    def truncate_url(url)
      path = URI.parse(url).path
      path.length > 40 ? "#{path[0..37]}..." : path
    end
  end
end
