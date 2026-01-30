module Tests
  module V1
    class NavPrimaryConversionGoalTest < BaseTest
      def run!
        return not_applicable unless has_nav_data?

        prompt = <<~PROMPT
          Analyze if the navigation bar features the company's primary conversion goal prominently.

          Look for:
          - Primary CTA buttons in the nav (e.g., "Buy Now", "Sign Up", "Get Started", "Contact Sales")
          - Prominent placement of conversion-focused links
          - Clear emphasis on the main business goal

          Determine if the navigation effectively guides users toward conversion.
        PROMPT

        data_context = {
          html_snippet: nav_html_snippet,
          links: nav_links,
          page_content: page_data.page_content.first(1000),
          meta_description: page_data.meta_description
        }

        analyze_with_ai(prompt, data_context)
      rescue => e
        Rails.logger.error "NavPrimaryConversionGoalTest failed: #{e.message}"
        not_applicable(summary: "Test could not be completed due to an error")
      end

      protected

      def test_category
        "nav"
      end

      def has_nav_data?
        page_data&.html_content.present?
      end

      def nav_html_snippet
        doc = Nokogiri::HTML(page_data.html_content)
        nav = doc.at_css("nav") || doc.at_css("header")
        nav ? nav.to_html.first(2000) : ""
      end

      def nav_links
        doc = Nokogiri::HTML(page_data.html_content)
        nav = doc.at_css("nav") || doc.at_css("header")
        return [] unless nav

        nav.css("a").map { |a| { text: a.text.strip, href: a["href"] } }.take(20)
      end
    end
  end
end
