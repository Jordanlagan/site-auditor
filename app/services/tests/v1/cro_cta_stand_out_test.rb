module Tests
  module V1
    class CroCtaStandOutTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        doc = Nokogiri::HTML(page_data.html_content)
        ctas = doc.css('button, a.btn, a[class*="button"], input[type="submit"]')

        analyze_with_ai(
          "Do CTAs stand out visually and appear frequently throughout the page?",
          {
            cta_count: ctas.count,
            cta_text: ctas.map { |c| c.text.strip }.first(10),
            colors: page_data.colors&.first(10),
            analysis_points: [
              "Do CTAs use contrasting colors?",
              "Are there multiple CTAs throughout the page?",
              "Do they use action-oriented text?",
              "Are they visually prominent?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "CroCtaStandOutTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze CTA prominence")
      end

      protected

      def test_category
        "cro"
      end
    end
  end
end
