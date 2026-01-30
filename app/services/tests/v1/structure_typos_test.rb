module Tests
  module V1
    class StructureTyposTest < BaseTest
      def run!
        return not_applicable(summary: "No page content available") unless page_data&.page_content.present?

        prompt = <<~PROMPT
          Analyze the visible page content for spelling and grammatical errors.

          Look for:
          - Obvious spelling mistakes
          - Grammatical errors
          - Inconsistent capitalization
          - Missing punctuation in important areas

          Focus on headline text, navigation labels, and prominent content only.
          Don't be overly pedantic - only flag clear errors that would hurt credibility.
        PROMPT

        data_context = {
          page_content: page_data.page_content&.first(3000),
          headings: page_data.headings,
          meta_title: page_data.meta_title,
          meta_description: page_data.meta_description,
          html_snippet: main_content_snippet
        }

        analyze_with_ai(prompt, data_context)
      rescue => e
        Rails.logger.error "StructureTyposTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze content for typos")
      end

      protected

      def test_category
        "structure"
      end

      def main_content_snippet
        doc = Nokogiri::HTML(page_data.html_content)
        main = doc.at_css("main") || doc.at_css("body")
        main ? main.text.strip.first(2000) : ""
      end
    end
  end
end
