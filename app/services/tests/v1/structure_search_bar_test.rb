module Tests
  module V1
    class StructureSearchBarTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        doc = Nokogiri::HTML(page_data.html_content)
        search_inputs = doc.css('input[type="search"], input[placeholder*="search"], input[name*="search"], input[aria-label*="search"]')

        if search_inputs.any?
          create_result(
            status: "passed",
            score: 100,
            summary: "Search bar found on the page.",
            details: { search_elements_count: search_inputs.count },
            priority: 3
          )
        else
          create_result(
            status: "warning",
            score: 70,
            summary: "No clearly visible search bar detected.",
            details: {},
            recommendation: "Consider adding a search bar to help users find content quickly, especially if your site has many products or pages.",
            priority: 3
          )
        end
      rescue => e
        Rails.logger.error "StructureSearchBarTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze search functionality")
      end

      protected

      def test_category
        "structure"
      end
    end
  end
end
