#!/usr/bin/env node

import WebSocket from 'ws';
import { execSync } from 'child_process';

const CXN_HOST = process.env.CXN_IP || '0.0.0.0';

function sendCXN(params) {
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
      ws.send(JSON.stringify({ path: '/zone/state', params }));
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

try {
  console.log('Powering off CXN v2...');
  await sendCXN({ power: false });
  console.log('Waiting for clean shutdown...');
  await new Promise((r) => setTimeout(r, 3000));
  console.log('Powering on CXN v2...');
  await sendCXN({ power: true });
  console.log('CXN v2 powered on');
} catch (err) {
  console.error('CXN error:', err.message);
}

console.log('Launching Roon...');
execSync('open /Applications/Roon.app');
console.log('Done');
