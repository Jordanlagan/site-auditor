module Tests
  module V1
    class CroAboveFoldElementsTest < BaseTest
      def run!
        return not_applicable unless page_data&.html_content.present?

        prompt = <<~PROMPT
          Analyze if the above-the-fold section contains all necessary conversion elements.

          Check for presence of:
          1. Compelling headline (clear value proposition)
          2. Hero image or visual element
          3. Primary CTA (call-to-action button)
          4. Key USPs (unique selling points) or benefits
          5. Social proof (reviews, testimonials, trust badges, customer logos)
          6. Any guarantees (money-back, free trial, etc.)

          Rate how complete and effective the above-the-fold section is for conversion.
        PROMPT

        data_context = {
          html_content: above_fold_html,
          headings: page_data.headings,
          images: page_data.images.take(5),
          meta_title: page_data.meta_title,
          meta_description: page_data.meta_description,
          page_content_sample: page_data.page_content&.first(1500)
        }

        analyze_with_ai(prompt, data_context)
      rescue => e
        Rails.logger.error "CroAboveFoldElementsTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze above-the-fold content")
      end

      protected

      def test_category
        "cro"
      end

      def above_fold_html
        # Get first ~1500 characters of body HTML as approximation
        doc = Nokogiri::HTML(page_data.html_content)
        body = doc.at_css("body")
        body ? body.to_html.first(2000) : ""
      end
    end
  end
end
