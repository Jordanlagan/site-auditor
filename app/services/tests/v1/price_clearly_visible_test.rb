module Tests
  module V1
    class PriceClearlyVisibleTest < BaseTest
      def run!
        return not_applicable(summary: "No page content available") unless page_data&.page_content.present?

        content = page_data.page_content
        # Look for price patterns
        has_price = content.match?(/\$\d+/) ||
                   content.match?(/£\d+/) ||
                   content.match?(/€\d+/) ||
                   content.downcase.include?("price:") ||
                   content.downcase.include?("cost:")

        if has_price
          create_result(
            status: "passed",
            score: 100,
            summary: "Pricing information appears to be visible on the page.",
            details: {},
            priority: 2
          )
        else
          create_result(
            status: "warning",
            score: 60,
            summary: "No clear pricing detected on this page.",
            details: {},
            recommendation: "If this is a product/service page, make pricing clear and prominent. Hidden pricing creates friction.",
            priority: 2
          )
        end
      rescue => e
        Rails.logger.error "PriceClearlyVisibleTest failed: #{e.message}"
        not_applicable(summary: "Could not check for pricing")
      end

      protected

      def test_category
        "price"
      end
    end
  end
end
