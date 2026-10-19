#!/usr/bin/env node
// Unit tests for workflow/menubar.js. Runs the JXA script under Node with a
// minimal fake of the Cocoa bridge: no macOS needed. On a Mac, CI also
// compiles it for real with `osacompile -l JavaScript`.
'use strict';
const fs = require('fs'), os = require('os'), path = require('path'), vm = require('vm');
const assert = require('assert');

const src = fs.readFileSync(path.join(__dirname, '..', 'workflow', 'menubar.js'), 'utf8');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'insomniac-mb-'));
const notes = [], calls = [];
let exited = 0;

class Exit extends Error {}
const fakeItem = () => {
  const o = { title: '', hidden: false, image: null, enabled: true };
  o.setTitle = (t) => { o.title = t; };
  o.setHidden = (h) => { o.hidden = !!h; };
  o.setEnabled = (e) => { o.enabled = !!e; };
  o.setImage = (i) => { o.image = i; };
  o.setImagePosition = () => {};
  return o;
};
const $ = (x) => x;
Object.assign($, {
  NSUTF8StringEncoding: 4,
  NSString: {
    stringWithContentsOfFileEncodingError: (p) => {
      try { return { isNil: () => false, v: fs.readFileSync(p, 'utf8') }; }
      catch (e) { return { isNil: () => true }; }
    },
  },
  exit: (code) => { exited++; throw new Exit(String(code)); },
});
const ctx = vm.createContext({
  $, console, Date, Number, Math, String,
  ObjC: { import() {}, registerSubclass() {}, unwrap: (s) => (s && s.v !== undefined ? s.v : s) },
  Application: { currentApplication: () => ({ displayNotification: (m) => notes.push(m) }) },
});
vm.runInContext(src, ctx);

// Wire up fakes in place of build().
ctx.__fakeItem = fakeItem;
ctx.__calls = calls;
vm.runInContext(`
  dataDir = ${JSON.stringify(dir)};
  statusItem = { button: __fakeItem() };
  header = __fakeItem(); detail = __fakeItem();
  ext15 = __fakeItem(); ext60 = __fakeItem(); sepExt = __fakeItem();
  images = { idle: 'IMG_CUP', lid: 'IMG_LAPTOP', warn: 'IMG_WARN' };
  var __next = 'active';
  engineCall = function (arg) { __calls.push(arg); return typeof __next === 'function' ? __next(arg) : __next; };
`, ctx);
const run = (code) => vm.runInContext(code, ctx);
const now = () => Math.floor(Date.now() / 1000);
const writeState = (kv) => fs.writeFileSync(path.join(dir, 'state'),
  Object.entries(kv).map(([k, v]) => `${k}=${v}`).join('\n') + '\n');
const expectExit = (fn) => { const before = exited; try { fn(); } catch (e) { if (!(e instanceof Exit)) throw e; } return exited > before; };

let passed = 0;
function test(name, fn) {
  try { fn(); passed++; console.log('\u2714 ' + name); }
  catch (e) { console.log('\u2718 ' + name + '\n   ' + e.message); process.exitCode = 1; }
}

test('fmtLeft formats hours, minutes, seconds', () => {
  assert.strictEqual(run('fmtLeft(3900)'), '1h 05m');
  assert.strictEqual(run('fmtLeft(2520)'), '42m');
  assert.strictEqual(run('fmtLeft(30)'), '30s');
  assert.strictEqual(run('fmtLeft(-5)'), '0s');
});

test('readState parses KEY=VALUE and rejects junk', () => {
  writeState({ MODE: 'idle', EXPIRES: 123, DISPLAY: 0 });
  assert.deepStrictEqual(JSON.parse(run('JSON.stringify(readState())')), { MODE: 'idle', EXPIRES: '123', DISPLAY: '0' });
  writeState({ MODE: 'bogus' });
  assert.strictEqual(run('readState()'), null);
  fs.writeFileSync(path.join(dir, 'state'), 'MODE=idle\nEVIL=$(rm -rf /)\n');
  assert.strictEqual(run('readState().EVIL'), undefined);
});

test('idle timed session renders cup + countdown + extend items', () => {
  writeState({ MODE: 'idle', EXPIRES: now() + 2530, DISPLAY: 1 });
  run('render(readState())');
  assert.strictEqual(run('statusItem.button.image'), 'IMG_CUP');
  assert.match(run('statusItem.button.title'), /^ 42m$/);
  assert.strictEqual(run('header.title'), 'Keeping your Mac awake');
  assert.match(run('detail.title'), /^Until \d\d:\d\d \(42m left\) · display stays on$/);
  assert.strictEqual(run('ext15.hidden'), false);
});

test('closed-lid indefinite renders laptop, ∞ and hides extend', () => {
  writeState({ MODE: 'lid', EXPIRES: 0, DISPLAY: 0 });
  run('render(readState())');
  assert.strictEqual(run('statusItem.button.image'), 'IMG_LAPTOP');
  assert.strictEqual(run('statusItem.button.title'), ' ∞');
  assert.strictEqual(run('header.title'), 'Closed-Lid mode');
  assert.strictEqual(run('detail.title'), 'Indefinite · display can sleep');
  assert.strictEqual(run('ext15.hidden') && run('ext60.hidden') && run('sepExt.hidden'), true);
});

test('falls back to emoji when SF Symbols are unavailable', () => {
  run("images = { idle: null, lid: null, warn: null }");
  writeState({ MODE: 'lid', EXPIRES: 0 });
  run('render(readState())');
  assert.strictEqual(run('statusItem.button.title'), '💻 ∞');
  run("images = { idle: 'IMG_CUP', lid: 'IMG_LAPTOP', warn: 'IMG_WARN' }");
});

test('tick quits when the state file is gone', () => {
  fs.rmSync(path.join(dir, 'state'), { force: true });
  assert.ok(expectExit(() => run('tick()')));
});

test('tick reconciles every 5 seconds, not every second', () => {
  writeState({ MODE: 'idle', EXPIRES: now() + 600 });
  calls.length = 0;
  run('ticks = 0');
  for (let i = 0; i < 10; i++) run('tick()');
  assert.deepStrictEqual(calls, ['reconcile', 'reconcile']);
});

test('degraded status shows the warning icon', () => {
  writeState({ MODE: 'lid', EXPIRES: 0 });
  run("__next = 'degraded'; ticks = 4; tick()");
  assert.strictEqual(run('statusItem.button.image'), 'IMG_WARN');
  assert.match(run('header.title'), /guardian not running/);
  run("__next = 'active'; ticks = 4; tick()");
  assert.strictEqual(run('statusItem.button.image'), 'IMG_LAPTOP');
});

test('finished idle timer: quits with a notification', () => {
  writeState({ MODE: 'idle', EXPIRES: now() - 1 });
  notes.length = 0;
  run("__next = 'inactive'; ticks = 4");
  assert.ok(expectExit(() => run('tick()')));
  assert.deepStrictEqual(notes, ['Timer finished. Your Mac can sleep normally again.']);
  run("__next = 'active'");
});

test('manual stop of indefinite idle session: quits silently', () => {
  writeState({ MODE: 'idle', EXPIRES: 0 });
  notes.length = 0;
  run("__next = 'inactive'; ticks = 4");
  assert.ok(expectExit(() => run('tick()')));
  assert.deepStrictEqual(notes, []);
  run("__next = 'active'");
});

test('Stop menu item: runs engine stop, notifies, quits once state is gone', () => {
  writeState({ MODE: 'idle', EXPIRES: 0 });
  notes.length = 0; calls.length = 0;
  ctx.__rm = () => fs.rmSync(path.join(dir, 'state'));
  run("__next = function () { __rm(); return 'Normal sleep restored'; }");
  assert.ok(expectExit(() => run("act('stop')")));
  assert.deepStrictEqual(calls, ['stop']);
  assert.deepStrictEqual(notes, ['Normal sleep restored']);
  run("__next = 'active'");
});

test('Extend menu item: runs engine extend and keeps running', () => {
  writeState({ MODE: 'idle', EXPIRES: now() + 60 });
  calls.length = 0;
  run(`__next = function () { return 'Keeping your Mac awake for 16m'; }`);
  assert.ok(!expectExit(() => run("act('extend 900')")));
  assert.deepStrictEqual(calls, ['extend 900']);
  run("__next = 'active'");
});

fs.rmSync(dir, { recursive: true, force: true });
console.log(`\nmenubar: ${passed} passed${process.exitCode ? ', some FAILED' : ''}`);
