module Tests
  module V1
    class PriceValueMessagingTest < BaseTest
      def run!
        return not_applicable(summary: "No page content available") unless page_data&.page_content.present?

        analyze_with_ai(
          "Is there clear value messaging to justify the price?",
          {
            page_content: page_data.page_content&.first(2000),
            headings: page_data.headings&.values&.flatten&.first(10),
            analysis_points: [
              "Are benefits clearly articulated?",
              "Is value proposition strong?",
              "Are features that justify price highlighted?",
              "Is ROI or value communicated?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "PriceValueMessagingTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze value messaging")
      end

      protected

      def test_category
        "price"
      end
    end
  end
end
