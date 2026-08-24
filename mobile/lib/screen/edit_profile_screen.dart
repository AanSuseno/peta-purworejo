import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/auth_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _kecamatanCtrl;
  late final TextEditingController _interestsCtrl;

  // Simpan tipe data asli "interests" dari server (List atau String)
  // supaya waktu dikirim balik formatnya tetap sama seperti yang backend
  // harapkan.
  bool _interestsWasList = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().userData ?? {};

    final rawInterests = user['interests'];
    _interestsWasList = rawInterests is List;
    final interestsText = rawInterests is List
        ? rawInterests.map((e) => e.toString()).join(', ')
        : (rawInterests?.toString() ?? '');

    _nameCtrl = TextEditingController(text: user['full_name'] ?? '');
    _phoneCtrl = TextEditingController(text: user['phone_number'] ?? '');
    _bioCtrl = TextEditingController(text: user['bio'] ?? '');
    _kecamatanCtrl = TextEditingController(text: user['kecamatan'] ?? '');
    _interestsCtrl = TextEditingController(text: interestsText);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    _kecamatanCtrl.dispose();
    _interestsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    final interestsList = _interestsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final updates = <String, dynamic>{
      'full_name': _nameCtrl.text.trim(),
      'phone_number': _phoneCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
      'kecamatan': _kecamatanCtrl.text.trim(),
      'interests': _interestsWasList ? interestsList : _interestsCtrl.text.trim(),
    };

    try {
      await context.read<AuthProvider>().updateProfile(updates);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil berhasil diperbarui')),
      );
      Navigator.of(context).pop();
    } on ValidationException catch (e) {
      _showError(e.message);
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Gagal menyimpan perubahan: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text('Edit Profil', style: GoogleFonts.poppins()),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _FieldLabel('Nama Lengkap'),
            _StyledField(
              controller: _nameCtrl,
              hint: 'Masukkan nama lengkap',
              icon: Icons.badge_outlined,
              textCapitalization: TextCapitalization.words,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Nama tidak boleh kosong';
                }
                return null;
              },
            ),
            const SizedBox(height: 18),
            _FieldLabel('No. Telepon'),
            _StyledField(
              controller: _phoneCtrl,
              hint: 'Contoh: 08123456789',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 18),
            _FieldLabel('Kecamatan'),
            _StyledField(
              controller: _kecamatanCtrl,
              hint: 'Kecamatan domisili',
              icon: Icons.location_on_outlined,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 18),
            _FieldLabel('Bio'),
            _StyledField(
              controller: _bioCtrl,
              hint: 'Ceritakan sedikit tentang dirimu',
              icon: Icons.info_outline,
              maxLines: 3,
            ),
            const SizedBox(height: 18),
            _FieldLabel('Minat'),
            _StyledField(
              controller: _interestsCtrl,
              hint: 'Pisahkan dengan koma, mis: fotografi, hiking',
              icon: Icons.interests_outlined,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Simpan Perubahan',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Batal',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }
}

class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

  const _StyledField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      style: GoogleFonts.poppins(fontSize: 14.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
          fontSize: 14,
          color: Colors.grey.shade400,
        ),
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: maxLines > 1 ? 40 : 0),
          child: Icon(icon, color: Colors.blue.shade700, size: 20),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.blue.shade700, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade400),
        ),
      ),
    );
  }
}
