"""Verify the zero-cost journey on a USB-connected Android phone.

Start scripts/start-free-demo.ps1 -Reset before running this check.
"""
import argparse
import json
import re
import subprocess
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--device', default='0874637289000589')
parser.add_argument('--apk', default='build/app/outputs/flutter-apk/fitnep-free-demo.apk')
args = parser.parse_args()
adb_path = r'D:\Android\Sdk\platform-tools\adb.exe'
output = Path('.dart_tool/free-demo-check')
output.mkdir(parents=True, exist_ok=True)


def adb(*arguments):
    return subprocess.run([adb_path, '-s', args.device, *arguments], check=True, capture_output=True).stdout


def nodes():
    try:
        result = adb('shell', 'uiautomator', 'dump', '/sdcard/fitnep-free-demo.xml').decode(errors='replace')
        # UiAutomator sometimes returns exit 0 without producing a fresh dump.
        if 'dumped to:' not in result:
            return []
        return list(ET.fromstring(adb('shell', 'cat', '/sdcard/fitnep-free-demo.xml')).iter('node'))
    except (subprocess.CalledProcessError, ET.ParseError):
        return []


def find(label, scroll=False):
    for attempt in range(20):
        for node in nodes():
            if node.get('package') != 'com.example.fitnep' or node.get('enabled') != 'true':
                continue
            values = (node.get('text', ''), node.get('content-desc', ''))
            if any(label == value or label in value.splitlines() for value in values):
                bounds = list(map(int, re.findall(r'\d+', node.get('bounds', ''))))
                if len(bounds) == 4 and bounds[3] > bounds[1]:
                    return bounds
        if scroll and attempt < 5:
            adb('shell', 'input', 'swipe', '360', '1350', '360', '450', '350')
        time.sleep(0.3)
    (output / 'failure.png').write_bytes(adb('exec-out', 'screencap', '-p'))
    raise AssertionError(f'App label not found: {label}')


def tap(label, scroll=False):
    x1, y1, x2, y2 = find(label, scroll)
    adb('shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))
    print(f'Tapped: {label}', flush=True)
    time.sleep(0.5)


def capture(name):
    (output / f'{name}.png').write_bytes(adb('exec-out', 'screencap', '-p'))


def request(url, body=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = f'Bearer {token}'
    payload = None if body is None else json.dumps(body).encode()
    with urllib.request.urlopen(urllib.request.Request(url, data=payload, headers=headers), timeout=10) as response:
        return json.load(response)


token = request('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key', {'email': 'demo-client@fitnep.test', 'password': 'FitnepDemo123!', 'returnSecureToken': True})['idToken']
assert not request('http://127.0.0.1:3000/memberships/me', token=token)['data']['memberships'], 'Start a fresh demo with scripts/start-free-demo.ps1 -Reset before this check.'

adb('reverse', 'tcp:9099', 'tcp:9099')
adb('reverse', 'tcp:3000', 'tcp:3000')
adb('install', '-r', args.apk)
adb('shell', 'am', 'force-stop', 'com.example.fitnep')
adb('shell', 'am', 'start', '-n', 'com.example.fitnep/.MainActivity')
tap('Continue as demo client')
tap('Choose Basic', scroll=True)
tap('Confirm selection')
find('Pending')
capture('pending')
print('Client selection persisted as Pending.', flush=True)
tap('Back')
tap('Continue as demo admin')
tap('Review payment', scroll=True)
find('This approves a test payment. No money is charged.')
tap('Verify and activate')
find('No packages are awaiting verification.')
capture('approved')
print('Admin manually verified and activated the package.', flush=True)
tap('Back')
tap('Continue as demo client')
find('Active')
find('30 days remaining')
capture('active')
token = request('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key', {'email': 'demo-client@fitnep.test', 'password': 'FitnepDemo123!', 'returnSecureToken': True})['idToken']
members = request('http://127.0.0.1:3000/memberships/me', token=token)['data']['memberships']
assert len(members) == 1 and members[0]['status'] == 'active'
assert members[0]['days_remaining'] == 30
assert members[0]['package']['price_npr'] == 2500
start = datetime.fromisoformat(members[0]['start_at'].replace('Z', '+00:00'))
end = datetime.fromisoformat(members[0]['end_at'].replace('Z', '+00:00'))
assert end - start == timedelta(days=30)
try:
    request(f"http://127.0.0.1:3000/admin/memberships/{members[0]['id']}/verify-payment", {'reference': 'CLIENT-BYPASS'}, token)
    raise AssertionError('Client was allowed to verify a payment.')
except urllib.error.HTTPError as error:
    assert error.code == 403
print(f'Phone UI and persisted API state passed. Screenshots: {output}', flush=True)
