module Tests
  module V1
    class StructureLogoLinksHomeTest < BaseTest
      def run!
        return not_applicable unless page_data&.html_content.present?

        doc = Nokogiri::HTML(page_data.html_content)
        logo_link = find_logo_link(doc)

        if logo_link && links_to_home?(logo_link)
          create_result(
            status: "passed",
            score: 100,
            summary: "Logo in header links to homepage.",
            details: { logo_href: logo_link["href"] },
            priority: 2
          )
        elsif logo_link
          create_result(
            status: "failed",
            score: 0,
            summary: "Logo found but doesn't link to homepage.",
            details: { logo_href: logo_link["href"] },
            recommendation: "Make the logo clickable and link it to the homepage. This is a standard web convention that users expect.",
            priority: 3
          )
        else
          create_result(
            status: "warning",
            score: 50,
            summary: "Could not definitively identify a logo link in the header.",
            recommendation: "Ensure your logo is prominently placed in the header and links to the homepage.",
            priority: 2
          )
        end
      rescue => e
        Rails.logger.error "StructureLogoLinksHomeTest failed: #{e.message}"
        not_applicable
      end

      protected

      def test_category
        "structure"
      end

      def find_logo_link(doc)
        header = doc.at_css("header") || doc.at_css("nav")
        return nil unless header

        # Look for common logo patterns
        logo_link = header.at_css('a.logo, a[class*="logo"], a img[alt*="logo"], a img[class*="logo"]')

        # If not found, look for the first link in header with an image
        logo_link ||= header.at_css("a img")&.parent

        logo_link
      end

      def links_to_home?(link)
        href = link["href"].to_s.strip
        return true if href == "/" || href == "#/" || href.empty?

        # Normalize URLs by removing trailing slashes and fragments
        href_normalized = href.gsub(/[\/\#]+$/, "")

        # Check if it's the root domain
        begin
          uri = URI.parse(href)
          page_uri = URI.parse(discovered_page.url)

          # Compare hosts (with and without www)
          same_host = uri.host == page_uri.host ||
                     uri.host == "www.#{page_uri.host}" ||
                     page_uri.host == "www.#{uri.host}"

          # Check if path is root (empty, /, or just trailing slash)
          root_path = uri.path.nil? || uri.path.empty? || uri.path == "/" || uri.path.gsub(/\/$/, "").empty?

          same_host && root_path
        rescue => e
          Rails.logger.warn "Failed to parse URLs: #{e.message}"
          false
        end
      end

      def not_applicable
        create_result(
          status: "not_applicable",
          summary: "Could not analyze header structure"
        )
      end
    end
  end
end
