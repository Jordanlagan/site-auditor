module Tests
  module V1
    class CroPrimaryCtaObviousTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        analyze_with_ai(
          "Is the primary CTA obvious within 5 seconds of landing on the page?",
          {
            page_content: page_data.page_content&.first(1500),
            buttons_and_links: extract_cta_elements,
            colors: page_data.colors&.first(10),
            analysis_points: [
              "Is there a prominent button/CTA?",
              "Does it stand out visually?",
              "Is it above the fold?",
              "Is the action clear?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "CroPrimaryCtaObviousTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze CTA visibility")
      end

      protected

      def test_category
        "cro"
      end

      def extract_cta_elements
        doc = Nokogiri::HTML(page_data.html_content)
        buttons = doc.css('button, a.btn, a[class*="button"], input[type="submit"]')
        buttons.first(10).map { |b| b.text.strip }.reject(&:empty?)
      end
    end
  end
end
