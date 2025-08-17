#!/usr/bin/env node

// Setup script for Encrypted Chat Backend
// Run with: node setup.js

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

console.log('🔐 Encrypted Chat Backend Setup\n');

async function setup() {
  try {
    // Check if .env exists
    const envPath = path.join(__dirname, '.env');
    if (!fs.existsSync(envPath)) {
      console.log('📝 Creating .env file from template...');
      
      const templatePath = path.join(__dirname, 'env.template');
      if (fs.existsSync(templatePath)) {
        fs.copyFileSync(templatePath, envPath);
        console.log('✅ .env file created');
        console.log('⚠️  Please edit .env with your database credentials and JWT secret\n');
      } else {
        console.log('❌ env.template not found');
        return;
      }
    } else {
      console.log('✅ .env file already exists\n');
    }

    // Check if Prisma client is generated
    console.log('🔧 Checking Prisma setup...');
    try {
      require('@prisma/client');
      console.log('✅ Prisma client already generated');
    } catch (error) {
      console.log('📦 Generating Prisma client...');
      execSync('npx prisma generate', { stdio: 'inherit' });
      console.log('✅ Prisma client generated');
    }

    // Check database connection
    console.log('\n🗄️  Checking database connection...');
    try {
      execSync('npx prisma db push --accept-data-loss', { stdio: 'inherit' });
      console.log('✅ Database schema updated');
    } catch (error) {
      console.log('❌ Database connection failed');
      console.log('Please check your DATABASE_URL in .env file');
      return;
    }

    console.log('\n🎉 Setup completed successfully!');
    console.log('\nNext steps:');
    console.log('1. Edit .env with your database credentials');
    console.log('2. Run: npm run dev');
    console.log('3. Test endpoints: node test-endpoints.js');
    console.log('\n📚 See README.md for more information');

  } catch (error) {
    console.error('❌ Setup failed:', error.message);
  }
}

if (require.main === module) {
  setup();
}

module.exports = { setup };
