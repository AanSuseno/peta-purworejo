// middlewares/upload.middleware.js
import multer from "multer";
import path from "path";
import fs from "fs";

// Pastikan folder uploads ada
const uploadDir = "uploads";
if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir, { recursive: true });
}

// Konfigurasi storage
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        // Tentukan folder berdasarkan tipe file
        let folder = uploadDir;
        if (file.fieldname === 'logo' || file.fieldname === 'banner') {
            folder = path.join(uploadDir, 'communities');
        } else if (file.fieldname === 'profile_picture') {
            folder = path.join(uploadDir, 'profiles');
        }
        
        // Buat folder jika belum ada
        if (!fs.existsSync(folder)) {
            fs.mkdirSync(folder, { recursive: true });
        }
        
        cb(null, folder);
    },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + "-" + Math.round(Math.random() * 1E9);
        const ext = path.extname(file.originalname);
        const prefix = file.fieldname === 'logo' ? 'logo' : 
                       file.fieldname === 'banner' ? 'banner' : 'profile';
        cb(null, `${prefix}-${uniqueSuffix}${ext}`);
    }
});

// Filter file - hanya gambar
const fileFilter = (req, file, cb) => {
    const allowedTypes = /jpeg|jpg|png|gif|webp/;
    const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
    const mimetype = allowedTypes.test(file.mimetype);

    if (mimetype && extname) {
        return cb(null, true);
    } else {
        cb(new Error("Hanya file gambar yang diizinkan (jpeg, jpg, png, gif, webp)"));
    }
};

// Upload middleware
const upload = multer({
    storage: storage,
    limits: {
        fileSize: 5 * 1024 * 1024 // 5MB
    },
    fileFilter: fileFilter
});

// Middleware untuk upload logo (single file)
export const uploadCommunityLogo = upload.single("logo");

// Middleware untuk upload banner (single file)
export const uploadCommunityBanner = upload.single("banner");

// Middleware untuk upload profile picture
export const uploadProfilePicture = upload.single("profile_picture");

// Middleware untuk upload multiple (logo + banner sekaligus)
export const uploadCommunityMedia = upload.fields([
    { name: 'logo', maxCount: 1 },
    { name: 'banner', maxCount: 1 }
]);