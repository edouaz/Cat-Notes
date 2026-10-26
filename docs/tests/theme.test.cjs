const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../theme.js'), 'utf8');

function page(saved, storageBlocked = false) {
  let ready;
  let change;
  let stored = saved;
  const root = { dataset: {} };
  const control = { value: '', addEventListener: (_, listener) => { change = listener; } };
  vm.runInNewContext(source, {
    document: {
      documentElement: root,
      addEventListener: (_, listener) => { ready = listener; },
      querySelector: () => control,
    },
    localStorage: {
      getItem: () => { if (storageBlocked) throw new Error('Blocked'); return stored; },
      setItem: (_, value) => { if (storageBlocked) throw new Error('Blocked'); stored = value; },
    },
  });
  ready();
  return {
    root, control,
    choose(value) { control.value = value; change(); },
    stored: () => stored,
  };
}

const fresh = page(null);
assert.equal(fresh.root.dataset.theme, undefined);
assert.equal(fresh.control.value, 'system');
fresh.choose('dark');
assert.equal(fresh.root.dataset.theme, 'dark');
assert.equal(fresh.stored(), 'dark');
fresh.choose('light');
assert.equal(fresh.root.dataset.theme, 'light');
fresh.choose('system');
assert.equal(fresh.root.dataset.theme, undefined);
assert.equal(fresh.stored(), 'system');
assert.equal(page('dark').root.dataset.theme, 'dark');
assert.equal(page('unexpected').control.value, 'system');
const blocked = page('dark', true);
assert.equal(blocked.control.value, 'system');
blocked.choose('light');
assert.equal(blocked.root.dataset.theme, 'light');
console.log('Appearance regression checks passed.');
