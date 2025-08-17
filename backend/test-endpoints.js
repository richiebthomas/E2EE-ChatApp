// Simple test script to verify backend endpoints
// Run with: node test-endpoints.js

const axios = require('axios');

const BASE_URL = 'http://localhost:3000/api';

// Test data
const testUser = {
  username: 'testuser1',
  email: 'test1@example.com',
  password: 'testpassword123',
  identityPubkey: 'dGVzdF9pZGVudGl0eV9wdWJrZXk=' // base64 encoded "test_identity_pubkey"
};

const testPrekeys = {
  signedPrekey: 'dGVzdF9zaWduZWRfcHJla2V5', // base64 encoded "test_signed_prekey"
  prekeySignature: 'dGVzdF9zaWduYXR1cmU=', // base64 encoded "test_signature"
  keyId: 1,
  oneTimePrekeys: [
    'dGVzdF9vdHBfMQ==', // base64 encoded "test_otp_1"
    'dGVzdF9vdHBfMg==', // base64 encoded "test_otp_2"
    'dGVzdF9vdHBfMw==' // base64 encoded "test_otp_3"
  ]
};

async function testEndpoints() {
  let authToken = '';
  let userId = '';

  try {
    console.log('🧪 Testing Encrypted Chat Backend...\n');

    // Test health check
    console.log('1. Testing health check...');
    const healthResponse = await axios.get('http://localhost:3000/health');
    console.log('✅ Health check:', healthResponse.data);

    // Test user registration
    console.log('\n2. Testing user registration...');
    const registerResponse = await axios.post(`${BASE_URL}/auth/register`, testUser);
    authToken = registerResponse.data.token;
    userId = registerResponse.data.user.id;
    console.log('✅ Registration successful:', registerResponse.data.user);

    // Test login
    console.log('\n3. Testing user login...');
    const loginResponse = await axios.post(`${BASE_URL}/auth/login`, {
      email: testUser.email,
      password: testUser.password
    });
    console.log('✅ Login successful:', loginResponse.data.user);

    // Setup auth headers
    const authHeaders = {
      'Authorization': `Bearer ${authToken}`,
      'Content-Type': 'application/json'
    };

    // Test token verification
    console.log('\n4. Testing token verification...');
    const verifyResponse = await axios.get(`${BASE_URL}/auth/verify`, { headers: authHeaders });
    console.log('✅ Token verification:', verifyResponse.data);

    // Test prekey upload
    console.log('\n5. Testing prekey upload...');
    const prekeyResponse = await axios.post(`${BASE_URL}/prekeys/upload`, testPrekeys, { headers: authHeaders });
    console.log('✅ Prekeys uploaded:', prekeyResponse.data);

    // Test prekey fetch
    console.log('\n6. Testing prekey fetch...');
    const fetchPrekeyResponse = await axios.get(`${BASE_URL}/prekeys/${userId}`, { headers: authHeaders });
    console.log('✅ Prekey bundle fetched:', fetchPrekeyResponse.data);

    // Test user profile
    console.log('\n7. Testing user profile...');
    const profileResponse = await axios.get(`${BASE_URL}/users/me`, { headers: authHeaders });
    console.log('✅ User profile:', profileResponse.data);

    // Test message sending (to self for testing)
    console.log('\n8. Testing message sending...');
    const messageResponse = await axios.post(`${BASE_URL}/messages/send`, {
      recipientId: userId,
      ciphertext: 'dGVzdF9lbmNyeXB0ZWRfbWVzc2FnZQ==' // base64 encoded "test_encrypted_message"
    }, { headers: authHeaders });
    console.log('✅ Message sent:', messageResponse.data);

    console.log('\n🎉 All tests passed! Backend is working correctly.');

  } catch (error) {
    console.error('\n❌ Test failed:', error.response?.data || error.message);
    
    if (error.response) {
      console.error('Status:', error.response.status);
      console.error('Response:', error.response.data);
    }
  }
}

// Run tests
if (require.main === module) {
  testEndpoints();
}

module.exports = { testEndpoints };
