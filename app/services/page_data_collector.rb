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

        # Scroll to bottom to trigger lazy-loaded content
        sleep 1 # Initial load
        driver.execute_script("window.scrollTo(0, document.body.scrollHeight)")
        sleep 1 # Wait for lazy content to load
        driver.execute_script("window.scrollTo(0, 0)") # Scroll back to top
        sleep 1 # Let any animations settle

        # Collect all data
        page_data = PageData.find_or_initialize_by(discovered_page: discovered_page)

        page_data.update!(
          # HTML & Content
          html_content: clean_html_content(driver.page_source),
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
      # Wait for body to be present and use innerText for better JS-rendered content
      wait = Selenium::WebDriver::Wait.new(timeout: 5)
      wait.until { driver.find_element(tag_name: "body") }

      # Use JavaScript to get innerText which handles rendered content better
      text = driver.execute_script("return document.body.innerText || document.body.textContent;")
      text&.strip || ""
    rescue => e
      Rails.logger.warn "Failed to extract text content: #{e.message}"
      # Fallback to simple text extraction
      begin
        driver.find_element(tag_name: "body").text
      rescue
        ""
      end
    end

    def extract_visible_html(driver)
      # Get HTML of only visible elements (excludes hidden popups, modals, etc.)
      visible_html = driver.execute_script(<<-JS)
        function getVisibleHTML(element) {
          const computedStyle = window.getComputedStyle(element);
          const isVisible = computedStyle.display !== 'none' &&#{' '}
                           computedStyle.visibility !== 'hidden' &&#{' '}
                           computedStyle.opacity !== '0' &&
                           element.offsetParent !== null;
        #{'  '}
          if (!isVisible) return '';
        #{'  '}
          let html = '<' + element.tagName.toLowerCase();
        #{'  '}
          // Keep important attributes
          const attrs = ['id', 'class', 'href', 'src', 'alt', 'title', 'role', 'aria-label', 'type', 'name'];
          for (const attr of attrs) {
            if (element.hasAttribute(attr)) {
              html += ' ' + attr + '="' + element.getAttribute(attr) + '"';
            }
          }
          html += '>';
        #{'  '}
          // Process children
          if (element.childNodes.length > 0) {
            for (const child of element.childNodes) {
              if (child.nodeType === Node.TEXT_NODE) {
                const text = child.textContent.trim();
                if (text) html += text;
              } else if (child.nodeType === Node.ELEMENT_NODE) {
                html += getVisibleHTML(child);
              }
            }
          }
        #{'  '}
          html += '</' + element.tagName.toLowerCase() + '>';
          return html;
        }

        return getVisibleHTML(document.body);
      JS

      clean_html_content(visible_html || "")
    rescue => e
      Rails.logger.warn "Failed to extract visible HTML: #{e.message}"
      ""
    end

    def clean_html_content(raw_html)
      doc = Nokogiri::HTML(raw_html)

      # Remove CONTENT of script tags but keep external script references
      doc.css("script").each do |script|
        # If it has a src attribute (external script), keep the tag but empty content
        # If it's inline script, remove the entire tag
        if script["src"].nil?
          script.remove # Remove inline scripts entirely
        else
          script.content = "" # Keep external script tags but remove any inline content
        end
      end

      # Remove CONTENT of style tags but keep the tag structure
      doc.css("style").each do |style|
        style.content = "/* styles removed */"
      end

      # Remove inline style attributes (these can be massive)
      doc.css("[style]").each do |el|
        el.remove_attribute("style")
      end

      # Remove noscript tags (not useful for analysis)
      doc.css("noscript").remove

      # Remove SVG content (can be massive paths/data)
      doc.css("svg").each do |svg|
        # Keep the svg tag with attributes but remove inner content
        svg.inner_html = "<!-- svg content removed -->"
      end

      # Remove iframe content (not useful and can contain large data)
      doc.css("iframe").each do |iframe|
        # Keep the tag with src but no content
        iframe.inner_html = ""
      end

      # Remove base64 encoded images (these are huge)
      doc.css("img[src^='data:']").each do |img|
        img["src"] = "data:image/removed"
      end

      # Keep: meta tags, link tags (small and useful for understanding page structure)
      # Keep: All semantic attributes (class, id, data-*, aria-*, role, etc.)

      doc.to_html
    rescue => e
      Rails.logger.warn "Failed to clean HTML: #{e.message}"
      raw_html # Return original if cleaning fails
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

      # Filter out tracking pixels, broken images, and data URIs
      filtered_images = (images || []).select do |img|
        src = img["src"] || img[:src]
        width = img["width"] || img[:width] || 0
        height = img["height"] || img[:height] || 0
        
        # Skip if no src or is data URI
        next false if src.nil? || src.empty? || src.start_with?("data:")
        
        # Skip 1x1 tracking pixels
        next false if width <= 1 || height <= 1
        
        # Skip if naturalWidth/height is 0 (broken/not loaded images)
        next false if width == 0 || height == 0
        
        true
      end

      filtered_images
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
      # Collect all performance-related metrics in one comprehensive object
      metrics = driver.execute_script(<<-JS)
        const navigation = performance.getEntriesByType('navigation')[0];
        const paint = performance.getEntriesByType('paint');
        const resources = performance.getEntriesByType('resource');

        // Calculate total page weight
        const totalWeight = resources.reduce((sum, r) => sum + (r.transferSize || 0), 0);

        // Calculate asset distribution
        const distribution = { images: 0, scripts: 0, css: 0, fonts: 0, other: 0, total: totalWeight };
        resources.forEach(r => {
          const size = r.transferSize || 0;
          if (r.initiatorType === 'img') distribution.images += size;
          else if (r.initiatorType === 'script') distribution.scripts += size;
          else if (r.initiatorType === 'css' || r.initiatorType === 'link') distribution.css += size;
          else if (r.name.match(/\\.(woff2?|ttf|otf|eot)/)) distribution.fonts += size;
          else distribution.other += size;
        });

        // Calculate percentages
        const distributionPercent = {};
        ['images', 'scripts', 'css', 'fonts', 'other'].forEach(type => {
          distributionPercent[type + '_percent'] = totalWeight > 0#{' '}
            ? Math.round((distribution[type] / totalWeight) * 100)#{' '}
            : 0;
        });

        return {
          // Timing metrics
          dom_content_loaded: navigation?.domContentLoadedEventEnd - navigation?.domContentLoadedEventStart,
          load_complete: navigation?.loadEventEnd - navigation?.loadEventStart,
          first_paint: paint.find(p => p.name === 'first-paint')?.startTime,
          first_contentful_paint: paint.find(p => p.name === 'first-contentful-paint')?.startTime,
          ttfb: navigation?.responseStart - navigation?.requestStart,
        #{'  '}
          // Page weight metrics
          total_page_weight_bytes: totalWeight,
          total_page_weight_kb: Math.round(totalWeight / 1024),
          total_page_weight_mb: (totalWeight / (1024 * 1024)).toFixed(2),
        #{'  '}
          // Asset distribution (bytes)
          images_bytes: distribution.images,
          scripts_bytes: distribution.scripts,
          css_bytes: distribution.css,
          fonts_bytes: distribution.fonts,
          other_bytes: distribution.other,
        #{'  '}
          // Asset distribution (percentages)
          ...distributionPercent,
        #{'  '}
          // Resource counts
          total_resources: resources.length,
          image_count: resources.filter(r => r.initiatorType === 'img').length,
          script_count: resources.filter(r => r.initiatorType === 'script').length,
          css_count: resources.filter(r => r.initiatorType === 'css' || r.initiatorType === 'link').length
        };
      JS

      metrics || {}
    rescue => e
      Rails.logger.warn "Failed to collect performance metrics: #{e.message}"
      {}
    end

    def capture_screenshots(driver)
      screenshots = {}

      # Scroll to trigger lazy loading before capturing
      driver.execute_script("window.scrollTo(0, document.body.scrollHeight)")
      sleep 1
      driver.execute_script("window.scrollTo(0, 0)")
      sleep 0.5

      # Desktop screenshot using CDP
      screenshots[:desktop] = capture_full_page_screenshot(driver, "desktop", mobile: false, width: 1920)

      # Mobile screenshot using CDP
      screenshots[:mobile] = capture_full_page_screenshot(driver, "mobile", mobile: true, width: 375)

      screenshots
    rescue => e
      Rails.logger.warn "Failed to capture screenshots: #{e.message}"
      {}
    end

    def capture_full_page_screenshot(driver, device_type, mobile:, width:)
      if mobile
        driver.manage.window.resize_to(375, 812)
      else
        driver.manage.window.resize_to(1920, 1080)
      end

      sleep 0.5

      # Get page dimensions at the CURRENT viewport size (before any resize)
      dimensions = driver.execute_script(<<~JS)
        return {
          width: document.documentElement.scrollWidth,
          height: Math.max(
            document.body.scrollHeight,
            document.documentElement.scrollHeight
          ),
          devicePixelRatio: window.devicePixelRatio || 1
        };
      JS

      page_height = dimensions["height"]
      content_width = width

      # Use CDP to capture full page WITHOUT resizing the viewport
      # This preserves vh units at their original values
      screenshot_data = driver.execute_cdp(
        "Page.captureScreenshot",
        format: "png",
        captureBeyondViewport: true,
        clip: {
          x: 0,
          y: 0,
          width: content_width,
          height: page_height,
          scale: 1
        }
      )

      filename = "#{discovered_page.id}_#{device_type}_#{Time.current.to_i}.png"
      filepath = Rails.root.join("public", "screenshots", filename)

      FileUtils.mkdir_p(File.dirname(filepath))
      File.open(filepath, "wb") do |f|
        f.write(Base64.decode64(screenshot_data["data"]))
      end

      "/screenshots/#{filename}"
    rescue => e
      Rails.logger.warn "CDP screenshot failed for #{device_type}: #{e.message}, falling back to standard method"
      # Fallback: standard screenshot but clamp vh elements first
      fallback_standard_screenshot(driver, device_type, width, page_height)
    end

    def fallback_standard_screenshot(driver, device_type, width, page_height)
      # Clamp vh-based elements BEFORE resizing
      driver.execute_script(<<~JS)
        document.querySelectorAll('*').forEach(el => {
          const h = window.getComputedStyle(el).height;
          if (el.offsetHeight >= window.innerHeight * 0.9) {
            el.style.maxHeight = el.offsetHeight + 'px';
          }
        });
      JS

      driver.manage.window.resize_to(width, page_height)
      sleep 0.5

      filename = "#{discovered_page.id}_#{device_type}_#{Time.current.to_i}.png"
      filepath = Rails.root.join("public", "screenshots", filename)
      FileUtils.mkdir_p(File.dirname(filepath))
      driver.save_screenshot(filepath)

      "/screenshots/#{filename}"
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
