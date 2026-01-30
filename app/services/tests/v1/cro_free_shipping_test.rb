module Tests
  module V1
    class CroFreeShippingTest < BaseTest
      def run!
        return not_applicable(summary: "No page content available") unless page_data&.page_content.present?

        content = page_data.page_content.downcase
        has_free_shipping = content.include?("free shipping") ||
                           content.include?("free delivery") ||
                           content.include?("shipping free")

        if has_free_shipping
          create_result(
            status: "passed",
            score: 100,
            summary: "Free shipping offer detected on the page.",
            details: {},
            priority: 3
          )
        else
          create_result(
            status: "warning",
            score: 60,
            summary: "No free shipping offer detected.",
            details: {},
            recommendation: "Consider offering free shipping or highlighting it prominently if you already do. Free shipping is a major conversion driver.",
            priority: 3
          )
        end
      rescue => e
        Rails.logger.error "CroFreeShippingTest failed: #{e.message}"
        not_applicable(summary: "Could not check for free shipping")
      end

      protected

      def test_category
        "cro"
      end
    end
  end
end
