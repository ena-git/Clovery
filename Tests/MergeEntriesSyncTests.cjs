const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const htmlPath = path.join(__dirname, '..', 'Clovery', 'Clover Diary.html');
const html = fs.readFileSync(htmlPath, 'utf8');

// Extract getDeletedMap / saveDeletedMap / mergeDeletedMap / getDeletedIds / mergeEntries
const startToken = 'function getDeletedMap()';
const endToken = '\n\nfunction App()';
const startIdx = html.indexOf(startToken);
const endIdx = html.indexOf(endToken, startIdx);
assert(startIdx !== -1 && endIdx !== -1, 'Could not locate sync helper functions in Clover Diary.html');

const codeSlice = html.slice(startIdx, endIdx);

const store = new Map();
const localStorageMock = {
  getItem: (k) => (store.has(k) ? store.get(k) : null),
  setItem: (k, v) => { store.set(k, String(v)); },
  removeItem: (k) => { store.delete(k); },
  clear: () => { store.clear(); },
};

const sandbox = {
  localStorage: localStorageMock,
  Date,
  Math,
  Number,
  String,
  Array,
  Object,
  Set,
  Map,
  JSON,
};
vm.createContext(sandbox);
vm.runInContext(codeSlice, sandbox);

// 1. Test edit conflict resolution via updatedAt
localStorageMock.clear();
const local1 = [
  { id: 'e1', date: '2026-11-24', lucky: 'Old text', tags: ['a'], photos: ['p1.jpg'], createdAt: 1000, updatedAt: 1000 },
];
const cloudNewer = [
  { id: 'e1', date: '2026-11-24', lucky: 'Edited text', tags: ['a', 'b'], photos: [], createdAt: 1000, updatedAt: 2000 },
];
const mergedEdit = sandbox.mergeEntries(local1, cloudNewer, { source: 'cloudkit' });
assert.strictEqual(mergedEdit.length, 1);
assert.strictEqual(mergedEdit[0].lucky, 'Edited text');
assert.deepStrictEqual(mergedEdit[0].tags, ['a', 'b']);
assert.strictEqual(mergedEdit[0].photos, undefined, 'CloudKit cleared photoCount=0 should drop local photos when newer');

// 2. Test KVS sync preserves local photos when edited remotely without photos payload
localStorageMock.clear();
const localWithPhoto = [
  { id: 'e2', date: '2026-11-24', lucky: 'Draft', photos: ['keep.jpg'], createdAt: 1000, updatedAt: 1000 },
];
const kvsUpdate = [
  { id: 'e2', date: '2026-11-24', lucky: 'Edited over KVS', createdAt: 1000, updatedAt: 3000 },
];
const mergedKvs = sandbox.mergeEntries(localWithPhoto, kvsUpdate, { source: 'kv' });
assert.strictEqual(mergedKvs[0].lucky, 'Edited over KVS');
assert.deepStrictEqual(mergedKvs[0].photos, ['keep.jpg'], 'KVS sync must not erase local photos');

// 3. Test tombstone propagation & resurrection prevention
localStorageMock.clear();
const localAlive = [
  { id: 'e3', date: '2026-11-24', lucky: 'To be deleted', createdAt: 1000, updatedAt: 1000 },
  { id: 'e4', date: '2026-11-24', lucky: 'Keep me', createdAt: 1500, updatedAt: 1500 },
];
const cloudTombstone = [
  { id: 'e3', isDeleted: true, deletedAt: 2500, updatedAt: 2500 },
];
const afterDelete = sandbox.mergeEntries(localAlive, cloudTombstone, { source: 'cloudkit' });
assert.strictEqual(afterDelete.length, 1);
assert.strictEqual(afterDelete[0].id, 'e4');
assert.strictEqual(sandbox.getDeletedMap().e3, 2500);

// Old stale cloud copy of e3 (updatedAt < deletedAt) must not resurrect
const afterStaleResync = sandbox.mergeEntries(afterDelete, [
  { id: 'e3', date: '2026-11-24', lucky: 'Zombie copy', createdAt: 1000, updatedAt: 1800 },
], { source: 'kv' });
assert.strictEqual(afterStaleResync.length, 1);

// 4. Test legacy clovery_deleted_ids backward compatibility
localStorageMock.clear();
localStorageMock.setItem('clovery_deleted_ids', JSON.stringify(['legacy-del']));
const legacyRes = sandbox.mergeEntries([], [
  { id: 'legacy-del', date: '2025-01-01', lucky: 'Old deleted', createdAt: 500 },
  { id: 'new-1', date: '2026-11-24', lucky: 'Alive', createdAt: 1000 },
]);
assert.strictEqual(legacyRes.length, 1);
assert.strictEqual(legacyRes[0].id, 'new-1');

console.log('MergeEntriesSyncTests PASSED');
