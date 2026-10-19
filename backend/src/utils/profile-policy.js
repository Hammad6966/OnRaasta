exports.skills = ['Engine Repair', 'Tyre Change', 'Battery', 'Brakes', 'AC Repair', 'Electrical', 'Body Work', 'Towing', 'Tyre Specialist', 'Auto Electrician', 'Engine Specialist', 'General Mechanic', 'Brake Specialist', 'Transmission Specialist', 'AC Specialist', 'Suspension Specialist'];

// Account eligibility and document evidence are deliberately independent.
exports.approvalStatus = m => m.isApproved ? 'approved' : ['rejected', 'revoked'].includes(m.approval?.status) ? m.approval.status : 'pending';
