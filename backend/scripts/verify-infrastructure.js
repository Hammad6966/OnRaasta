const fs = require('fs');
const path = require('path');
const dns = require('dns').promises;
const tls = require('tls');
const mongoose = require('mongoose');
const dotenv = require('dotenv');
const config = fs.existsSync(path.resolve(__dirname, '../.env')) ? dotenv.parse(fs.readFileSync(path.resolve(__dirname, '../.env'))) : {};
const env = { ...config, ...process.env };
const report = { checkedAt: new Date().toISOString(), policy: 'read_only_no_schema_or_application_writes', configuration: {}, dns: {}, tls: {}, mongo: {}, indexes: [] };
function category(err) {
  const message = String(err?.message || '');
  if (/auth|bad auth/i.test(message) || err?.code === 18) return 'authentication';
  if (err?.code === 13 || /not authorized/i.test(message)) return 'authorization';
  if (/querySrv|ENOTFOUND|ECONNREFUSED.*_mongodb|EAI_AGAIN/i.test(message)) return 'dns';
  if (/TLS|SSL|certificate/i.test(message)) return 'tls';
  if (/timeout|ETIMEDOUT|server selection/i.test(message)) return 'network_allowlist_cluster_or_timeout';
  return 'connection_or_configuration';
}
const canonical = obj => Array.isArray(obj) ? obj.map(canonical) : obj && typeof obj === 'object' ? Object.fromEntries(Object.keys(obj).sort().map(k => [k, canonical(obj[k])])) : obj;
const signature = (key, o) => JSON.stringify(canonical({ key: Object.entries(key), unique: !!o.unique, sparse: !!o.sparse, partialFilterExpression: o.partialFilterExpression || null, expireAfterSeconds: o.expireAfterSeconds ?? null }));
(async () => {
 let conn;
 try {
  const uri = env.MONGODB_URI || env.MONGO_URI;
  report.configuration = { MONGODB_URI: !!env.MONGODB_URI, MONGO_URI: !!env.MONGO_URI, aliasesAgree: !(env.MONGODB_URI && env.MONGO_URI && env.MONGODB_URI !== env.MONGO_URI), isolatedTestUriConfigured: !!env.ONRAASTA_TEST_MONGO_URI };
  if (!uri || !report.configuration.aliasesAgree) throw new Error('Missing or conflicting database configuration');
  const parsed = new URL(uri);
  if (!['mongodb:', 'mongodb+srv:'].includes(parsed.protocol)) throw new Error('Invalid URI scheme');
  decodeURIComponent(parsed.username); decodeURIComponent(parsed.password);
  const dbName = decodeURIComponent(parsed.pathname.slice(1));
  report.configuration.uriFormatValid = true;
  report.configuration.explicitDatabase = !!dbName;
  report.configuration.srv = parsed.protocol === 'mongodb+srv:';
  report.configuration.tlsDisabled = ['false', '0'].includes(parsed.searchParams.get('tls')) || ['false', '0'].includes(parsed.searchParams.get('ssl'));
  if (report.configuration.tlsDisabled) throw new Error('TLS disabled in configured URI');
  let servers;
  try {
   servers = report.configuration.srv ? await dns.resolveSrv('_mongodb._tcp.' + parsed.hostname) : [{ name: parsed.hostname, port: Number(parsed.port || 27017) }];
   report.dns = { success: true, serverCount: servers.length };
  } catch (e) { report.dns = { success: false, category: category(e), code: /^[A-Z_]+$/.test(e.code || '') ? e.code : 'DNS_ERROR' }; throw e; }
  const tlsResults = await Promise.all(servers.slice(0, 3).map(server => new Promise(resolve => {
   const socket = tls.connect({ host: server.name, port: server.port, servername: server.name, rejectUnauthorized: true });
   const done = result => { socket.destroy(); resolve(result); };
   socket.setTimeout(8000, () => done({ success: false, category: 'timeout' }));
   socket.once('secureConnect', () => done({ success: socket.authorized, protocol: socket.getProtocol() }));
   socket.once('error', e => done({ success: false, category: category(e) }));
  })));
  report.tls = { success: tlsResults.some(r => r.success), attempts: tlsResults };
  conn = mongoose.createConnection(uri, { autoIndex: false, autoCreate: false, serverSelectionTimeoutMS: 10000, connectTimeoutMS: 8000, socketTimeoutMS: 10000, maxPoolSize: 5, minPoolSize: 0 });
  let connectionsCreated = 0; conn.getClient().on('connectionCreated', () => connectionsCreated++);
  await conn.asPromise();
  report.mongo.connected = true;
  report.mongo.selectedMatchesConfigured = dbName ? conn.name === dbName : null;
  report.mongo.selectedDefaultTest = conn.name === 'test';
  const hello = await conn.db.command({ hello: 1 });
  report.mongo.replicaSet = !!hello.setName;
  report.mongo.sharded = hello.msg === 'isdbgrid';
  report.mongo.sessionsSupported = hello.logicalSessionTimeoutMinutes != null;
  report.mongo.transactionCapabilityAdvertised = !!(hello.logicalSessionTimeoutMinutes != null && (hello.setName || hello.msg === 'isdbgrid') && hello.maxWireVersion >= 7);
  report.mongo.transactionWritesTested = false;
  await Promise.all([1, 2, 3].map(() => conn.db.command({ ping: 1 })));
  await conn.db.collection('users').findOne({}, { projection: { _id: 1 }, maxTimeMS: 3000 });
  report.mongo.readOperationSucceeded = true;
  report.mongo.pool = { maxPoolSize: 5, connectionsCreated, concurrentPingsSucceeded: true };
  try {
   const status = await conn.db.command({ connectionStatus: 1, showPrivileges: true });
   const actions = new Set((status.authInfo?.authenticatedUserPrivileges || []).flatMap(p => p.actions || []));
   report.mongo.permissions = { authenticated: !!status.authInfo?.authenticatedUsers?.length, readAdvertised: actions.has('find'), insertAdvertised: actions.has('insert'), updateAdvertised: actions.has('update'), createIndexAdvertised: actions.has('createIndex'), privilegesInspected: true };
  } catch(e) { report.mongo.permissions = { privilegesInspected: false, category: category(e) }; }
  for (const name of ['User', 'Mechanic', 'Job', 'Bid', 'Vehicle', 'RefreshSession', 'AdminLog']) {
   const model = require('../src/models/' + name);
   const collection = model.collection.collectionName;
   const expected = model.schema.indexes().map(([key, opts]) => ({ key, ...opts }));
   try {
    const actual = await conn.db.collection(collection).listIndexes().toArray();
    const missing = expected.filter(index => !actual.some(a => signature(a.key, a) === signature(index.key, index)));
    report.indexes.push({ model: name, collectionExists: true, expectedCount: expected.length, actualCount: actual.length,
      actual: actual.map(({ key, unique, sparse, expireAfterSeconds, partialFilterExpression }) => ({ key, unique: !!unique, sparse: !!sparse, ...(expireAfterSeconds !== undefined ? { expireAfterSeconds } : {}), ...(partialFilterExpression ? { partialFilterExpression } : {}) })),
      missing: missing.map(({ key, unique, sparse, expireAfterSeconds, partialFilterExpression }) => ({ key, unique: !!unique, sparse: !!sparse, ...(expireAfterSeconds !== undefined ? { expireAfterSeconds } : {}), ...(partialFilterExpression ? { partialFilterExpression } : {}) })) });
   } catch(e) { report.indexes.push({ model: name, collectionExists: e.code === 26 ? false : null, inspected: false, category: e.code === 26 ? 'namespace_missing' : category(e) }); }
  }
 } catch(e) { report.error = { category: category(e), name: /^[A-Za-z]+$/.test(e.name || '') ? e.name : 'Error' }; }
 finally {
  if (conn) await conn.close().catch(() => {});
  const output = JSON.stringify(report, null, 2);
  const destination = path.resolve(__dirname, '../../verification/mongo-readonly.json');
  fs.writeFileSync(destination, output + '\n');
  console.log(output);
  if (!report.mongo.connected) process.exitCode = 1;
 }
})();
