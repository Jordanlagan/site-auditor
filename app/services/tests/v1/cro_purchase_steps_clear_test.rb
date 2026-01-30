module Tests
  module V1
    class CroPurchaseStepsClearTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        analyze_with_ai(
          "Are the steps to purchase described clearly on the page?",
          {
            page_content: page_data.page_content&.first(2000),
            cta_buttons: extract_cta_text,
            analysis_points: [
              "Is the purchase process clear?",
              "Are next steps obvious?",
              "Is there a clear path to conversion?",
              "Are steps numbered or outlined?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "CroPurchaseStepsClearTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze purchase steps")
      end

      protected

      def test_category
        "cro"
      end

      def extract_cta_text
        doc = Nokogiri::HTML(page_data.html_content)
        doc.css('button, a.btn, a[class*="button"]').map { |b| b.text.strip }.first(8)
      end
    end
  end
end
