module Tests
  module V1
    class PriceDiscountLabelsTest < BaseTest
      def run!
        return not_applicable(summary: "No page content available") unless page_data&.page_content.present?

        content = page_data.page_content.downcase
        has_discount = content.match?(/save\s+\$?\d+/) ||
                      content.match?(/\d+%\s*off/) ||
                      content.include?("discount") ||
                      content.include?("bundle") && content.include?("save")

        if has_discount
          create_result(
            status: "passed",
            score: 100,
            summary: "Discount or savings labels detected.",
            details: {},
            priority: 3
          )
        else
          create_result(
            status: "warning",
            score: 70,
            summary: "No clear discount/savings labels detected.",
            details: {},
            recommendation: "If offering bundles or promotions, clearly label the savings amount to highlight value.",
            priority: 3
          )
        end
      rescue => e
        Rails.logger.error "PriceDiscountLabelsTest failed: #{e.message}"
        not_applicable(summary: "Could not check for discount labels")
      end

      protected

      def test_category
        "price"
      end
    end
  end
end
