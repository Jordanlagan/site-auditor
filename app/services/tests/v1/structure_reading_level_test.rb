module Tests
  module V1
    class StructureReadingLevelTest < BaseTest
      def run!
        return not_applicable(summary: "No page content available") unless page_data&.page_content.present?

        content = page_data.page_content.first(2000)

        analyze_with_ai(
          "Is the site content written in customer-friendly language at an appropriate reading level?",
          {
            content_sample: content,
            analysis_points: [
              "Is the language simple and accessible?",
              "Are complex terms explained?",
              "Is sentence structure easy to follow?",
              "Would the average person understand this?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "StructureReadingLevelTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze reading level")
      end

      protected

      def test_category
        "structure"
      end
    end
  end
end
