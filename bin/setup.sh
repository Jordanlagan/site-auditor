#!/bin/bash

# Site Auditor Development Setup Script

echo "🚀 Setting up Site Auditor..."

# Check Ruby version
echo ""
echo "Checking Ruby version..."
ruby_version=$(ruby -v | grep -oP '\d+\.\d+')
if (( $(echo "$ruby_version < 3.2" | bc -l) )); then
  echo "❌ Ruby 3.2+ required. You have Ruby $ruby_version"
  exit 1
fi
echo "✓ Ruby $ruby_version"

# Check Node version
echo ""
echo "Checking Node version..."
node_version=$(node -v | grep -oP '\d+' | head -1)
if (( node_version < 18 )); then
  echo "❌ Node 18+ required. You have Node $node_version"
  exit 1
fi
echo "✓ Node $(node -v)"

# Check PostgreSQL
echo ""
echo "Checking PostgreSQL..."
if ! command -v psql &> /dev/null; then
  echo "❌ PostgreSQL not found. Please install PostgreSQL first."
  exit 1
fi
echo "✓ PostgreSQL installed"

# Install Ruby dependencies
echo ""
echo "Installing Ruby dependencies..."
bundle install

# Install Node dependencies
echo ""
echo "Installing Node dependencies..."
cd frontend && yarn install && cd ..

# Check for .env file
echo ""
if [ ! -f .env ]; then
  echo "⚠️  No .env file found. Copying from .env.example..."
  cp .env.example .env
  echo "📝 Please edit .env and add your OPENAI_API_KEY"
fi

# Setup database
echo ""
echo "Setting up database..."
rails db:create
rails db:migrate

# Create screenshots directory
mkdir -p public/screenshots

echo ""
echo "✅ Setup complete!"
echo ""
echo "To start the app:"
echo "  Terminal 1: rails s"
echo "  Terminal 2: cd frontend && yarn dev"
echo ""
echo "Then visit: http://localhost:5173"
