module Tests
  module V1
    class StructureUrlHierarchyTest < BaseTest
      def run!
        url = discovered_page.url
        uri = URI.parse(url)
        path_segments = uri.path.split("/").reject(&:empty?)

        # Homepage/root URL is always good
        if path_segments.empty?
          create_result(
            status: "passed",
            score: 100,
            summary: "Homepage URL structure is clean.",
            details: { path_depth: 0, segments: [], is_homepage: true },
            priority: 3
          )
        elsif path_segments.length <= 3 && path_segments.all? { |seg| seg =~ /^[a-z0-9-]+$/i }
          create_result(
            status: "passed",
            score: 100,
            summary: "URL structure is clean and hierarchical.",
            details: { path_depth: path_segments.length, segments: path_segments },
            priority: 3
          )
        elsif path_segments.length > 5
          create_result(
            status: "failed",
            score: 50,
            summary: "URL is too deep (#{path_segments.length} levels).",
            details: { path_depth: path_segments.length, segments: path_segments },
            recommendation: "Simplify URL structure. Avoid deeply nested paths as they hurt SEO and user experience.",
            priority: 3
          )
        else
          create_result(
            status: "warning",
            score: 75,
            summary: "URL structure is acceptable but could be improved.",
            details: { path_depth: path_segments.length, segments: path_segments },
            recommendation: "Consider shorter, more descriptive URLs with lowercase and hyphens.",
            priority: 3
          )
        end
      rescue => e
        Rails.logger.error "StructureUrlHierarchyTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze URL structure")
      end

      protected

      def test_category
        "structure"
      end
    end
  end
end
