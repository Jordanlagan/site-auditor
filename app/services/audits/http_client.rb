require 'net/http'
require 'nokogiri'

module Audits
  class HttpClient
    attr_reader :url, :response, :document, :redirected_url

    def initialize(url)
      @url = url
      @response = nil
      @document = nil
      @redirected_url = url
    end

    def fetch
      uri = URI.parse(url)
      
      # Follow redirects up to 5 times
      5.times do
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 10
        http.read_timeout = 30
        
        request = Net::HTTP::Get.new(uri.request_uri)
        request['User-Agent'] = 'SiteAuditor/1.0 (Internal Tool)'
        
        @response = http.request(request)
        
        if @response.is_a?(Net::HTTPRedirection)
          location = @response['location']
          uri = URI.parse(location)
          @redirected_url = uri.to_s
        else
          break
        end
      end
      
      # Parse HTML if successful
      if @response.is_a?(Net::HTTPSuccess)
        @document = Nokogiri::HTML(@response.body)
      end
      
      self
    rescue StandardError => e
      Rails.logger.error("HTTP fetch error for #{url}: #{e.message}")
      nil
    end

    def success?
      response.is_a?(Net::HTTPSuccess)
    end

    def html
      response&.body
    end

    def headers
      return {} unless response
      
      response.each_header.to_h
    end

    def status_code
      response&.code&.to_i
    end

    def content_type
      response&.content_type
    end

    # Calculate page weight
    def page_weight
      html&.bytesize || 0
    end

    # Get all resource URLs from HTML
    def resource_urls
      return [] unless document
      
      resources = []
      
      # Scripts
      document.css('script[src]').each do |node|
        resources << node['src']
      end
      
      # Stylesheets
      document.css('link[rel="stylesheet"]').each do |node|
        resources << node['href']
      end
      
      # Images
      document.css('img[src]').each do |node|
        resources << node['src']
      end
      
      resources.compact.uniq
    end
  end
end
