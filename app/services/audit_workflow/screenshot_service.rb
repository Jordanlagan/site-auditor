# frozen_string_literal: true

require "puppeteer"
require "fileutils"

module AuditWorkflow
  class ScreenshotService
    attr_reader :page

    def initialize(page)
      @page = page
    end

    def capture_both
      capture_desktop
      capture_mobile
    end

    private

    def capture_desktop
      Rails.logger.info "Attempting desktop screenshot for #{page.url}"
      screenshot_path = capture_screenshot(1920, 1080, "desktop")

      PageScreenshot.create!(
        discovered_page: page,
        device_type: "desktop",
        screenshot_url: screenshot_path,
        viewport_width: 1920,
        viewport_height: 1080,
        metadata: {
          captured_at: Time.current,
          above_fold_height: 900
        }
      )
      Rails.logger.info "Desktop screenshot saved: #{screenshot_path}"
    rescue StandardError => e
      Rails.logger.error("Desktop screenshot failed for #{page.url}: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      create_placeholder_screenshot("desktop", 1920, 1080)
    end

    def capture_mobile
      Rails.logger.info "Attempting mobile screenshot for #{page.url}"
      screenshot_path = capture_screenshot(375, 812, "mobile")

      PageScreenshot.create!(
        discovered_page: page,
        device_type: "mobile",
        screenshot_url: screenshot_path,
        viewport_width: 375,
        viewport_height: 812,
        metadata: {
          captured_at: Time.current,
          above_fold_height: 700
        }
      )
      Rails.logger.info "Mobile screenshot saved: #{screenshot_path}"
    rescue StandardError => e
      Rails.logger.error("Mobile screenshot failed for #{page.url}: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      create_placeholder_screenshot("mobile", 375, 812)
    end

    def capture_screenshot(width, height, device_type)
      # Create screenshots directory if it doesn't exist
      screenshots_dir = Rails.root.join("public", "screenshots")
      FileUtils.mkdir_p(screenshots_dir)

      filename = "#{page.id}_#{device_type}_#{Time.current.to_i}.png"
      filepath = screenshots_dir.join(filename)

      # Configure Chromium/Chrome path - check ENV first, then system paths
      chromium_path = ENV["CHROME_PATH"] || begin
        if File.exist?("/usr/bin/google-chrome")
          "/usr/bin/google-chrome"
        elsif File.exist?("/usr/bin/chromium")
          "/usr/bin/chromium"
        elsif File.exist?("/usr/bin/chromium-browser")
          "/usr/bin/chromium-browser"
        else
          nil # Let puppeteer auto-detect
        end
      end

      launch_options = {
        headless: true,
        args: [
          "--no-sandbox",
          "--disable-setuid-sandbox",
          "--disable-dev-shm-usage",
          "--disable-gpu",
          "--disable-software-rasterizer",
          "--disable-extensions",
          "--disable-background-networking",
          "--disable-default-apps",
          "--disable-sync",
          "--metrics-recording-only",
          "--mute-audio",
          "--no-first-run",
          "--safebrowsing-disable-auto-update",
          "--ignore-certificate-errors",
          "--ignore-ssl-errors",
          "--ignore-certificate-errors-spki-list",
          "--disable-features=VizDisplayCompositor",
          ENV["CHROME_EXTRA_ARGS"]
        ].compact
      }
      launch_options[:executable_path] = chromium_path if chromium_path

      Puppeteer.launch(**launch_options) do |browser|
        browser_page = browser.new_page
        # Set viewport - don't constrain height
        browser_page.viewport = Puppeteer::Viewport.new(width: width, height: 1080)

        # Navigate to page with timeout
        browser_page.goto(page.url, wait_until: "networkidle2", timeout: 30_000)

        # Wait for page to settle
        sleep 2

        # Scroll down and back up multiple times to trigger all lazy loading
        browser_page.evaluate("async () => {
          const distance = 100;
          const delay = 100;

          while (document.scrollingElement.scrollTop + window.innerHeight < document.scrollingElement.scrollHeight) {
            document.scrollingElement.scrollBy(0, distance);
            await new Promise(resolve => setTimeout(resolve, delay));
          }

          // Scroll back to top
          document.scrollingElement.scrollTo(0, 0);
          await new Promise(resolve => setTimeout(resolve, 500));
        }")

        sleep 1

        # Take full page screenshot
        browser_page.screenshot(
          path: filepath.to_s,
          full_page: true
        )
      end

      "/screenshots/#{filename}"
    rescue StandardError => e
      Rails.logger.error("Screenshot capture failed for #{page.url}: #{e.message}")
      raise e
    end

    def create_placeholder_screenshot(device_type, width, height)
      PageScreenshot.create!(
        discovered_page: page,
        device_type: device_type,
        screenshot_url: "/screenshots/placeholder_#{device_type}.png",
        viewport_width: width,
        viewport_height: height,
        metadata: {
          captured_at: Time.current,
          note: "Screenshot capture failed - placeholder used"
        }
      )
    end
  end
end
