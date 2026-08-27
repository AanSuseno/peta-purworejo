import prisma from "../../lib/prisma.js";

export const checkCommunityAdmin = async (communityId, userId) => {
    const admin = await prisma.community_admins.findFirst({
        where: {
            community_id: parseInt(communityId),
            user_id: userId
        }
    });
    
    if (admin) return { isAdmin: true, role: admin.role };
    
    // Check if user is founder from communities table
    const community = await prisma.communities.findUnique({
        where: { community_id: parseInt(communityId) },
        select: { founder_id: true }
    });
    
    if (community && community.founder_id === userId) {
        return { isAdmin: true, role: 'founder' };
    }
    
    return { isAdmin: false };
};

// Check if user is system admin
export const isSystemAdmin = async (userId) => {
    const user = await prisma.users.findUnique({
        where: { user_id: userId },
        include: { user_roles: true }
    });
    return user?.user_roles?.role_name?.toLowerCase() === 'system_admin';
};