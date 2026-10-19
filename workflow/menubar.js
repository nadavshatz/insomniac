// menubar.js — Insomniac menu bar indicator (JavaScript for Automation).
//
//   /usr/bin/osascript -l JavaScript menubar.js <workflow_data_dir> <toggle_engine.sh>
//
// Started by toggle_engine.sh when a session begins, killed when it ends.
// Shows a cup (idle-only) or laptop (closed-lid) with the time left, and a
// menu with Extend / Stop. It holds no state of its own: every second it
// reads the engine's state file, and every few seconds it asks the engine to
// reconcile with reality. When the session is gone, it quits. Uses only the
// Cocoa bridge built into macOS, with no extra runtime.

ObjC.import('Cocoa');
ObjC.import('stdlib');

const LABEL = 'io.github.nadavshatz.insomniac';
const LAST_REASON = '/var/run/' + LABEL + '.last';
const RECONCILE_EVERY = 5; // seconds

let dataDir, engine, statusItem, menu, header, detail, ext15, ext60, sepExt, ctrl;
let images = {};
let ticks = 0;
let degraded = false;

const sa = Application.currentApplication();
sa.includeStandardAdditions = true;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function readFile(path) {
  const s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  return s && !s.isNil() ? ObjC.unwrap(s) : null;
}

function readState() {
  const text = readFile(dataDir + '/state');
  if (!text) return null;
  const st = {};
  text.split('\n').forEach(function (line) {
    const m = /^([A-Z_]+)=([A-Za-z0-9_.-]*)$/.exec(line);
    if (m) st[m[1]] = m[2];
  });
  return st.MODE === 'idle' || st.MODE === 'lid' ? st : null;
}

function fmtLeft(secs) {
  secs = Math.max(0, Math.floor(secs));
  const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60);
  if (h) return h + 'h ' + (m < 10 ? '0' : '') + m + 'm';
  if (m) return m + 'm';
  return secs + 's';
}

function fmtClock(epoch) {
  const d = new Date(epoch * 1000);
  const pad = function (n) { return (n < 10 ? '0' : '') + n; };
  return pad(d.getHours()) + ':' + pad(d.getMinutes());
}

function notify(msg) {
  try { sa.displayNotification(msg, { withTitle: 'Insomniac' }); } catch (e) { /* notifications off */ }
}

function symbol(name, fallback) {
  try {
    const img = $.NSImage.imageWithSystemSymbolNameAccessibilityDescription(name, 'Insomniac');
    if (img && !img.isNil()) { img.setTemplate(true); return img; }
  } catch (e) { /* older macOS */ }
  return fallback;
}

// Run the engine and return the last line it printed. INSOMNIAC_FROM_MENUBAR
// tells the engine not to kill this process: we quit on our own after
// posting the result.
function engineCall(arg) {
  const task = $.NSTask.alloc.init;
  task.setLaunchPath('/bin/zsh');
  task.setArguments($(['-f', engine, arg]));
  const env = $.NSProcessInfo.processInfo.environment.mutableCopy;
  env.setObjectForKey('1', 'INSOMNIAC_FROM_MENUBAR');
  task.setEnvironment(env);
  const pipe = $.NSPipe.pipe;
  task.setStandardOutput(pipe);
  task.setStandardError($.NSFileHandle.fileHandleWithNullDevice);
  try { task.launch; } catch (e) { return ''; }
  const data = pipe.fileHandleForReading.readDataToEndOfFile;
  task.waitUntilExit;
  const out = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)) || '';
  const lines = out.trim().split('\n');
  return lines[lines.length - 1] || '';
}

function quit() { $.exit(0); }

// ---------------------------------------------------------------------------
// UI
// ---------------------------------------------------------------------------
function menuItem(title, action) {
  const mi = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent(title, action, '');
  mi.setTarget(ctrl);
  return mi;
}

function build() {
  const app = $.NSApplication.sharedApplication;
  app.setActivationPolicy(1); // NSApplicationActivationPolicyAccessory: no Dock icon

  statusItem = $.NSStatusBar.systemStatusBar.statusItemWithLength(-1); // variable length
  images = {
    idle: symbol('cup.and.saucer.fill', null),
    lid: symbol('laptopcomputer', null),
    warn: symbol('exclamationmark.triangle.fill', null),
  };
  try {
    statusItem.button.setFont($.NSFont.monospacedDigitSystemFontOfSizeWeight(0, 0));
  } catch (e) { /* keep default font */ }

  menu = $.NSMenu.alloc.init;
  menu.setAutoenablesItems(false);
  header = menuItem('Insomniac', 'noop:');
  header.setEnabled(false);
  detail = menuItem('', 'noop:');
  detail.setEnabled(false);
  ext15 = menuItem('Extend +15 Minutes', 'extend15:');
  ext60 = menuItem('Extend +1 Hour', 'extend60:');
  sepExt = $.NSMenuItem.separatorItem;
  menu.addItem(header);
  menu.addItem(detail);
  menu.addItem($.NSMenuItem.separatorItem);
  menu.addItem(ext15);
  menu.addItem(ext60);
  menu.addItem(sepExt);
  menu.addItem(menuItem('Stop & Restore Normal Sleep', 'stop:'));
  statusItem.setMenu(menu);

  const timer = $.NSTimer.timerWithTimeIntervalTargetSelectorUserInfoRepeats(1, ctrl, 'tick:', $(), true);
  // Common modes: keep the countdown running while the menu is open.
  $.NSRunLoop.currentRunLoop.addTimerForMode(timer, 'kCFRunLoopCommonModes');
}

function render(st) {
  const now = Date.now() / 1000;
  const exp = Number(st.EXPIRES) || 0;
  const left = exp ? fmtLeft(exp - now) : '∞';
  const lid = st.MODE === 'lid';
  const img = degraded ? images.warn : lid ? images.lid : images.idle;
  const button = statusItem.button;
  if (img) {
    button.setImage(img);
    button.setImagePosition(2); // NSImageLeft
    button.setTitle(' ' + left);
  } else {
    button.setTitle((degraded ? '⚠ ' : lid ? '💻 ' : '☕ ') + left);
  }
  header.setTitle(degraded ? '⚠ Sleep disabled, guardian not running'
                           : lid ? 'Closed-Lid mode' : 'Keeping your Mac awake');
  const disp = st.DISPLAY === '0' ? 'display can sleep' : 'display stays on';
  detail.setTitle((exp ? 'Until ' + fmtClock(exp) + ' (' + left + ' left)' : 'Indefinite') + ' · ' + disp);
  ext15.setHidden(!exp);
  ext60.setHidden(!exp);
  sepExt.setHidden(!exp);
}

// Explain why a session ended without the user stopping it.
function notifyEnded(st) {
  const now = Date.now() / 1000;
  const exp = Number(st.EXPIRES) || 0;
  if (st.MODE === 'lid') {
    const r = (readFile(LAST_REASON) || '').trim().split(' ');
    if (r.length === 2 && now - Number(r[1]) < 60) {
      const why = { timer: 'timer finished', battery: 'battery low', thermal: 'Mac running hot',
                    external: 'sleep re-enabled elsewhere' }[r[0]];
      if (why) notify('Closed-lid mode ended (' + why + '). Normal sleep restored.');
    }
  } else if (exp && now >= exp - RECONCILE_EVERY) {
    notify('Timer finished. Your Mac can sleep normally again.');
  }
}

function tick() {
  ticks++;
  const st = readState();
  if (!st) return quit();
  if (ticks % RECONCILE_EVERY === 0) {
    const status = engineCall('reconcile');
    if (status === 'inactive' || status === 'orphan') { notifyEnded(st); return quit(); }
    degraded = status === 'degraded';
  }
  render(st);
}

function act(arg) {
  const msg = engineCall(arg);
  if (msg) notify(msg);
  const st = readState();
  if (!st) return quit();
  render(st);
}

ObjC.registerSubclass({
  name: 'InsomniacMenuController',
  methods: {
    'tick:':     { types: ['void', ['id']], implementation: function () { tick(); } },
    'noop:':     { types: ['void', ['id']], implementation: function () {} },
    'extend15:': { types: ['void', ['id']], implementation: function () { act('extend 900'); } },
    'extend60:': { types: ['void', ['id']], implementation: function () { act('extend 3600'); } },
    'stop:':     { types: ['void', ['id']], implementation: function () { act('stop'); } },
  },
});

function run(argv) {
  dataDir = argv[0];
  engine = argv[1];
  if (!dataDir || !engine) return 'usage: menubar.js <data_dir> <toggle_engine.sh>';
  ctrl = $.InsomniacMenuController.alloc.init;
  build();
  const st = readState();
  if (!st) return quit();
  render(st);
  $.NSApplication.sharedApplication.run;
}
