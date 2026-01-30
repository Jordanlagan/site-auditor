# Site Auditor

A comprehensive website analysis tool for agencies to audit client sites and gather detailed CRO (Conversion Rate Optimization) insights.

## What It Does

Crawls any website, analyzes page structure and content, captures full-page screenshots, and generates detailed reports with metrics like word counts, heading structure, link analysis, visual design elements, technical SEO, and accessibility data.

## Quick Start

### Prerequisites

- Ruby 3.2+
- PostgreSQL
- Node.js 18+ and Yarn
- Chrome/Chromium browser (for screenshots)
- OpenAI API key (for AI summaries)

### Setup

1. **Install dependencies**
   ```bash
   bundle install
   cd frontend && yarn install && cd ..
   ```

2. **Database setup**
   ```bash
   rails db:create db:migrate
   ```

3. **Environment variables**
   
   Create `.env` file in the root:
   ```
   OPENAI_API_KEY=your_openai_api_key_here
   CHROME_PATH=/usr/bin/google-chrome  # Optional: specify Chrome location
   ```

4. **Start the servers**
   
   Terminal 1 - Rails API:
   ```bash
   rails s
   ```
   
   Terminal 2 - React frontend:
   ```bash
   cd frontend
   yarn dev
   ```

5. **Open the app**
   
   Visit http://localhost:5173

## Important Notes

### Puppeteer/Chrome Issues

- **WSL1 Users**: Puppeteer may fail to launch Chrome due to kernel limitations. Screenshots will create placeholders. Consider upgrading to WSL2 or use a native Linux/macOS environment.

- **Chrome Installation**: The app looks for Chrome at `/usr/bin/google-chrome`, `/usr/bin/chromium`, or `/usr/bin/chromium-browser`. If Chrome is elsewhere, set `CHROME_PATH` in your `.env` file.

- **Headless Mode**: Screenshots run in headless mode with various flags for compatibility. If you encounter issues, check the Rails logs for detailed Puppeteer errors.

### Development Environment

- **File Watching (WSL)**: Vite is configured with polling for WSL compatibility (`usePolling: true`). This may use more CPU but ensures hot module reload works.

- **CORS**: The Rails API has CORS enabled for `http://localhost:5173` in development.

## Architecture

- **Backend**: Rails 7.2 API-only app with PostgreSQL
- **Frontend**: React + Vite with dark-themed UI
- **Screenshot Service**: Puppeteer-ruby for full-page captures
- **AI Integration**: OpenAI GPT-4o-mini for page summaries
- **Background Jobs**: ActiveJob (Async adapter) for page analysis

## Key Features

- Automatic page discovery via sitemap and crawling
- Priority-based analysis (homepage always prioritized)
- Full-page screenshots (desktop + mobile viewports)
- 50+ comprehensive metrics per page:
  - Content (word count, headings, reading time)
  - Assets (images, scripts, stylesheets)
  - Links (internal/external/backlinks)
  - Visual (colors, fonts)
  - Technical (meta tags, Open Graph, mobile optimization)
  - UX (navigation, forms, accessibility)
- AI-generated page summaries
- Summary dashboard with aggregated findings
- Expandable lightbox for screenshots
- On-demand analysis for additional pages

## Project Structure

```
app/
├── controllers/        # API endpoints
├── models/            # Database models
├── services/          # Business logic
│   └── audit_workflow/
│       ├── conductor.rb          # Orchestrates audit phases
│       ├── crawler.rb            # Page discovery & backlinks
│       ├── screenshot_service.rb # Puppeteer screenshots
│       ├── page_data_collector.rb # Metrics collection
│       └── page_summarizer.rb    # AI summaries
└── jobs/              # Background processing

frontend/
├── src/
│   ├── App.jsx                   # Main application
│   ├── ComprehensiveData.jsx    # Metrics display component
│   └── *.css                     # Styling
```

## License

Internal work project - not licensed for external use.
