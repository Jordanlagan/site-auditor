module Tests
  module V1
    class DesignTapTargetSizeTest < BaseTest
      MIN_TAP_SIZE = 44 # pixels

      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        analyze_with_ai(
          "Do interactive elements meet minimum tap target size (≥44×44px) for mobile usability?",
          {
            mobile_screenshot: page_data.screenshots&.dig("mobile"),
            analysis_note: "Check buttons, links, form inputs for adequate tap target size (minimum 44×44px per accessibility guidelines)",
            page_url: discovered_page.url
          }
        )
      rescue => e
        Rails.logger.error "DesignTapTargetSizeTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze tap target sizes")
      end

      protected

      def test_category
        "design"
      end
    end
  end
end
