require "selenium-webdriver"
require "nokogiri"

class InspirationCrawler
  attr_reader :url

  def initialize(url)
    @url = url
  end

  def crawl!
    Rails.logger.info "Crawling inspiration site: #{url}"

    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument("--headless")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--window-size=1920,1080")

    driver = Selenium::WebDriver.for :chrome, options: options

    begin
      driver.navigate.to url
      sleep 2 # Let page load

      result = {
        html: extract_clean_html(driver),
        css: extract_primary_css(driver),
        layout_structure: analyze_layout(driver),
        url: url
      }

      Rails.logger.info "✓ Inspiration site crawled successfully"
      result
    rescue => e
      Rails.logger.error "Failed to crawl inspiration site: #{e.message}"
      {
        html: "",
        css: "",
        layout_structure: {},
        url: url,
        error: e.message
      }
    ensure
      driver.quit if driver
    end
  end

  private

  def extract_clean_html(driver)
    # Use similar cleaning as PageDataCollector
    html = driver.page_source
    doc = Nokogiri::HTML(html)

    # Remove scripts, inline styles, but keep structure
    doc.css("script").remove
    doc.css("style").remove
    doc.css("[style]").each { |el| el.remove_attribute("style") }
    doc.css("noscript").remove

    # Remove SVG content
    doc.css("svg").each { |svg| svg.inner_html = "<!-- svg removed -->" }

    # Remove iframes
    doc.css("iframe").remove

    # Remove base64 images
    doc.css("img[src^='data:']").each { |img| img["src"] = "" }

    # Return full HTML structure (limit to 50k to avoid excessive size)
    doc.to_html[0..50000]
  rescue => e
    Rails.logger.warn "Failed to extract HTML: #{e.message}"
    ""
  end

  def extract_primary_css(driver)
    # Get inline styles from primary CSS files
    css = driver.execute_script(<<~JS)
      const cssRules = [];
      let totalLength = 0;
      const maxLength = 50000; // Limit CSS size

      for (const sheet of document.styleSheets) {
        try {
          // Only process same-origin or public sheets
          const href = sheet.href;
          if (!href || href.includes(window.location.origin)) {
            for (const rule of sheet.cssRules || sheet.rules) {
              if (totalLength < maxLength) {
                const ruleText = rule.cssText;
                cssRules.push(ruleText);
                totalLength += ruleText.length;
              }
            }
          }
        } catch(e) {
          // Cross-origin stylesheets will throw - skip them
        }
      }
      return cssRules.join('\\n');
    JS

    css || ""
  rescue => e
    Rails.logger.warn "Failed to extract CSS: #{e.message}"
    ""
  end

  def analyze_layout(driver)
    # Detect layout patterns
    layout = driver.execute_script(<<~JS)
      const body = document.body;
      const sections = Array.from(document.querySelectorAll('section, div[class*="section"], div[id*="section"], header, footer, main, article'));

      return {
        sections: sections.slice(0, 10).map(s => ({
          type: s.tagName.toLowerCase(),
          classes: s.className,
          height: s.offsetHeight,
          children_count: s.children.length
        })),
        grid_detected: !!body.querySelector('[style*="grid"], [class*="grid"]'),
        flex_detected: !!body.querySelector('[style*="flex"], [class*="flex"]'),
        has_hero: !!body.querySelector('header, [class*="hero"], [id*="hero"]'),
        has_nav: !!body.querySelector('nav, [class*="nav"], [id*="nav"]')
      };
    JS

    layout || {}
  rescue => e
    Rails.logger.warn "Failed to analyze layout: #{e.message}"
    {}
  end
end
