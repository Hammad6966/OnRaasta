const mongoose = require('mongoose');
const { pipeline } = require('node:stream/promises');
const { Readable } = require('node:stream');
const multer = require('multer');
const sharp = require('sharp');
const fail = require('../utils/http-error');
const { sameId, idPattern } = require('./access.service');
const User = require('../models/User');

const MAX_BYTES = 8 * 1024 * 1024;
exports.upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: MAX_BYTES, files: 1, fields: 2, parts: 3 } }).single('file');
exports.validate = (file, pdf = false) => {
  if (!file?.buffer?.length || file.buffer.length > MAX_BYTES) throw fail(400, 'Choose a file up to 8 MB');
  const b = file.buffer;
  const mime = b.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])) ? 'image/png'
    : b[0] === 255 && b[1] === 216 && b[2] === 255 ? 'image/jpeg'
    : b.toString('ascii', 0, 4) === 'RIFF' && b.toString('ascii', 8, 12) === 'WEBP' ? 'image/webp'
    : pdf && b.toString('ascii', 0, 5) === '%PDF-' ? 'application/pdf' : null;
  if (!mime || file.mimetype !== mime) throw fail(400, pdf ? 'Use a valid JPG, PNG, WebP or PDF file' : 'Use a valid JPG, PNG or WebP image');
  return { mime, size: b.length, name: String(file.originalname || 'upload').replace(/[^a-zA-Z0-9_. -]/g, '_').slice(-100) };
};
exports.prepare = async (file, pdf = false) => {
  const info = exports.validate(file, pdf);
  if (info.mime === 'application/pdf') {
    if (!file.buffer.subarray(-1024).includes(Buffer.from('%%EOF'))) throw fail(400, 'Incomplete PDF file');
    return { ...info, buffer: file.buffer };
  }
  try {
    // Decode bounded images, strip location/EXIF metadata and re-encode.
    const buffer = await sharp(file.buffer, { limitInputPixels: 24000000, failOn: 'warning' })
      .rotate().resize({ width: 2400, height: 2400, fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: 90 }).toBuffer();
    return { mime: 'image/jpeg', name: info.name.replace(/\.[^.]*$/, '') + '.jpg', size: buffer.length, buffer };
  } catch { throw fail(400, 'Image is damaged or too large to decode'); }
};
function bucket() {
  if (!mongoose.connection.db) throw fail(503, 'File storage is unavailable');
  return new mongoose.mongo.GridFSBucket(mongoose.connection.db, { bucketName: 'privateUploads' });
}
// Exported storage boundary supports controlled tests without external storage.
exports.store = async (buffer, metadata) => {
  const stream = bucket().openUploadStream(metadata.name, { metadata });
  await pipeline(Readable.from(buffer), stream);
  return stream.id;
};
exports.find = async id => (await bucket().find({ _id: new mongoose.Types.ObjectId(id) }).limit(1).toArray())[0];
exports.stream = async (file, res) => {
  res.set({ 'Content-Type': file.metadata.mime, 'Content-Length': String(file.length),
    'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': "default-src 'none'; sandbox",
    'Content-Disposition': `inline; filename="${file.metadata.name}"` });
  await pipeline(bucket().openDownloadStream(file._id), res);
};
exports.privateFile = async (req, res, next) => {
  try {
    if (!idPattern.test(req.params.id || '')) throw fail(400, 'Invalid file ID');
    const file = await exports.find(req.params.id);
    if (!file || file.metadata?.purpose !== 'document' || !(req.user.role === 'admin' || sameId(file.metadata.ownerId, req.user.id))) throw fail(404, 'Document not found');
    await exports.stream(file, res);
  } catch (e) { next(e); }
};
exports.uploadPhoto = async (req, res, next) => {
  try {
    const { buffer, ...info } = await exports.prepare(req.file);
    const fileId = await exports.store(buffer, { ...info, purpose: 'avatar', ownerId: req.user.id });
    const user = await User.findOneAndUpdate({ _id: req.user.id, isActive: true, isVerified: true }, { $set: { photo: { fileId, updatedAt: new Date() } }, $inc: { __v: 1 } }, { new: true });
    if (!user) throw fail(403, 'Account unavailable');
    res.json({ success: true, data: { photo: user.photo } });
  } catch (e) { next(e); }
};
exports.avatar = async (req, res, next) => {
  try {
    if (!idPattern.test(req.params.id || '')) throw fail(400, 'Invalid account ID');
    const user = await User.findOne({ _id: req.params.id, isActive: true, isVerified: true }).select('photo');
    if (!user?.photo?.fileId) throw fail(404, 'Profile photo unavailable');
    const file = await exports.find(user.photo.fileId);
    if (!file || file.metadata.purpose !== 'avatar') throw fail(404, 'Profile photo unavailable');
    await exports.stream(file, res);
  } catch (e) { next(e); }
};
