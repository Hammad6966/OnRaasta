export interface Account {
  _id: string; name: string; email?: string; phone: string; role: string;
  isActive: boolean; isVerified: boolean; revision: number; createdAt?: string; updatedAt?: string;
  mechanic?: Mechanic | null;
}
export interface Mechanic {
  _id: string; userId: string; user?: Account; skills: string[]; serviceRadius: number;
  shopAddress?: string; isApproved: boolean; accountApprovalStatus: string; revision: number;
  createdAt?: string; updatedAt?: string;
  approval?: { method?: string; reason?: string; decidedAt?: string; decidedBy?: string };
  documents: { status: string; evidenceAvailable: boolean; verificationAvailable: boolean };
}
export interface AuditLog {
  _id: string; adminId: string; targetId: string; targetType: string; action: string;
  reason: string; createdAt: string; previous: object; next: object;
}
export interface Listing<T> { success: boolean; data: T[]; pagination: { page: number; limit: number; total: number; hasMore: boolean }; counts?: Record<string, number> }
