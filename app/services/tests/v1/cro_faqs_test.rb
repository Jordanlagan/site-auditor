module Tests
  module V1
    class CroFaqsTest < BaseTest
      def run!
        return not_applicable(summary: "No page content available") unless page_data&.html_content.present?

        doc = Nokogiri::HTML(page_data.html_content)
        content = page_data.page_content&.downcase || ""

        has_faq = doc.css('[class*="faq"], [id*="faq"]').any? ||
                 content.include?("frequently asked questions") ||
                 content.include?("faq") ||
                 page_data.structured_data&.any? { |sd| sd["@type"] == "FAQPage" }

        if has_faq
          create_result(
            status: "passed",
            score: 100,
            summary: "FAQ section found on the site.",
            details: {},
            priority: 3
          )
        else
          create_result(
            status: "warning",
            score: 60,
            summary: "No FAQ section detected.",
            details: {},
            recommendation: "Add an FAQ section to address common customer questions and reduce support burden.",
            priority: 3
          )
        end
      rescue => e
        Rails.logger.error "CroFaqsTest failed: #{e.message}"
        not_applicable(summary: "Could not check for FAQs")
      end

      protected

      def test_category
        "cro"
      end
    end
  end
end
