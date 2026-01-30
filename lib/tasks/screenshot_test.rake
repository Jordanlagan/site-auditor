namespace :screenshot do
  desc "Test screenshot capture functionality"
  task test: :environment do
    require "puppeteer"
    require "fileutils"

    puts "\n🔍 Testing Chrome/Puppeteer Screenshot Capture..."
    puts "=" * 60

    # Check Chrome path
    chrome_path = ENV["CHROME_PATH"] || "/usr/bin/google-chrome"
    puts "Chrome path: #{chrome_path}"
    puts "Chrome exists: #{File.exist?(chrome_path)}"

    # Create test directory
    screenshots_dir = Rails.root.join("public", "screenshots", "test")
    FileUtils.mkdir_p(screenshots_dir)
    filepath = screenshots_dir.join("test_#{Time.current.to_i}.png")

    puts "Output path: #{filepath}"
    puts "\n⏳ Attempting to launch Chrome and capture screenshot..."
    puts "=" * 60

    begin
      launch_options = {
        headless: true,
        timeout: 30000,
        args: [
          "--no-sandbox",
          "--disable-setuid-sandbox",
          "--disable-dev-shm-usage",
          "--disable-gpu",
          "--disable-software-rasterizer",
          "--disable-extensions",
          "--disable-features=IsolateOrigins,site-per-process,Crashpad",
          "--disable-blink-features=AutomationControlled"
        ]
      }
      launch_options[:executable_path] = chrome_path if File.exist?(chrome_path)

      Puppeteer.launch(**launch_options) do |browser|
        puts "✅ Chrome launched successfully!"

        page = browser.new_page
        page.viewport = Puppeteer::Viewport.new(width: 1280, height: 720)

        puts "⏳ Navigating to example.com..."
        page.goto("https://example.com", wait_until: "networkidle2", timeout: 15_000)

        puts "✅ Page loaded!"
        puts "⏳ Taking screenshot..."

        page.screenshot(path: filepath.to_s, full_page: false)

        puts "✅ Screenshot saved!"
        puts "\n" + "=" * 60
        puts "SUCCESS! Screenshot saved to:"
        puts filepath
        puts "File size: #{File.size(filepath)} bytes"
        puts "=" * 60
      end
    rescue StandardError => e
      puts "\n" + "=" * 60
      puts "❌ FAILED!"
      puts "Error: #{e.class}"
      puts "Message: #{e.message}"
      puts "\nFull backtrace:"
      puts e.backtrace.first(10).join("\n")
      puts "=" * 60
      exit 1
    end
  end
end
