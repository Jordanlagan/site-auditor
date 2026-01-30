module Tests
  module V1
    class StructureContentFlowTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        analyze_with_ai(
          "Is the content optimized to flow well with the layout?",
          {
            page_content: page_data.page_content&.first(3000),
            headings: page_data.headings,
            layout_note: "Analyze content structure, heading hierarchy, paragraph length, and visual flow"
          }
        )
      rescue => e
        Rails.logger.error "StructureContentFlowTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze content flow")
      end

      protected

      def test_category
        "structure"
      end
    end
  end
end
