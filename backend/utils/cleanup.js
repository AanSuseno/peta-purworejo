// utils/cleanup.js
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import prisma from "../lib/prisma.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const uploadDir = path.join(__dirname, "..", "uploads");

// Konfigurasi tiap folder upload: lokasi di disk + cara ambil file yang
// masih dipakai dari database, sesuai skema Prisma.
const FOLDER_CONFIG = {
  profiles: {
    dir: path.join(uploadDir, "profiles"),
    getUsedFiles: async () => {
      const rows = await prisma.users.findMany({
        where: { profile_picture: { not: null } },
        select: { profile_picture: true },
      });
      return rows.map((r) => r.profile_picture);
    },
  },
  communities: {
    dir: path.join(uploadDir, "communities"),
    getUsedFiles: async () => {
      const rows = await prisma.communities.findMany({
        where: { OR: [{ logo: { not: null } }, { banner: { not: null } }] },
        select: { logo: true, banner: true },
      });
      const files = [];
      rows.forEach((r) => {
        if (r.logo) files.push(r.logo);
        if (r.banner) files.push(r.banner);
      });
      return files;
    },
  },
  donations: {
    dir: path.join(uploadDir, "donations"),
    getUsedFiles: async () => {
      const rows = await prisma.donations.findMany({
        where: { proof_image: { not: null } },
        select: { proof_image: true },
      });
      return rows.map((r) => r.proof_image);
    },
  },
  distributions: {
    dir: path.join(uploadDir, "distributions"),
    getUsedFiles: async () => {
      const rows = await prisma.distribution_evidences.findMany({
        select: { evidence_url: true },
      });
      return rows.map((r) => r.evidence_url);
    },
  },
};

// Nilai di DB bisa berupa "namafile.jpg", "/uploads/profiles/namafile.jpg",
// atau URL lengkap. Kita ambil basename-nya saja agar bisa dicocokkan
// dengan nama file fisik di disk.
function extractFilename(value) {
  if (!value) return null;
  const clean = String(value).split("?")[0];
  return path.basename(clean);
}

function getFilesInDir(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((f) => {
    try {
      return fs.statSync(path.join(dir, f)).isFile();
    } catch {
      return false;
    }
  });
}

function formatBytes(bytes) {
  if (!bytes) return "0 B";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${(bytes / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`;
}

export async function getFileStats() {
  const folders = {};
  let totalFiles = 0;
  let totalSize = 0;
  let totalUnused = 0;

  for (const [name, config] of Object.entries(FOLDER_CONFIG)) {
    const filesOnDisk = getFilesInDir(config.dir);
    const usedValues = await config.getUsedFiles();
    const usedFilenames = new Set(usedValues.map(extractFilename).filter(Boolean));

    let folderSize = 0;
    const unusedFiles = [];

    filesOnDisk.forEach((file) => {
      const size = fs.statSync(path.join(config.dir, file)).size;
      folderSize += size;
      if (!usedFilenames.has(file)) unusedFiles.push(file);
    });

    folders[name] = {
      total_files: filesOnDisk.length,
      total_size: formatBytes(folderSize),
      used_files: filesOnDisk.length - unusedFiles.length,
      unused_files: unusedFiles.length,
      unused_file_names: unusedFiles,
    };

    totalFiles += filesOnDisk.length;
    totalSize += folderSize;
    totalUnused += unusedFiles.length;
  }

  return {
    success: true,
    summary: {
      total_files: totalFiles,
      total_size: formatBytes(totalSize),
      total_unused_files: totalUnused,
    },
    folders,
  };
}

export async function cleanupUnusedFiles() {
  const details = {};
  const errors = [];
  let totalDeleted = 0;
  let totalFreedBytes = 0;

  for (const [name, config] of Object.entries(FOLDER_CONFIG)) {
    const filesOnDisk = getFilesInDir(config.dir);
    const usedValues = await config.getUsedFiles();
    const usedFilenames = new Set(usedValues.map(extractFilename).filter(Boolean));

    const deleted = [];
    let freedBytes = 0;

    for (const file of filesOnDisk) {
      if (usedFilenames.has(file)) continue;
      const filePath = path.join(config.dir, file);
      try {
        const size = fs.statSync(filePath).size;
        fs.unlinkSync(filePath);
        deleted.push(file);
        freedBytes += size;
      } catch (err) {
        errors.push({ folder: name, file, error: err.message });
      }
    }

    details[name] = {
      deleted_count: deleted.length,
      deleted_files: deleted,
      freed_space: formatBytes(freedBytes),
    };

    totalDeleted += deleted.length;
    totalFreedBytes += freedBytes;
  }

  return {
    success: true,
    summary: {
      total_deleted: totalDeleted,
      total_freed_space: formatBytes(totalFreedBytes),
    },
    details,
    ...(errors.length ? { errors } : {}),
  };
}