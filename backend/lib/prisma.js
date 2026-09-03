import "dotenv/config";
import { PrismaClient } from '@prisma/client';
import { PrismaPg } from "@prisma/adapter-pg";
import pg from 'pg';

const { Pool } = pg;

// 1. Buat connection pool dari library 'pg'
const connectionString = process.env.DATABASE_URL;
const pool = new Pool({ 
  connectionString,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false 
});

// 2. Masukkan pool ke dalam adapter Prisma
const adapter = new PrismaPg(pool);

// 3. Inisialisasi PrismaClient dengan adapter
const prisma = new PrismaClient({ adapter });

export default prisma;