module Tests
  module V1
    class CroCtaAboveFoldTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        doc = Nokogiri::HTML(page_data.html_content)
        # Check first 1000 chars of body as proxy for above-the-fold
        above_fold_html = doc.at_css("body")&.to_html&.first(2000) || ""

        ctas = Nokogiri::HTML(above_fold_html).css('button, a.btn, a[class*="button"], input[type="submit"]')

        if ctas.any?
          create_result(
            status: "passed",
            score: 100,
            summary: "Primary CTA found above the fold.",
            details: { cta_count: ctas.count, cta_text: ctas.map { |c| c.text.strip }.first(5) },
            priority: 2
          )
        else
          create_result(
            status: "failed",
            score: 40,
            summary: "No clear CTA found above the fold.",
            details: {},
            recommendation: "Add a prominent call-to-action button above the fold. Users should know what action to take immediately upon landing.",
            priority: 2
          )
        end
      rescue => e
        Rails.logger.error "CroCtaAboveFoldTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze above-the-fold CTAs")
      end

      protected

      def test_category
        "cro"
      end
    end
  end
end
