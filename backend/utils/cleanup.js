// utils/cleanup.js
import fs from "fs";
import path from "path";
import { promisify } from "util";
import prisma from "../lib/prisma.js";

const readdir = promisify(fs.readdir);
const stat = promisify(fs.stat);
const unlink = promisify(fs.unlink);
const rmdir = promisify(fs.rmdir);

/**
 * Ambil semua file dari database
 */
async function getFilesFromDatabase() {
    const filePaths = new Set();

    // 1. Profile pictures dari users
    const users = await prisma.users.findMany({
        select: { profile_picture: true },
        where: { profile_picture: { not: null } }
    });
    users.forEach(u => {
        if (u.profile_picture) {
            // Simpan dalam berbagai format untuk perbandingan
            const normalized = normalizePath(u.profile_picture);
            filePaths.add(normalized);
            filePaths.add(path.basename(normalized));
            // Tambahkan dengan prefix uploads/
            if (!normalized.startsWith('uploads/')) {
                filePaths.add(`uploads/${normalized}`);
            }
        }
    });

    // 2. Logo dari communities
    const communities = await prisma.communities.findMany({
        select: { logo: true, banner: true },
        where: { OR: [{ logo: { not: null } }, { banner: { not: null } }] }
    });
    communities.forEach(c => {
        if (c.logo) {
            const normalized = normalizePath(c.logo);
            filePaths.add(normalized);
            filePaths.add(path.basename(normalized));
            if (!normalized.startsWith('uploads/')) {
                filePaths.add(`uploads/${normalized}`);
            }
        }
        if (c.banner) {
            const normalized = normalizePath(c.banner);
            filePaths.add(normalized);
            filePaths.add(path.basename(normalized));
            if (!normalized.startsWith('uploads/')) {
                filePaths.add(`uploads/${normalized}`);
            }
        }
    });

    // 3. Post media
    const postMedia = await prisma.post_media.findMany({
        select: { media_url: true }
    });
    postMedia.forEach(pm => {
        if (pm.media_url) {
            const normalized = normalizePath(pm.media_url);
            filePaths.add(normalized);
            filePaths.add(path.basename(normalized));
            if (!normalized.startsWith('uploads/')) {
                filePaths.add(`uploads/${normalized}`);
            }
        }
    });

    // 4. Donation proof images
    const donations = await prisma.donations.findMany({
        select: { proof_image: true, goods_photo: true },
        where: { OR: [{ proof_image: { not: null } }, { goods_photo: { not: null } }] }
    });
    donations.forEach(d => {
        if (d.proof_image) {
            const normalized = normalizePath(d.proof_image);
            filePaths.add(normalized);
            filePaths.add(path.basename(normalized));
            if (!normalized.startsWith('uploads/')) {
                filePaths.add(`uploads/${normalized}`);
            }
        }
        if (d.goods_photo) {
            const normalized = normalizePath(d.goods_photo);
            filePaths.add(normalized);
            filePaths.add(path.basename(normalized));
            if (!normalized.startsWith('uploads/')) {
                filePaths.add(`uploads/${normalized}`);
            }
        }
    });

    console.log(`📁 Found ${filePaths.size} unique file references in database`);
    console.log("📋 Sample DB files:", Array.from(filePaths).slice(0, 5));
    
    return filePaths;
}

function normalizePath(filePath) {
    if (!filePath) return '';
    // Remove leading slash
    let normalized = filePath.replace(/^\/+/, '');
    // Remove query parameters
    if (normalized.includes('?')) {
        normalized = normalized.split('?')[0];
    }
    return normalized;
}

/**
 * Scan dan hapus file yang tidak terpakai
 */
async function scanAndDelete(dirPath, dbFiles, relativePath = '') {
    const result = {
        deletedFiles: 0,
        deletedFolders: 0,
        errors: [],
        deletedItems: []
    };

    try {
        const files = await readdir(dirPath);

        for (const file of files) {
            const fullPath = path.join(dirPath, file);
            const relativeFilePath = path.join(relativePath, file);
            const fileStat = await stat(fullPath);

            if (fileStat.isDirectory()) {
                // Skip folder uploads/profiles dan uploads/communities jika tidak kosong
                if (relativeFilePath === 'profiles' || relativeFilePath === 'communities') {
                    // Jangan hapus folder utama
                    const subResult = await scanAndDelete(fullPath, dbFiles, relativeFilePath);
                    result.deletedFiles += subResult.deletedFiles;
                    result.deletedFolders += subResult.deletedFolders;
                    result.errors.push(...subResult.errors);
                    result.deletedItems.push(...subResult.deletedItems);
                    continue;
                }

                const subResult = await scanAndDelete(fullPath, dbFiles, relativeFilePath);
                result.deletedFiles += subResult.deletedFiles;
                result.deletedFolders += subResult.deletedFolders;
                result.errors.push(...subResult.errors);
                result.deletedItems.push(...subResult.deletedItems);

                // Hapus folder kosong (tapi jangan hapus folder utama)
                const remainingFiles = await readdir(fullPath);
                if (remainingFiles.length === 0 && 
                    relativeFilePath !== 'profiles' && 
                    relativeFilePath !== 'communities') {
                    await rmdir(fullPath);
                    result.deletedFolders++;
                    result.deletedItems.push({
                        path: relativeFilePath,
                        type: 'folder',
                        reason: 'Empty folder'
                    });
                    console.log(`🗑️ Deleted empty folder: ${relativeFilePath}`);
                }
            } else {
                // Cek apakah file terdaftar di database
                const isInDb = checkIfFileInDb(relativeFilePath, file, dbFiles);
                
                if (!isInDb) {
                    try {
                        await unlink(fullPath);
                        result.deletedFiles++;
                        result.deletedItems.push({
                            path: relativeFilePath,
                            type: 'file',
                            reason: 'Not in database'
                        });
                        console.log(`🗑️ Deleted: ${relativeFilePath}`);
                    } catch (err) {
                        const errorMsg = `Failed to delete ${relativeFilePath}: ${err.message}`;
                        result.errors.push(errorMsg);
                        console.error(`❌ ${errorMsg}`);
                    }
                } else {
                    console.log(`✅ Kept: ${relativeFilePath} (in database)`);
                }
            }
        }
    } catch (error) {
        result.errors.push(`Error scanning ${dirPath}: ${error.message}`);
    }

    return result;
}

/**
 * Cek apakah file terdaftar di database dengan berbagai format
 */
function checkIfFileInDb(relativeFilePath, fileName, dbFiles) {
    // Format yang mungkin disimpan di database
    const formats = [
        relativeFilePath,                          // "profiles/image.jpg"
        `uploads/${relativeFilePath}`,             // "uploads/profiles/image.jpg"
        `/${relativeFilePath}`,                    // "/profiles/image.jpg"
        `uploads/${relativeFilePath}`,             // "uploads/profiles/image.jpg"
        relativeFilePath.replace(/^uploads\//, ''), // Tanpa prefix uploads/
        fileName,                                   // "image.jpg"
        `profiles/${fileName}`,                    // "profiles/image.jpg"
        `communities/${fileName}`,                 // "communities/image.jpg"
        `uploads/profiles/${fileName}`,            // "uploads/profiles/image.jpg"
        `uploads/communities/${fileName}`,         // "uploads/communities/image.jpg"
    ];

    for (const format of formats) {
        if (dbFiles.has(format)) {
            return true;
        }
    }

    return false;
}

/**
 * Main function untuk cleanup
 */
export async function cleanupUnusedFiles() {
    const uploadDir = path.join(process.cwd(), "uploads");
    
    if (!fs.existsSync(uploadDir)) {
        return { success: false, message: "Uploads folder not found" };
    }

    console.log("📊 Fetching files from database...");
    const dbFiles = await getFilesFromDatabase();
    console.log(`📁 Found ${dbFiles.size} files in database`);

    console.log("🔍 Scanning uploads folder...");
    const result = await scanAndDelete(uploadDir, dbFiles, '');

    return {
        success: true,
        message: "Cleanup completed",
        deletedFiles: result.deletedFiles,
        deletedFolders: result.deletedFolders,
        deletedItems: result.deletedItems,
        errors: result.errors
    };
}

/**
 * Statistik file (tanpa delete)
 */
export async function getFileStats() {
    const uploadDir = path.join(process.cwd(), "uploads");
    
    if (!fs.existsSync(uploadDir)) {
        return { success: false, message: "Uploads folder not found" };
    }

    const dbFiles = await getFilesFromDatabase();
    let totalFiles = 0;
    let inDatabase = 0;
    let notInDatabase = 0;
    const details = [];

    async function countFiles(dirPath, relativePath = '') {
        const files = await readdir(dirPath);
        for (const file of files) {
            const fullPath = path.join(dirPath, file);
            const relativeFilePath = path.join(relativePath, file);
            const fileStat = await stat(fullPath);
            
            if (fileStat.isDirectory()) {
                await countFiles(fullPath, relativeFilePath);
            } else {
                totalFiles++;
                const isInDb = checkIfFileInDb(relativeFilePath, file, dbFiles);
                if (isInDb) {
                    inDatabase++;
                } else {
                    notInDatabase++;
                    details.push({
                        path: relativeFilePath,
                        reason: 'Not in database'
                    });
                }
            }
        }
    }

    await countFiles(uploadDir, '');

    return {
        success: true,
        totalFiles,
        inDatabase,
        notInDatabase,
        details: details.slice(0, 20) // Batasi 20 file pertama
    };
}