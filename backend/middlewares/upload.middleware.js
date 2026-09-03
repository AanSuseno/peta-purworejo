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

const postStorage = multer.diskStorage({
    destination: (req, file, cb) => {
        const folder = path.join(uploadDir, 'posts');
        if (!fs.existsSync(folder)) {
            fs.mkdirSync(folder, { recursive: true });
        }
        cb(null, folder);
    },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + "-" + Math.round(Math.random() * 1E9);
        const ext = path.extname(file.originalname);
        cb(null, `post-${uniqueSuffix}${ext}`);
    }
});

// Filter untuk post media (gambar & video)
const postFileFilter = (req, file, cb) => {
    const allowedTypes = /jpeg|jpg|png|gif|webp|mp4|mov|avi/;
    const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
    const mimetype = allowedTypes.test(file.mimetype);

    if (mimetype && extname) {
        return cb(null, true);
    } else {
        cb(new Error("Hanya file gambar (jpeg, jpg, png, gif, webp) dan video (mp4, mov, avi) yang diizinkan"));
    }
};

// Upload middleware untuk post media (multiple files)
const uploadPostMedia = multer({
    storage: postStorage,
    limits: {
        fileSize: 20 * 1024 * 1024 // 20MB untuk video
    },
    fileFilter: postFileFilter
});

export const handleUploadError = (err, req, res, next) => {
    if (err instanceof multer.MulterError) {
        let message = "Upload gagal";
        if (err.code === 'LIMIT_FILE_SIZE') {
            message = "Ukuran file terlalu besar";
        } else if (err.code === 'LIMIT_UNEXPECTED_FILE') {
            message = "Field file tidak sesuai dengan yang diharapkan";
        }
        return res.status(400).json({ success: false, message });
    }

    if (err) {
        // Error dari fileFilter, mis. "Hanya file gambar yang diizinkan..."
        return res.status(400).json({ success: false, message: err.message });
    }

    next();
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

export const uploadPostImages = uploadPostMedia.array("media", 10); // Max 10 files
export const uploadSinglePostImage = uploadPostMedia.single("media");

const donationStorage = multer.diskStorage({
    destination: (req, file, cb) => {
        const folder = path.join(uploadDir, 'donations');
        if (!fs.existsSync(folder)) {
            fs.mkdirSync(folder, { recursive: true });
        }
        cb(null, folder);
    },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + "-" + Math.round(Math.random() * 1E9);
        const ext = path.extname(file.originalname);
        cb(null, `donation-${uniqueSuffix}${ext}`);
    }
});

// Donation file filter
const donationFileFilter = (req, file, cb) => {
    const allowedTypes = /jpeg|jpg|png|gif|webp|pdf/;
    const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
    const mimetype = allowedTypes.test(file.mimetype);

    if (mimetype && extname) {
        return cb(null, true);
    } else {
        cb(new Error("Hanya file gambar (jpeg, jpg, png, gif, webp) dan PDF yang diizinkan"));
    }
};

// Donation upload middleware
const uploadDonation = multer({
    storage: donationStorage,
    limits: {
        fileSize: 10 * 1024 * 1024 // 10MB
    },
    fileFilter: donationFileFilter
});

export const uploadDonationProof = uploadDonation.single("proof_image");
export const uploadDonationGoodsPhoto = uploadDonation.single("goods_photo");

export const uploadDistributionEvidence = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => cb(null, "uploads/distributions/"),
    filename: (req, file, cb) => {
      cb(null, `${Date.now()}-${file.originalname}`);
    }
  })
}).array("evidence_images", 10);