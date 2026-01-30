module Tests
  module V1
    class StructureCopyReadableTest < BaseTest
      def run!
        return not_applicable(summary: "No page content available") unless page_data&.page_content.present?

        content = page_data.page_content.first(2000)

        analyze_with_ai(
          "Is the page copy readable and clear for a first-time visitor?",
          {
            content_sample: content,
            headings: page_data.headings&.values&.flatten&.first(10),
            analysis_points: [
              "Can a first-time visitor understand what the site offers?",
              "Is the copy scannable?",
              "Are key points easy to grasp?",
              "Is jargon avoided?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "StructureCopyReadableTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze copy readability")
      end

      protected

      def test_category
        "structure"
      end
    end
  end
end
