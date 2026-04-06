#!/usr/bin/env node

import WebSocket from 'ws';
import { execSync } from 'child_process';

const CXN_HOST = '192.168.x.x';

function powerOffCXN() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://${CXN_HOST}:80/smoip`, {
      headers: {
        Origin: `ws://${CXN_HOST}`,
        Host: `${CXN_HOST}:80`,
      },
    });

    const timeout = setTimeout(() => {
      ws.close();
      reject(new Error('Timed out connecting to CXN'));
    }, 5000);

    ws.on('open', () => {
      ws.send(JSON.stringify({ path: '/zone/state', params: { power: false } }));
      setTimeout(() => {
        clearTimeout(timeout);
        ws.close();
        resolve();
      }, 1000);
    });

    ws.on('error', (err) => {
      clearTimeout(timeout);
      reject(err);
    });
  });
}

// Quit Roon
try {
  console.log('Quitting Roon...');
  execSync('osascript -e \'tell application "Roon" to quit\'');
  console.log('Roon quit');
} catch (err) {
  console.log('Roon not running or already quit');
}

// Power off CXN
try {
  console.log('Powering off CXN v2...');
  await powerOffCXN();
  console.log('CXN v2 powered off');
} catch (err) {
  console.error('CXN error:', err.message);
}

console.log('Done');
