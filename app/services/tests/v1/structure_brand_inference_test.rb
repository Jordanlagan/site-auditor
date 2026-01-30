module Tests
  module V1
    class StructureBrandInferenceTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        analyze_with_ai(
          "Can a user quickly infer what the brand sells from above-the-fold content?",
          {
            page_title: page_data.meta_title,
            meta_description: page_data.meta_description,
            h1_headings: page_data.headings&.dig("h1"),
            first_paragraph: page_data.page_content&.first(500),
            analysis_points: [
              "Is the value proposition clear?",
              "Do users immediately understand what's being sold?",
              "Is the headline descriptive?",
              "Are key benefits visible?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "StructureBrandInferenceTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze brand clarity")
      end

      protected

      def test_category
        "structure"
      end
    end
  end
end
