const tags = Object.freeze(['Professional', 'On Time', 'Fair Price', 'Quality Work', 'Friendly', 'Clean Work', 'Skilled', 'Fast Service']);
const clean = text => text.replace(/<[^>]*>/g, '').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '').trim();
module.exports = { tags, clean };
