module Tests
  module V1
    class CroUspsPresentTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        analyze_with_ai(
          "Do key pages include USPs (Unique Selling Propositions)?",
          {
            page_content: page_data.page_content&.first(2000),
            headings: page_data.headings&.values&.flatten&.first(10),
            analysis_points: [
              "Are unique benefits highlighted?",
              "Is the value proposition clear?",
              "Are differentiators mentioned?",
              "Do USPs stand out visually?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "CroUspsPresentTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze USPs")
      end

      protected

      def test_category
        "cro"
      end
    end
  end
end
