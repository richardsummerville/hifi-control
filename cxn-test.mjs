import WebSocket from 'ws';

const CXN_HOST = '192.168.x.x';
const ws = new WebSocket(`ws://${CXN_HOST}:80/smoip`, {
  headers: {
    Origin: `ws://${CXN_HOST}`,
    Host: `${CXN_HOST}:80`,
  },
});

ws.on('open', () => {
  console.log('Connected to CXN v2');

  // Power OFF
  console.log('\n⏻  Sending power OFF...');
  ws.send(JSON.stringify({ path: '/zone/state', params: { power: false } }));

  // Wait 5 seconds then power ON
  setTimeout(() => {
    console.log('\n⏻  Sending power ON...');
    ws.send(JSON.stringify({ path: '/zone/state', params: { power: true } }));
  }, 5000);

  // Exit after 8 seconds
  setTimeout(() => {
    console.log('\nDone');
    ws.close();
    process.exit(0);
  }, 8000);
});

ws.on('message', (data) => {
  const msg = JSON.parse(data.toString());
  if (msg.path === '/zone/state') {
    console.log(`   power: ${msg.params?.power}, source: ${msg.params?.source}`);
  }
});

ws.on('error', (err) => {
  console.error('ERR:', err.message);
  process.exit(1);
});
