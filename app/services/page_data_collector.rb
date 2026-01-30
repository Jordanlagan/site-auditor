require "selenium-webdriver"
require "nokogiri"

class PageDataCollector
  attr_reader :url, :discovered_page

    def initialize(discovered_page)
      @discovered_page = discovered_page
      @url = discovered_page.url
    end

    def collect!
      Rails.logger.info "Collecting comprehensive data for: #{url}"

      discovered_page.update(data_collection_status: "collecting")

      # Setup Selenium
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument("--headless")
      options.add_argument("--no-sandbox")
      options.add_argument("--disable-dev-shm-usage")
      options.add_argument("--disable-gpu")
      options.add_argument("--window-size=1920,1080")

      driver = Selenium::WebDriver.for :chrome, options: options

      begin
        driver.navigate.to url
        sleep 2 # Wait for page load

        # Collect all data
        page_data = PageData.find_or_initialize_by(discovered_page: discovered_page)

        page_data.update!(
          # HTML & Content
          html_content: driver.page_source,
          page_content: extract_text_content(driver),

          # Assets
          fonts: collect_fonts(driver),
          colors: collect_colors(driver),
          images: collect_images(driver),
          scripts: collect_scripts(driver),
          stylesheets: collect_stylesheets(driver),

          # SEO
          headings: collect_headings(driver),
          links: collect_links(driver),
          meta_title: driver.title,
          meta_description: get_meta_tag(driver, "description"),
          meta_tags: collect_meta_tags(driver),
          structured_data: collect_structured_data(driver),

          # Performance
          total_page_weight_bytes: calculate_page_weight(driver),
          asset_distribution: calculate_asset_distribution(driver),
          performance_metrics: collect_performance_metrics(driver),

          # Screenshots
          screenshots: capture_screenshots(driver),

          # Metadata
          metadata: {
            viewport: get_viewport(driver),
            lang: get_lang(driver),
            charset: get_charset(driver),
            collected_at: Time.current
          }
        )

        discovered_page.update(data_collection_status: "complete")
        Rails.logger.info "✓ Data collection complete for: #{url}"

        page_data
      rescue => e
        Rails.logger.error "✗ Data collection failed for #{url}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        discovered_page.update(data_collection_status: "failed")
        raise
      ensure
        driver.quit if driver
      end
    end

    private

    def extract_text_content(driver)
      driver.find_element(tag_name: "body").text
    rescue => e
      Rails.logger.warn "Failed to extract text content: #{e.message}"
      ""
    end

    def collect_fonts(driver)
      fonts = []
      doc = Nokogiri::HTML(driver.page_source)

      # From link tags
      doc.css('link[rel="stylesheet"]').each do |link|
        href = link["href"]
        if href && href.include?("fonts.googleapis.com")
          fonts << { source: "google_fonts", href: href }
        end
      end

      # From @font-face rules (requires JavaScript execution)
      font_faces = driver.execute_script(<<-JS)
        const fonts = [];
        for (const sheet of document.styleSheets) {
          try {
            for (const rule of sheet.cssRules || sheet.rules) {
              if (rule instanceof CSSFontFaceRule) {
                fonts.push({
                  family: rule.style.fontFamily,
                  src: rule.style.src,
                  weight: rule.style.fontWeight,
                  style: rule.style.fontStyle
                });
              }
            }
          } catch(e) {}
        }
        return fonts;
      JS

      fonts.concat(font_faces || [])
    rescue => e
      Rails.logger.warn "Failed to collect fonts: #{e.message}"
      []
    end

    def collect_colors(driver)
      # Get all colors used on the page
      colors = driver.execute_script(<<-JS)
        const colors = new Map();
        const elements = document.querySelectorAll('*');

        elements.forEach(el => {
          const styles = window.getComputedStyle(el);
          ['color', 'backgroundColor', 'borderColor'].forEach(prop => {
            const val = styles[prop];
            if (val && val !== 'rgba(0, 0, 0, 0)' && val !== 'transparent') {
              colors.set(val, (colors.get(val) || 0) + 1);
            }
          });
        });

        return Array.from(colors.entries()).map(([color, count]) => ({
          color: color,
          usage_count: count
        })).sort((a, b) => b.usage_count - a.usage_count).slice(0, 20);
      JS

      colors || []
    rescue => e
      Rails.logger.warn "Failed to collect colors: #{e.message}"
      []
    end

    def collect_images(driver)
      images = driver.execute_script(<<-JS)
        return Array.from(document.querySelectorAll('img')).map(img => ({
          src: img.src,
          alt: img.alt,
          width: img.naturalWidth,
          height: img.naturalHeight,
          loading: img.loading,
          srcset: img.srcset
        }));
      JS

      images || []
    rescue => e
      Rails.logger.warn "Failed to collect images: #{e.message}"
      []
    end

    def collect_scripts(driver)
      scripts = driver.execute_script(<<-JS)
        return Array.from(document.querySelectorAll('script')).map(script => ({
          src: script.src,
          type: script.type,
          async: script.async,
          defer: script.defer,
          inline: !script.src && script.textContent.length > 0
        }));
      JS

      scripts || []
    rescue => e
      Rails.logger.warn "Failed to collect scripts: #{e.message}"
      []
    end

    def collect_stylesheets(driver)
      stylesheets = driver.execute_script(<<-JS)
        return Array.from(document.querySelectorAll('link[rel="stylesheet"]')).map(link => ({
          href: link.href,
          media: link.media
        }));
      JS

      stylesheets || []
    rescue => e
      Rails.logger.warn "Failed to collect stylesheets: #{e.message}"
      []
    end

    def collect_headings(driver)
      {
        h1: driver.find_elements(tag_name: "h1").map(&:text),
        h2: driver.find_elements(tag_name: "h2").map(&:text),
        h3: driver.find_elements(tag_name: "h3").map(&:text),
        h4: driver.find_elements(tag_name: "h4").map(&:text),
        h5: driver.find_elements(tag_name: "h5").map(&:text),
        h6: driver.find_elements(tag_name: "h6").map(&:text)
      }
    rescue => e
      Rails.logger.warn "Failed to collect headings: #{e.message}"
      { h1: [], h2: [], h3: [], h4: [], h5: [], h6: [] }
    end

    def collect_links(driver)
      links = driver.execute_script(<<-JS)
        return Array.from(document.querySelectorAll('a')).map(a => ({
          href: a.href,
          text: a.textContent.trim(),
          rel: a.rel,
          target: a.target
        }));
      JS

      links || []
    rescue => e
      Rails.logger.warn "Failed to collect links: #{e.message}"
      []
    end

    def get_meta_tag(driver, name)
      driver.execute_script("return document.querySelector('meta[name=\"#{name}\"]')?.content")
    rescue
      nil
    end

    def collect_meta_tags(driver)
      meta_tags = driver.execute_script(<<-JS)
        const tags = {};
        document.querySelectorAll('meta').forEach(meta => {
          const name = meta.name || meta.property;
          if (name) tags[name] = meta.content;
        });
        return tags;
      JS

      meta_tags || {}
    rescue => e
      Rails.logger.warn "Failed to collect meta tags: #{e.message}"
      {}
    end

    def collect_structured_data(driver)
      structured_data = driver.execute_script(<<-JS)
        const data = [];
        document.querySelectorAll('script[type="application/ld+json"]').forEach(script => {
          try {
            data.push(JSON.parse(script.textContent));
          } catch(e) {}
        });
        return data;
      JS

      structured_data || []
    rescue => e
      Rails.logger.warn "Failed to collect structured data: #{e.message}"
      []
    end

    def calculate_page_weight(driver)
      # Get resource sizes via Performance API
      weight = driver.execute_script(<<-JS)
        const resources = performance.getEntriesByType('resource');
        return resources.reduce((sum, r) => sum + (r.transferSize || 0), 0);
      JS

      weight || 0
    rescue => e
      Rails.logger.warn "Failed to calculate page weight: #{e.message}"
      0
    end

    def calculate_asset_distribution(driver)
      distribution = driver.execute_script(<<-JS)
        const resources = performance.getEntriesByType('resource');
        const dist = { images: 0, scripts: 0, css: 0, fonts: 0, other: 0 };

        resources.forEach(r => {
          const size = r.transferSize || 0;
          if (r.initiatorType === 'img') dist.images += size;
          else if (r.initiatorType === 'script') dist.scripts += size;
          else if (r.initiatorType === 'css' || r.initiatorType === 'link') dist.css += size;
          else if (r.name.match(/\.(woff2?|ttf|otf|eot)/)) dist.fonts += size;
          else dist.other += size;
        });

        return dist;
      JS

      distribution || {}
    rescue => e
      Rails.logger.warn "Failed to calculate asset distribution: #{e.message}"
      {}
    end

    def collect_performance_metrics(driver)
      metrics = driver.execute_script(<<-JS)
        const navigation = performance.getEntriesByType('navigation')[0];
        const paint = performance.getEntriesByType('paint');

        return {
          dom_content_loaded: navigation?.domContentLoadedEventEnd - navigation?.domContentLoadedEventStart,
          load_complete: navigation?.loadEventEnd - navigation?.loadEventStart,
          first_paint: paint.find(p => p.name === 'first-paint')?.startTime,
          first_contentful_paint: paint.find(p => p.name === 'first-contentful-paint')?.startTime,
          ttfb: navigation?.responseStart - navigation?.requestStart
        };
      JS

      metrics || {}
    rescue => e
      Rails.logger.warn "Failed to collect performance metrics: #{e.message}"
      {}
    end

    def capture_screenshots(driver)
      screenshots = {}

      # Desktop screenshot
      driver.manage.window.resize_to(1920, 1080)
      sleep 1
      screenshots[:desktop] = save_screenshot(driver, "desktop")

      # Mobile screenshot
      driver.manage.window.resize_to(375, 667)
      sleep 1
      screenshots[:mobile] = save_screenshot(driver, "mobile")

      screenshots
    rescue => e
      Rails.logger.warn "Failed to capture screenshots: #{e.message}"
      {}
    end

    def save_screenshot(driver, device_type)
      filename = "#{discovered_page.id}_#{device_type}_#{Time.current.to_i}.png"
      filepath = Rails.root.join("public", "screenshots", filename)

      FileUtils.mkdir_p(File.dirname(filepath))
      driver.save_screenshot(filepath)

      "/screenshots/#{filename}"
    rescue => e
      Rails.logger.warn "Failed to save screenshot: #{e.message}"
      nil
    end

    def get_viewport(driver)
      driver.execute_script("return { width: window.innerWidth, height: window.innerHeight }")
    rescue
      {}
    end

    def get_lang(driver)
      driver.execute_script("return document.documentElement.lang")
    rescue
      nil
    end

    def get_charset(driver)
      driver.execute_script("return document.characterSet")
    rescue
      nil
    end
end
