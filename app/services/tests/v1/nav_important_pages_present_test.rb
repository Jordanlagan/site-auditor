module Tests
  module V1
    class NavImportantPagesPresentTest < BaseTest
      IMPORTANT_PAGES = [ "about", "contact", "products", "services", "pricing", "shop", "store" ]

      def run!
        return not_applicable(summary: "No navigation data available") unless page_data&.html_content.present?

        nav_links = extract_nav_links
        found_pages = IMPORTANT_PAGES.select { |page| has_page_link?(nav_links, page) }

        analyze_with_ai(
          "Are all important pages present in the navigation menu?",
          {
            nav_links: nav_links.map { |l| "#{l[:text]} (#{l[:href]})" }.join("\n"),
            important_pages: IMPORTANT_PAGES,
            found_pages: found_pages,
            missing_pages: IMPORTANT_PAGES - found_pages
          }
        )
      rescue => e
        Rails.logger.error "NavImportantPagesPresentTest failed: #{e.message}"
        not_applicable(summary: "Test could not be completed")
      end

      protected

      def test_category
        "nav"
      end

      def extract_nav_links
        doc = Nokogiri::HTML(page_data.html_content)
        nav = doc.at_css("nav") || doc.at_css("header nav") || doc.at_css("header")
        return [] unless nav

        nav.css("a").map do |link|
          { text: link.text.strip, href: link["href"] }
        end.reject { |l| l[:text].empty? }
      end

      def has_page_link?(links, page_name)
        links.any? do |link|
          link[:text].downcase.include?(page_name) ||
          link[:href].to_s.downcase.include?(page_name)
        end
      end
    end
  end
end
