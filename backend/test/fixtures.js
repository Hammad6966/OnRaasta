// Controlled query/transaction fixtures. These never connect to a database.
const mongoose = require('mongoose');
const models = Object.fromEntries(['User', 'Mechanic', 'Job', 'Bid', 'Vehicle', 'RefreshSession', 'AdminLog', 'DocumentReview'].map(name => [name, require(`../src/models/${name}`)]));
const ids = Object.fromEntries(['driver', 'foreign', 'mechanicUser', 'otherMechanicUser', 'unapprovedUser', 'admin',
  'mechanic', 'otherMechanic', 'unapproved', 'job', 'otherJob', 'bid', 'otherBid', 'vehicle'].map((k, i) => [k, (i + 1).toString(16).padStart(24, '0')]));
let db;
let nextId;
let lock = Promise.resolve();
const clone = value => structuredClone(value);
const get = (obj, key) => key.split('.').reduce((v, k) => v?.[k], obj);
function matches(doc, filter) {
  return Object.entries(filter).every(([key, value]) => {
    if (key === '$or') return value.some(v => matches(doc, v));
    const actual = get(doc, key);
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      if ('$regex' in value) return new RegExp(value.$regex, value.$options).test(String(actual || ''));
      if ('$in' in value) return value.$in.some(v => String(v) === String(actual));
      if ('$ne' in value) return String(actual) !== String(value.$ne);
      if ('$exists' in value) return (actual !== undefined) === value.$exists;
      if ('$gt' in value) return actual instanceof Date || value.$gt instanceof Date ? new Date(actual) > new Date(value.$gt) : actual > value.$gt;
      if ('$gte' in value || '$lte' in value) {
        const compare = (a, b) => a instanceof Date || b instanceof Date ? new Date(a).getTime() - new Date(b).getTime() : a - b;
        return (!('$gte' in value) || compare(actual, value.$gte) >= 0) && (!('$lte' in value) || compare(actual, value.$lte) <= 0);
      }
    }
    return value === null ? actual == null : String(actual) === String(value);
  });
}
function set(doc, path, value) {
  const keys = path.split('.'); const last = keys.pop();
  const obj = keys.reduce((v, k) => v[k] ||= {}, doc);
  obj[last] = clone(value);
}
function update(doc, change) {
  for (const [path, value] of Object.entries(change.$set || (change.$inc ? {} : change))) set(doc, path, value);
  for (const [path, value] of Object.entries(change.$inc || {})) set(doc, path, (get(doc, path) || 0) + value);
}
function query(name, execute) {
  let projection, order, offset = 0, count;
  const q = {
    session() { return q; }, sort(value) { order = value; return q; }, skip(value) { offset = value; return q; }, limit(value) { count = value; return q; },
    cursor() { return { async *[Symbol.asyncIterator]() { for (const value of await q) yield value; } }; }, populate() { return q; }, lean() { return q; },
    select(fields) { projection = fields; return q; },
    then(resolve, reject) {
      return Promise.resolve().then(execute).then(result => {
        const doc = raw => {
          if (!raw) return raw;
          let value = clone(raw);
          if (projection && !projection.split(' ').every(k => k.startsWith('+'))) {
            const keys = projection.split(' ');
            if (keys[0].startsWith('-')) keys.forEach(k => delete value[k.slice(1)]);
            else {
              const projected = {};
              for (const key of ['_id', ...keys]) if (get(value, key) !== undefined) set(projected, key, get(value, key));
              value = projected;
            }
          }
          Object.defineProperty(value, 'save', { value: async () => {
            const target = db[name].find(d => d._id === value._id); Object.assign(target, clone(value));
          } });
          return value;
        };
        if (Array.isArray(result)) {
          result = [...result];
          if (order) result.sort((a, b) => {
            for (const [key, direction] of Object.entries(order)) {
              const av = get(a, key), bv = get(b, key);
              const delta = av instanceof Date || bv instanceof Date ? new Date(av || 0) - new Date(bv || 0) : String(av ?? '').localeCompare(String(bv ?? ''));
              if (delta) return delta * direction;
            } return 0;
          });
          result = result.slice(offset, count === undefined ? undefined : offset + count);
        }
        return Array.isArray(result) ? result.map(doc) : result && typeof result === 'object' ? doc(result) : result;
      }).then(resolve, reject);
    },
  };
  return q;
}
function reset(hash) {
  const user = (id, role) => ({ _id: id, name: role, role, isActive: true, isVerified: true,
    phone: '3001234567', email: `${role}@example.test`, passwordHash: hash, failedLoginAttempts: 0 });
  db = {
    User: [user(ids.driver, 'user'), user(ids.foreign, 'user'), user(ids.mechanicUser, 'mechanic'),
      user(ids.otherMechanicUser, 'mechanic'), user(ids.unapprovedUser, 'mechanic'), user(ids.admin, 'admin')],
    Mechanic: [
      { _id: ids.mechanic, userId: ids.mechanicUser, isApproved: true, rating: 4, skills: [] },
      { _id: ids.otherMechanic, userId: ids.otherMechanicUser, isApproved: true, rating: 3, skills: [] },
      { _id: ids.unapproved, userId: ids.unapprovedUser, isApproved: false, rating: 0, skills: [] },
    ],
    Job: [{ _id: ids.job, userId: ids.driver, status: 'bidding', description: 'Battery failure', location: { lat: 31, lng: 74 } }],
    DocumentReview: [], AdminLog: [], RefreshSession: [], Bid: [], Vehicle: [{ _id: ids.vehicle, userId: ids.driver, plate: 'TEST' }],
  };
  nextId = 100;
}
function install(mock) {
  for (const [name, Model] of Object.entries(models)) {
    mock.method(Model, 'findById', id => query(name, () => db[name].find(d => d._id === String(id)) || null));
    mock.method(Model, 'findOne', filter => query(name, () => db[name].find(d => matches(d, filter)) || null));
    mock.method(Model, 'find', (filter = {}) => query(name, () => db[name].filter(d => matches(d, filter))));
    mock.method(Model, 'exists', filter => query(name, () => db[name].find(d => matches(d, filter)) ? { _id: 'exists' } : null));
    mock.method(Model, 'findOneAndUpdate', (filter, change) => query(name, () => {
      const doc = db[name].find(d => matches(d, filter)); if (!doc) return null; update(doc, change); return doc;
    }));
    mock.method(Model, 'findByIdAndUpdate', (id, change) => query(name, () => {
      const doc = db[name].find(d => d._id === id); if (!doc) return null; update(doc, change); return doc;
    }));
    mock.method(Model, 'updateMany', (filter, change) => query(name, () => {
      db[name].filter(d => matches(d, filter)).forEach(doc => update(doc, change)); return { acknowledged: true };
    }));
    mock.method(Model, 'create', async input => {
      const create = value => {
        const doc = { _id: (++nextId).toString(16).padStart(24, '0'), status: name === 'Job' ? 'pending' : 'pending', ...clone(value) };
        db[name].push(doc); return clone(doc);
      };
      return Array.isArray(input) ? input.map(create) : create(input);
    });
    mock.method(Model, 'deleteOne', (filter) => query(name, () => {
      const index = db[name].findIndex(d => matches(d, filter));
      if (index >= 0) db[name].splice(index, 1);
      return { deletedCount: index >= 0 ? 1 : 0 };
    }));
    mock.method(Model, 'countDocuments', async (filter = {}) => db[name].filter(d => matches(d, filter)).length);
    mock.method(Model, 'aggregate', async () => []);
  }
  mock.method(mongoose, 'startSession', async () => ({
    async withTransaction(work) {
      const previous = lock; let release; lock = new Promise(r => { release = r; });
      await previous; const snapshot = clone(db);
      try { return await work(); } catch (err) { db = snapshot; throw err; } finally { release(); }
    },
    async endSession() {},
  }));
}
module.exports = { ids, models, reset, install, data: () => db };
