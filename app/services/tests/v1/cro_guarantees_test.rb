module Tests
  module V1
    class CroGuaranteesTest < BaseTest
      def run!
        return not_applicable(summary: "No page content available") unless page_data&.page_content.present?

        content = page_data.page_content.downcase
        has_guarantee = content.include?("guarantee") ||
                       content.include?("money back") ||
                       content.include?("satisfaction") ||
                       content.include?("warranty")

        if has_guarantee
          create_result(
            status: "passed",
            score: 100,
            summary: "Guarantees or warranties mentioned on the page.",
            details: {},
            priority: 3
          )
        else
          create_result(
            status: "warning",
            score: 65,
            summary: "No guarantees or warranties detected.",
            details: {},
            recommendation: "Consider adding guarantees (money-back, satisfaction, etc.) to reduce purchase anxiety and increase trust.",
            priority: 3
          )
        end
      rescue => e
        Rails.logger.error "CroGuaranteesTest failed: #{e.message}"
        not_applicable(summary: "Could not check for guarantees")
      end

      protected

      def test_category
        "cro"
      end
    end
  end
end
