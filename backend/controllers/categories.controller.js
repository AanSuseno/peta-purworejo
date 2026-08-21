import prisma from "../lib/prisma.js";

export const getAllCategories = async (req, res) => {
    try {
        const categories = await prisma.categories.findMany({
            orderBy: {
                category_name: "asc"
            },
            include: {
                _count: {
                    select: {
                        communities: true
                    }
                }
            }
        });

        return res.json({
            success: true,
            data: categories,
            total: categories.length

        });
    } catch (error) {
        console.error("Error fetching categories:", error);
        return res.status(500).json({
            success: false,
            message: "Terjadi kesalahan saat mengambil data kategori",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        })
    }
}

export const getCategoryById = async (req, res) => {
    try {
        const { id } = req.params;

        const category = await prisma.categories.findUnique({
            where: {
                category_id: parseInt(id)
            },
            include: {
                communities: {
                    select: {
                        community_id: true,
                        community_name: true,
                        community_slug: true,
                        logo: true,
                        total_members: true,
                        total_score: true,
                        is_verified: true,
                    },
                    where: {
                        is_active: true
                    },
                    orderBy: {
                        total_members: "desc"
                    },
                    take: 10
                },
                _count: {
                    select: {
                        communities: true
                    }
                }
            }
        });

        if (!category) {
            return res.status(404).json({
                success: false,
                message: "Kategori tidak ditemukan"
            });
        }

        return res.json({
            success: true,
            data: category
        });
    } catch (error) {
        console.error("Error fetching category:", error);
        return res.status(500).json({
            success: false,
            message: "Terjadi kesalahan saat mengambil data kategori",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
}

export const createCategory = async (req, res) => {
    try {
        const { category_name, category_icon, category_description } = req.body;

        if (!category_name || category_name.trim() === "") {
            return res.status(400).json({
                success: false,
                message: "Nama kategori tidak boleh kosong"
            });
        }

        const existingCategory = await prisma.categories.findUnique({
            where: {
                category_name: category_name
            }
        });
        if (existingCategory) {
            return res.status(409).json({
                success: false,
                message: "Nama kategori sudah ada"
            });
        }

        const newCategory = await prisma.categories.create({
            data: {
                category_name: category_name,
                category_icon: category_icon || null,
                category_description: category_description || null,
                created_at: new Date(),
            }
        });

        return res.status(201).json({
            success: true,
            message: "Kategori berhasil dibuat",
            data: newCategory
        });
    } catch (error) {
        console.error("Error creating category:", error);
        return res.status(500).json({
            success: false,
            message: "Terjadi kesalahan saat membuat kategori",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
}

export const updateCategory = async (req, res) => {
    try {
        const {id} = req.params;
        const {category_name, category_icon, category_description} = req.body;

        const existingCategory = await prisma.categories.findUnique({
            where: {
                category_id: parseInt(id)
            }
        });

        if(!existingCategory) {
            return res.status(404).json({
                success: false,
                message: "Kategori tidak ditemukan"
            });
        }

        if(category_name && category_name.trim() !== existingCategory.category_name) {
            const duplicateCheck = await prisma.categories.findUnique({
                where: {
                    category_name: category_name.trim()
                }
            });

            if (duplicateCheck) {
                return res.status(409).json({
                    success: false,
                    message: "Nama kategori sudah ada"
                });
            }
        }

        const updatedCategory = await prisma.categories.update({
            where: {
                category_id: parseInt(id)
            },
            data: {
                category_name:  category_name ? category_name.trim() : existingCategory.category_name,
                category_icon: category_icon !== undefined ? category_icon : existingCategory.category_icon,
                category_description: category_description !== undefined ? category_description : existingCategory.category_description,
            }
        });

        return res.json({
            success: true,
            message: "Kategori berhasil diperbarui",
            data: updatedCategory
        });
    } catch (error) {
        console.error("Error updating category:", error);
        return res.status(500).json({
            success: false,
            message: "Terjadi kesalahan saat memperbarui kategori",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
}

export const deleteCategory = async (req, res) => {
    try {
        const {id} = req.params;

        const category = await prisma.categories.findUnique({
            where: {
                category_id: parseInt(id)
            },
            include: {
                _count: {
                    select: {
                        communities: true
                    }
                }
            }
        });

        if(!category) {
            return res.status(404).json({
                success: false,
                message: "Kategori tidak ditemukan"
            });
        }

        if (category._count.communities > 0) {
            return res.status(400).json({
                success: false,
                message: "Kategori tidak dapat dihapus karena masih memiliki komunitas terkait"
            });
        }

        await prisma.categories.delete({
            where: {
                category_id: parseInt(id)
            }
        });

        return res.json({
            success: true,
            message: "Kategori berhasil dihapus"
        });
    } catch (error) {
        console.error("Error deleting category:", error);
        return res.status(500).json({
            success: false,
            message: "Terjadi kesalahan saat menghapus kategori",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
}

export const searchCategories = async (req, res) => {
    try {
        const { q } = req.query;

        if (!q || q.trim() === "") {
            return res.status(400).json({
                success: false,
                message: "Query pencarian tidak boleh kosong"
            });
        }

        const categories = await prisma.categories.findMany({
            where: {
                OR: [
                    {
                        category_name: {
                            contains: q.trim(),
                            mode: "insensitive"
                        }
                    },
                    {
                        category_description: {
                            contains: q.trim(),
                            mode: "insensitive"
                        }
                    }
                ]
            },
            include: {
                _count: {
                    select: {
                        communities: true
                    }
                }
            },
            orderBy: {
                category_name: "asc"
            }
        });

        return res.status(200).json({
            success: true,
            data: categories,
            total: categories.length
        });
    } catch (error) {
        console.error("Error searching categories:", error);
        return res.status(500).json({
            success: false,
            message: "Terjadi kesalahan saat mencari kategori",
            error: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
}