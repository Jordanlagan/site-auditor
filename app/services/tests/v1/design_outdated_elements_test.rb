module Tests
  module V1
    class DesignOutdatedElementsTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        analyze_with_ai(
          "Does the site avoid outdated or generic visual elements?",
          {
            screenshots: page_data.screenshots,
            fonts: page_data.fonts&.first(10),
            colors: page_data.colors&.first(10),
            analysis_points: [
              "Does the design feel modern?",
              "Are outdated patterns avoided (e.g., excessive gradients, skeuomorphism)?",
              "Are generic stock photos avoided?",
              "Does it follow current design trends appropriately?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "DesignOutdatedElementsTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze design modernness")
      end

      protected

      def test_category
        "design"
      end
    end
  end
end
