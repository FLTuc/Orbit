// Lecture et ecriture de fichiers zip, sans bibliotheque : pour echanger avec Orbit PC
// (son menu « Autre PC > Exporter / Importer » produit et lit des zip).
// Securite : taille maximale du zip et de chaque fichier decompresse (pas de « bombe zip »),
// seuls les fichiers attendus sont lus, et leur contenu est ensuite verifie par store.js.
'use strict';

export const MAX_ZIP = 50 * 1024 * 1024;     // zip de 50 Mo au plus
export const MAX_ENTRY = 8 * 1024 * 1024;    // chaque fichier lu : 8 Mo au plus une fois decompresse

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
export function crc32(bytes) {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}

async function inflateRaw(data, limit) {
  const ds = new DecompressionStream('deflate-raw');
  const writer = ds.writable.getWriter();
  writer.write(data).catch(() => {});
  writer.close().catch(() => {});
  const reader = ds.readable.getReader();
  const parts = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > limit) { await reader.cancel().catch(() => {}); throw new Error('fichier trop gros une fois décompressé'); }
    parts.push(value);
  }
  const out = new Uint8Array(total);
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}

// Lit les fichiers d'un zip dont le nom (sans dossier) est dans `wanted`.
// Renvoie { 'kanban.json': '...texte...', ... } ; le premier trouve gagne.
export async function readZip(buffer, wanted) {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  if (bytes.length > MAX_ZIP) throw new Error('zip trop gros');
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  // fin du repertoire central (cherchee a la fin, commentaire de 64 Ko au plus)
  let eocd = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 22 - 65535); i--) {
    if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error("ce fichier n'est pas un zip");
  const count = dv.getUint16(eocd + 10, true);
  let p = dv.getUint32(eocd + 16, true);
  if (count > 5000 || p >= bytes.length) throw new Error('zip abîmé');
  const want = new Set(wanted);
  const out = {};
  const dec = new TextDecoder('utf-8');
  for (let n = 0; n < count; n++) {
    if (p + 46 > bytes.length || dv.getUint32(p, true) !== 0x02014b50) throw new Error('zip abîmé');
    const method = dv.getUint16(p + 10, true);
    const csize = dv.getUint32(p + 20, true);
    const usize = dv.getUint32(p + 24, true);
    const nlen = dv.getUint16(p + 28, true), xlen = dv.getUint16(p + 30, true), clen = dv.getUint16(p + 32, true);
    const local = dv.getUint32(p + 42, true);
    const name = dec.decode(bytes.subarray(p + 46, p + 46 + nlen)).replace(/\\/g, '/');
    p += 46 + nlen + xlen + clen;
    const base = name.split('/').pop();
    if (!want.has(base) || base in out) continue;
    if (usize > MAX_ENTRY || csize > MAX_ZIP) throw new Error(`${base} : trop gros`);
    if (local + 30 > bytes.length || dv.getUint32(local, true) !== 0x04034b50) throw new Error('zip abîmé');
    const start = local + 30 + dv.getUint16(local + 26, true) + dv.getUint16(local + 28, true);
    if (start + csize > bytes.length) throw new Error('zip abîmé');
    const raw = bytes.subarray(start, start + csize);
    let data;
    if (method === 0) data = raw;
    else if (method === 8) data = await inflateRaw(raw, MAX_ENTRY);
    else throw new Error(`${base} : compression non prise en charge`);
    out[base] = dec.decode(data);
  }
  return out;
}

// Ecrit un zip (fichiers stockes sans compression) : { 'donnees/kanban.json': 'texte', ... }
export function writeZip(files, date = new Date()) {
  const enc = new TextEncoder();
  const time = ((date.getHours() << 11) | (date.getMinutes() << 5) | (date.getSeconds() >> 1)) & 0xFFFF;
  const day = (((date.getFullYear() - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate()) & 0xFFFF;
  const locals = [], centrals = [];
  let offset = 0;
  for (const [name, text] of Object.entries(files)) {
    const nameB = enc.encode(name);
    const data = enc.encode(text);
    const crc = crc32(data);
    const lh = new Uint8Array(30 + nameB.length);
    const l = new DataView(lh.buffer);
    l.setUint32(0, 0x04034b50, true); l.setUint16(4, 20, true); l.setUint16(6, 0x0800, true);   // noms en UTF-8
    l.setUint16(8, 0, true); l.setUint16(10, time, true); l.setUint16(12, day, true);
    l.setUint32(14, crc, true); l.setUint32(18, data.length, true); l.setUint32(22, data.length, true);
    l.setUint16(26, nameB.length, true); l.setUint16(28, 0, true);
    lh.set(nameB, 30);
    const ch = new Uint8Array(46 + nameB.length);
    const c = new DataView(ch.buffer);
    c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint16(8, 0x0800, true);
    c.setUint16(10, 0, true); c.setUint16(12, time, true); c.setUint16(14, day, true);
    c.setUint32(16, crc, true); c.setUint32(20, data.length, true); c.setUint32(24, data.length, true);
    c.setUint16(28, nameB.length, true); c.setUint32(42, offset, true);
    ch.set(nameB, 46);
    locals.push(lh, data);
    centrals.push(ch);
    offset += lh.length + data.length;
  }
  const csize = centrals.reduce((a, b) => a + b.length, 0);
  const end = new Uint8Array(22);
  const e = new DataView(end.buffer);
  e.setUint32(0, 0x06054b50, true); e.setUint16(8, centrals.length, true); e.setUint16(10, centrals.length, true);
  e.setUint32(12, csize, true); e.setUint32(16, offset, true);
  const all = [...locals, ...centrals, end];
  const out = new Uint8Array(all.reduce((a, b) => a + b.length, 0));
  let o = 0;
  for (const part of all) { out.set(part, o); o += part.length; }
  return out;
}
