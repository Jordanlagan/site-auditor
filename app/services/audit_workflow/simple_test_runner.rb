module AuditWorkflow
  class SimpleTestRunner
    attr_reader :page, :html_doc, :metrics

    def initialize(page, html_doc, metrics)
      @page = page
      @html_doc = html_doc
      @metrics = metrics
    end

    def run_all_tests
      [
        test_has_h1,
        test_single_h1,
        test_has_title,
        test_meta_description_present,
        test_meta_description_length,
        test_images_have_alt_text,
        test_has_favicon,
        test_mobile_viewport,
        test_https_protocol,
        test_no_broken_links_candidate
      ].compact
    end

    private

    def test_has_h1
      h1_count = metrics.dig(:content_metrics, :heading_counts, :h1) || 0
      {
        test: "Has H1 Tag",
        passed: h1_count > 0,
        message: h1_count > 0 ? "Page has #{h1_count} H1 tag(s)" : "No H1 tag found",
        severity: h1_count > 0 ? nil : "high"
      }
    end

    def test_single_h1
      h1_count = metrics.dig(:content_metrics, :heading_counts, :h1) || 0
      {
        test: "Single H1 Tag",
        passed: h1_count == 1,
        message: h1_count == 1 ? "Correct: Single H1 tag" : "Found #{h1_count} H1 tags (should be 1)",
        severity: h1_count == 1 ? nil : "medium"
      }
    end

    def test_has_title
      title = html_doc.at_css("title")&.text
      {
        test: "Has Page Title",
        passed: title.present?,
        message: title.present? ? "Title: #{title.truncate(50)}" : "No title tag found",
        severity: title.present? ? nil : "high"
      }
    end

    def test_meta_description_present
      meta_desc = metrics.dig(:technical_metrics, :meta_description)
      {
        test: "Has Meta Description",
        passed: meta_desc.present?,
        message: meta_desc.present? ? "Meta description present" : "No meta description found",
        severity: meta_desc.present? ? nil : "medium"
      }
    end

    def test_meta_description_length
      length = metrics.dig(:technical_metrics, :meta_description_length) || 0
      optimal = length >= 120 && length <= 160
      {
        test: "Meta Description Length",
        passed: optimal,
        message: "#{length} characters (optimal: 120-160)",
        severity: optimal ? nil : "low"
      }
    end

    def test_images_have_alt_text
      missing = metrics.dig(:asset_metrics, :images_without_alt) || 0
      total = metrics.dig(:asset_metrics, :image_count) || 0
      {
        test: "Images Have Alt Text",
        passed: missing == 0 && total > 0,
        message: missing == 0 ? "All #{total} images have alt text" : "#{missing} of #{total} images missing alt text",
        severity: missing == 0 ? nil : (missing > 5 ? "high" : "medium")
      }
    end

    def test_has_favicon
      has_favicon = metrics.dig(:asset_metrics, :favicon_present)
      {
        test: "Has Favicon",
        passed: has_favicon == true,
        message: has_favicon ? "Favicon present" : "No favicon detected",
        severity: has_favicon ? nil : "low"
      }
    end

    def test_mobile_viewport
      mobile_optimized = metrics.dig(:technical_metrics, :mobile_optimized)
      {
        test: "Mobile Viewport Tag",
        passed: mobile_optimized == true,
        message: mobile_optimized ? "Mobile viewport configured" : "No mobile viewport meta tag",
        severity: mobile_optimized ? nil : "high"
      }
    end

    def test_https_protocol
      is_https = page.url.start_with?("https://")
      {
        test: "HTTPS Protocol",
        passed: is_https,
        message: is_https ? "Site uses HTTPS" : "Site uses HTTP (insecure)",
        severity: is_https ? nil : "high"
      }
    end

    def test_no_broken_links_candidate
      broken_candidates = metrics.dig(:link_metrics, :broken_link_candidates) || 0
      {
        test: "No Broken Link Patterns",
        passed: broken_candidates == 0,
        message: broken_candidates == 0 ? "No broken link patterns detected" : "#{broken_candidates} potential broken links",
        severity: broken_candidates == 0 ? nil : "medium"
      }
    end
  end
end
