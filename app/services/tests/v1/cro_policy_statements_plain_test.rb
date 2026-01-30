module Tests
  module V1
    class CroPolicyStatementsPlainTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.page_content.present?

        analyze_with_ai(
          "Are policy and guarantee statements written plainly and easy to find?",
          {
            page_content: page_data.page_content&.first(2000),
            links: page_data.links&.select { |l| l["text"]&.downcase&.match?(/policy|return|shipping|term/) }&.first(10),
            analysis_points: [
              "Is policy language simple and clear?",
              "Are policies easy to locate?",
              "Is legal jargon minimized?",
              "Are key points highlighted?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "CroPolicyStatementsPlainTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze policy statements")
      end

      protected

      def test_category
        "cro"
      end
    end
  end
end
