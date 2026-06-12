async function test() {
  try {
    const res = await fetch('https://chatly-backend-nepf.onrender.com/api/auth/register', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        email: `test_user_${Date.now()}@example.com`,
        password: 'securePassword123!',
        username: `user_${Date.now().toString().slice(-6)}`,
        avatarColor: '#6366F1'
      })
    });
    
    console.log('Status Code:', res.status);
    const body = await res.json();
    console.log('Response Body:', body);
  } catch (e) {
    console.error('Error:', e);
  }
}

test();
