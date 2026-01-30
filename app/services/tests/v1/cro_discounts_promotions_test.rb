module Tests
  module V1
    class CroDiscountsPromotionsTest < BaseTest
      def run!
        return not_applicable(summary: "No page content available") unless page_data&.page_content.present?

        content = page_data.page_content.downcase
        has_discount = content.match?(/\d+%\s*(off|discount)/) ||
                      content.include?("sale") ||
                      content.include?("promo") ||
                      content.include?("coupon") ||
                      content.include?("special offer")

        if has_discount
          create_result(
            status: "passed",
            score: 100,
            summary: "Discounts or promotions detected on the page.",
            details: {},
            priority: 3
          )
        else
          create_result(
            status: "warning",
            score: 70,
            summary: "No discounts or promotions detected.",
            details: {},
            recommendation: "Consider highlighting current promotions or offering first-time buyer discounts to increase conversions.",
            priority: 3
          )
        end
      rescue => e
        Rails.logger.error "CroDiscountsPromotionsTest failed: #{e.message}"
        not_applicable(summary: "Could not check for discounts")
      end

      protected

      def test_category
        "cro"
      end
    end
  end
end
