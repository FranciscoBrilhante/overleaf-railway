#!/bin/bash
# Checks whether this Overleaf container can reach MongoDB and Redis.
# Run inside the overleaf container:  bash /overleaf-check-connections.sh
cd /overleaf/services/web && node - <<'JS'
const dns = require('dns').promises
const net = require('net')
const { MongoClient } = require('mongodb')

const mongoUrl = process.env.OVERLEAF_MONGO_URL
const redisHost = process.env.OVERLEAF_REDIS_HOST || process.env.REDIS_HOST
const redisPort = Number(process.env.OVERLEAF_REDIS_PORT || process.env.REDIS_PORT || 6379)
const ok = m => console.log('  OK   ' + m)
const bad = m => console.log('  FAIL ' + m)

function tcp(host, port, family) {
  return new Promise(resolve => {
    const s = net.connect({ host, port, family, timeout: 5000 })
    s.on('connect', () => { s.destroy(); resolve(null) })
    s.on('timeout', () => { s.destroy(); resolve(new Error('timeout')) })
    s.on('error', e => resolve(e))
  })
}

function redisPing(host, port) {
  // family 4 because Overleaf's Redis client (ioredis) only uses IPv4
  return new Promise(resolve => {
    const s = net.connect({ host, port, family: 4, timeout: 5000 })
    let buf = ''
    s.on('connect', () => s.write('PING\r\n'))
    s.on('data', d => { buf += d; s.destroy(); resolve(buf.trim()) })
    s.on('timeout', () => { s.destroy(); resolve('timeout') })
    s.on('error', e => resolve(e.code || e.message))
  })
}

async function checkDns(host) {
  try {
    const all = await dns.lookup(host, { all: true })
    ok(`DNS ${host} -> ${all.map(a => a.address).join(', ')}`)
    if (!all.some(a => a.family === 4)) bad(`${host} has no IPv4 address (Overleaf's Redis client needs IPv4)`)
    return true
  } catch (e) { bad(`DNS ${host}: ${e.code || e.message}`); return false }
}

;(async () => {
  console.log('Environment:')
  console.log('  OVERLEAF_MONGO_URL  =', mongoUrl)
  console.log('  OVERLEAF_REDIS_HOST =', process.env.OVERLEAF_REDIS_HOST)
  console.log('  REDIS_HOST          =', process.env.REDIS_HOST)

  console.log('\nMongoDB:')
  if (!mongoUrl) { bad('OVERLEAF_MONGO_URL is not set') } else {
    const u = new URL(mongoUrl)
    const host = u.hostname, port = Number(u.port || 27017)
    if (await checkDns(host)) {
      const e = await tcp(host, port)
      e ? bad(`TCP ${host}:${port}: ${e.code || e.message}`) : ok(`TCP ${host}:${port} open`)
    }
    // 1) talk to this one server directly, show replica set config
    let c = new MongoClient(mongoUrl, { directConnection: true, serverSelectionTimeoutMS: 5000 })
    try {
      await c.connect()
      const h = await c.db('admin').command({ hello: 1 })
      ok(`connected directly; replica set = ${h.setName || '(none)'}, members = ${JSON.stringify(h.hosts || [])}, primary = ${h.isWritablePrimary}`)
      if (!h.setName) bad('mongod is not running as a replica set (it was not started with --replSet / not initialised)')
      else if (/directConnection=true/i.test(mongoUrl)) ok('OVERLEAF_MONGO_URL uses directConnection=true, so the member address does not need to resolve from here')
      else if (!(h.hosts || []).includes(`${host}:${port}`)) bad(`replica set member is ${JSON.stringify(h.hosts)} but OVERLEAF_MONGO_URL uses ${host}:${port}. Overleaf will try to reach the member address. Add ?directConnection=true to OVERLEAF_MONGO_URL.`)
    } catch (e) { bad(`direct connection: ${e.message}`) } finally { await c.close().catch(() => {}) }
    // 2) connect the way Overleaf does (follows the replica set)
    c = new MongoClient(mongoUrl, { serverSelectionTimeoutMS: 8000 })
    try {
      await c.connect()
      await c.db().command({ ping: 1 })
      ok('connected like Overleaf does (replica set discovery) and ping succeeded')
    } catch (e) { bad(`Overleaf-style connection: ${e.message}`) } finally { await c.close().catch(() => {}) }
  }

  console.log('\nRedis:')
  if (!redisHost) { bad('OVERLEAF_REDIS_HOST / REDIS_HOST not set') } else if (await checkDns(redisHost)) {
    const r = await redisPing(redisHost, redisPort)
    r === '+PONG' ? ok(`PING ${redisHost}:${redisPort} over IPv4 -> PONG`) : bad(`PING ${redisHost}:${redisPort} over IPv4 -> ${r}`)
  }
})()
JS
