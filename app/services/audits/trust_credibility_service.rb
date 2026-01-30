module Audits
  class TrustCredibilityService < BaseService
    def category
      'trust_credibility'
    end

    def perform
      client = HttpClient.new(url).fetch
      return unless client&.success?

      check_contact_information(client)
      check_social_proof(client)
      check_return_policy(client)
      check_trust_badges(client)
      check_about_page(client)
      check_privacy_policy(client)
      check_business_information(client)
      check_professional_email(client)
      
      {
        score: calculate_score,
        raw_data: {
          has_contact_page: has_contact_page?,
          has_phone: has_phone_number?(client),
          has_email: has_business_email?(client),
          has_reviews: has_reviews?(client),
          has_return_policy: has_return_policy?,
          has_about_page: has_about_page?
        }
      }
    end

    private

    def check_contact_information(client)
      return unless client.document
      
      # Check for contact page
      has_contact = has_contact_page?
      
      unless has_contact
        add_issue(
          severity: 'high',
          title: 'No Contact Page Found',
          description: 'Visitors have no clear way to reach you. This significantly reduces trust and can prevent sales.',
          recommendation: 'Create a dedicated /contact page with multiple contact methods (phone, email, chat). 47% of users will leave a site if they cannot easily find contact information.'
        )
      end
      
      # Check for visible phone number
      phone_found = has_phone_number?(client)
      
      unless phone_found
        add_issue(
          severity: 'high',
          title: 'No Phone Number Visible',
          description: 'Lack of phone number reduces credibility, especially for high-ticket items.',
          recommendation: 'Display phone number in header/footer. B2B buyers and high-value purchases often need phone support. Consider click-to-call on mobile.'
        )
      end
      
      # Check for business email (not generic)
      unless has_business_email?(client)
        add_issue(
          severity: 'medium',
          title: 'No Professional Email Address Displayed',
          description: 'Generic contact forms without visible email addresses reduce trust.',
          recommendation: 'Display a professional email (e.g., info@yourdomain.com) in footer. Avoid generic Gmail/Yahoo addresses.'
        )
      end
    end

    def check_social_proof(client)
      return unless client.document
      
      # Check for reviews/testimonials
      has_reviews = has_reviews?(client)
      
      unless has_reviews
        add_issue(
          severity: 'high',
          title: 'No Customer Reviews or Testimonials',
          description: 'Missing social proof is a major conversion killer. 93% of consumers read online reviews before buying.',
          recommendation: 'Add customer testimonials with photos, video testimonials, or integrate third-party review platforms (Trustpilot, Google Reviews, Yelp). Place prominently on homepage and product pages.'
        )
      end
      
      # Check for social media links
      social_links = count_social_media_links(client)
      
      if social_links == 0
        add_issue(
          severity: 'medium',
          title: 'No Social Media Links Found',
          description: 'Missing social media links reduce credibility and limit customer engagement channels.',
          recommendation: 'Add social media icons in footer linking to active profiles (Instagram, Facebook, LinkedIn). Display follower counts if substantial.'
        )
      end
      
      # Check for "As Featured In" or press mentions
      html = client.html.downcase
      has_press = html.include?('featured') || html.include?('as seen') || html.include?('press')
      
      unless has_press
        add_issue(
          severity: 'low',
          title: 'No Press Mentions or Brand Logos',
          description: 'Brand trust indicators like "As Featured In" or client logos boost credibility.',
          recommendation: 'If you have press coverage or notable clients, create an "As Featured In" section with media logos or a client logo carousel.'
        )
      end
    end

    def check_return_policy(client)
      has_policy = has_return_policy?
      
      unless has_policy
        add_issue(
          severity: 'high',
          title: 'No Return/Refund Policy Found',
          description: 'Missing return policy is a major purchase blocker. 67% of shoppers check return policy before buying.',
          recommendation: 'Create clear /returns or /refund-policy page. Highlight money-back guarantee if offered. Link prominently in footer and near "Add to Cart" buttons.'
        )
      end
    end

    def check_trust_badges(client)
      return unless client.document
      
      html = client.html.downcase
      
      # Check for security badges
      has_security_badge = html.include?('ssl') || html.include?('secure') || 
                          html.include?('verified') || html.include?('mcafee') ||
                          html.include?('norton') || html.include?('trustwave')
      
      unless has_security_badge
        add_issue(
          severity: 'medium',
          title: 'No Security or Trust Badges Visible',
          description: 'Trust badges near checkout increase conversion by up to 32%.',
          recommendation: 'Add security badges (SSL, payment processor logos) near checkout and payment forms. Display "Secure Checkout" or "256-bit Encryption" messaging.'
        )
      end
      
      # Check for payment method logos
      has_payment_logos = html.include?('visa') || html.include?('mastercard') || 
                         html.include?('paypal') || html.include?('amex') ||
                         html.include?('payment')
      
      unless has_payment_logos
        add_issue(
          severity: 'low',
          title: 'Payment Method Logos Not Displayed',
          description: 'Showing accepted payment methods builds trust and sets expectations.',
          recommendation: 'Display payment method logos (Visa, Mastercard, PayPal, etc.) in footer and near checkout.'
        )
      end
    end

    def check_about_page(client)
      unless has_about_page?
        add_issue(
          severity: 'medium',
          title: 'No About Page Found',
          description: 'About page is critical for building trust and connecting with your audience.',
          recommendation: 'Create /about page telling your brand story, mission, team photos, and founding story. Include founder photo/bio for personal connection.'
        )
      end
    end

    def check_privacy_policy(client)
      uri = URI.parse(url)
      privacy_url = "#{uri.scheme}://#{uri.host}/privacy"
      
      begin
        response = Net::HTTP.get_response(URI.parse(privacy_url))
        unless response.is_a?(Net::HTTPSuccess)
          # Try alternative URLs
          alt_urls = ['/privacy-policy', '/privacy.html', '/legal/privacy']
          found = alt_urls.any? do |path|
            check_url = "#{uri.scheme}://#{uri.host}#{path}"
            resp = Net::HTTP.get_response(URI.parse(check_url))
            resp.is_a?(Net::HTTPSuccess)
          end
          
          unless found
            add_issue(
              severity: 'medium',
              title: 'No Privacy Policy Found',
              description: 'Privacy policy is legally required in many jurisdictions (GDPR, CCPA) and builds trust.',
              recommendation: 'Create privacy policy page and link in footer. Use a privacy policy generator if needed. Required for EU visitors under GDPR.'
            )
          end
        end
      rescue StandardError
        # Ignore network errors
      end
    end

    def check_business_information(client)
      return unless client.document
      
      html = client.html.downcase
      
      # Check for business address
      has_address = html.match?(/\d+\s+[\w\s]+(?:street|st|avenue|ave|road|rd|drive|dr|lane|ln|boulevard|blvd)/i)
      
      unless has_address
        add_issue(
          severity: 'low',
          title: 'No Physical Address Displayed',
          description: 'Displaying a physical address increases legitimacy, especially for local businesses.',
          recommendation: 'Add business address in footer. Required for Google Business Profile and local SEO. Increases trust for brick-and-mortar and service businesses.'
        )
      end
      
      # Check for business hours
      has_hours = html.include?('hours') || html.include?('open') || html.include?('closed')
      
      if !has_hours && html.include?('store')
        add_issue(
          severity: 'low',
          title: 'No Business Hours Listed',
          description: 'For physical locations or businesses with limited availability, hours should be clear.',
          recommendation: 'Display business hours on contact page and footer if applicable.'
        )
      end
    end

    def check_professional_email(client)
      return unless client.document
      
      html = client.html.downcase
      
      # Check for unprofessional email addresses
      has_generic_email = html.include?('@gmail.com') || html.include?('@yahoo.com') || 
                         html.include?('@hotmail.com') || html.include?('@aol.com')
      
      if has_generic_email
        add_issue(
          severity: 'medium',
          title: 'Using Free Email Provider (Gmail, Yahoo)',
          description: 'Generic free email addresses reduce professionalism and brand trust.',
          recommendation: 'Use professional email with your domain (e.g., contact@yourdomain.com). Costs $5-10/month via Google Workspace or Microsoft 365.'
        )
      end
    end

    # Helper methods
    def has_contact_page?
      uri = URI.parse(url)
      contact_paths = ['/contact', '/contact-us', '/contact.html', '/get-in-touch']
      
      contact_paths.any? do |path|
        check_url = "#{uri.scheme}://#{uri.host}#{path}"
        begin
          response = Net::HTTP.get_response(URI.parse(check_url))
          response.is_a?(Net::HTTPSuccess)
        rescue StandardError
          false
        end
      end
    end

    def has_phone_number?(client)
      return false unless client.document
      html = client.html
      # Match phone patterns: (xxx) xxx-xxxx, xxx-xxx-xxxx, xxx.xxx.xxxx, +1-xxx-xxx-xxxx
      html.match?(/(\+\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}/)
    end

    def has_business_email?(client)
      return false unless client.document
      html = client.html.downcase
      uri = URI.parse(url)
      domain = uri.host.gsub('www.', '')
      # Look for email with the site's domain
      html.include?("@#{domain}")
    end

    def has_reviews?(client)
      return false unless client.document
      html = client.html.downcase
      html.include?('testimonial') || html.include?('review') || 
      html.include?('rating') || html.include?('star') ||
      html.include?('trustpilot') || html.include?('yelp')
    end

    def has_return_policy?
      uri = URI.parse(url)
      policy_paths = ['/returns', '/return-policy', '/refund', '/refund-policy', '/refunds']
      
      policy_paths.any? do |path|
        check_url = "#{uri.scheme}://#{uri.host}#{path}"
        begin
          response = Net::HTTP.get_response(URI.parse(check_url))
          response.is_a?(Net::HTTPSuccess)
        rescue StandardError
          false
        end
      end
    end

    def has_about_page?
      uri = URI.parse(url)
      about_paths = ['/about', '/about-us', '/about.html', '/our-story', '/who-we-are']
      
      about_paths.any? do |path|
        check_url = "#{uri.scheme}://#{uri.host}#{path}"
        begin
          response = Net::HTTP.get_response(URI.parse(check_url))
          response.is_a?(Net::HTTPSuccess)
        rescue StandardError
          false
        end
      end
    end

    def count_social_media_links(client)
      return 0 unless client.document
      
      social_domains = ['facebook.com', 'instagram.com', 'twitter.com', 'linkedin.com', 
                       'youtube.com', 'tiktok.com', 'pinterest.com']
      
      links = client.document.css('a[href]')
      links.count do |link|
        href = link['href'].to_s.downcase
        social_domains.any? { |domain| href.include?(domain) }
      end
    end
  end
end
