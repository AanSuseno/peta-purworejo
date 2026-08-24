// lib/screens/create_post_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';
import '../services/posts_service.dart';

class CreatePostScreen extends StatefulWidget {
  final int communityId;
  final String communityName;

  const CreatePostScreen({
    super.key,
    required this.communityId,
    required this.communityName,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final PostsService _service = PostsService();
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  // Post type: "regular" atau "event"
  String _postType = 'regular';
  String _visibility = 'public';
  bool _isSubmitting = false;
  final List<File> _selectedFiles = [];

  // Event fields
  DateTime? _selectedEventDate;
  TimeOfDay? _selectedStartTime;
  TimeOfDay? _selectedEndTime;
  final _eventLocationController = TextEditingController();
  final _eventLatitudeController = TextEditingController();
  final _eventLongitudeController = TextEditingController();
  final _eventQuotaController = TextEditingController();
  final _eventRegistrationLinkController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _eventLocationController.dispose();
    _eventLatitudeController.dispose();
    _eventLongitudeController.dispose();
    _eventQuotaController.dispose();
    _eventRegistrationLinkController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 85);

    if (files.isNotEmpty) {
      setState(() {
        _selectedFiles.addAll(files.map((f) => File(f.path)));
      });
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  Future<void> _selectEventDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedEventDate = picked);
    }
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) {
      setState(() => _selectedStartTime = picked);
    }
  }

  Future<void> _selectEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
    );
    if (picked != null) {
      setState(() => _selectedEndTime = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Validasi event
    if (_postType == 'event' && _selectedEventDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tanggal event wajib diisi untuk event'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final token = await context.read<AuthProvider>().getToken();
    if (token == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesi tidak ditemukan, silakan login ulang'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      Map<String, dynamic> result;

      final eventDate = _selectedEventDate != null
          ? '${_selectedEventDate!.year}-${_selectedEventDate!.month.toString().padLeft(2, '0')}-${_selectedEventDate!.day.toString().padLeft(2, '0')}'
          : null;
      final startTime = _selectedStartTime != null
          ? '${_selectedStartTime!.hour.toString().padLeft(2, '0')}:${_selectedStartTime!.minute.toString().padLeft(2, '0')}:00'
          : null;
      final endTime = _selectedEndTime != null
          ? '${_selectedEndTime!.hour.toString().padLeft(2, '0')}:${_selectedEndTime!.minute.toString().padLeft(2, '0')}:00'
          : null;
      final latitude = _eventLatitudeController.text.isNotEmpty
          ? double.tryParse(_eventLatitudeController.text)
          : null;
      final longitude = _eventLongitudeController.text.isNotEmpty
          ? double.tryParse(_eventLongitudeController.text)
          : null;
      final quota = _eventQuotaController.text.isNotEmpty
          ? int.tryParse(_eventQuotaController.text)
          : null;

      if (_selectedFiles.isEmpty) {
        // Post text only
        result = await _service.createPost(
          token: token,
          communityId: widget.communityId,
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
          postType: _postType,
          visibility: _visibility,
          eventDate: eventDate,
          eventStartTime: startTime,
          eventEndTime: endTime,
          eventLocation: _eventLocationController.text.trim(),
          eventLatitude: latitude,
          eventLongitude: longitude,
          eventQuota: quota,
          eventRegistrationLink: _eventRegistrationLinkController.text.trim(),
        );
      } else {
        // Post with media
        result = await _service.createPostWithMedia(
          token: token,
          communityId: widget.communityId,
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
          postType: _postType,
          visibility: _visibility,
          files: _selectedFiles,
          eventDate: eventDate,
          eventStartTime: startTime,
          eventEndTime: endTime,
          eventLocation: _eventLocationController.text.trim(),
          eventLatitude: latitude,
          eventLongitude: longitude,
          eventQuota: quota,
          eventRegistrationLink: _eventRegistrationLinkController.text.trim(),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Postingan berhasil dibuat')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(
          'Buat Postingan',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info komunitas
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.groups, size: 20, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Memposting di ${widget.communityName}',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Tipe Postingan
              _fieldLabel('Tipe Postingan'),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: DropdownButtonHideUnderline(
                  child: DropdownButtonFormField<String>(
                    value: _postType,
                    isExpanded: true,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      color: Colors.black87,
                    ),
                    decoration: const InputDecoration(border: InputBorder.none),
                    items: const [
                      DropdownMenuItem(
                        value: 'regular',
                        child: Row(
                          children: [
                            Icon(Icons.article_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Postingan Biasa'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'event',
                        child: Row(
                          children: [
                            Icon(Icons.event_available_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Event'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _postType = value);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Visibility
              _fieldLabel('Visibilitas'),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: DropdownButtonHideUnderline(
                  child: DropdownButtonFormField<String>(
                    value: _visibility,
                    isExpanded: true,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      color: Colors.black87,
                    ),
                    decoration: const InputDecoration(border: InputBorder.none),
                    items: const [
                      DropdownMenuItem(
                        value: 'public',
                        child: Row(
                          children: [
                            Icon(Icons.public, size: 18),
                            SizedBox(width: 8),
                            Text('Publik'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'community_only',
                        child: Row(
                          children: [
                            Icon(Icons.groups, size: 18),
                            SizedBox(width: 8),
                            Text('Hanya Komunitas'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _visibility = value);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _fieldLabel('Judul *'),
              _textField(
                controller: _titleController,
                hint: 'Masukkan judul postingan',
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Judul wajib diisi'
                    : null,
              ),
              const SizedBox(height: 16),

              _fieldLabel('Konten'),
              _textField(
                controller: _contentController,
                hint: 'Tuliskan konten postingan...',
                maxLines: 6,
              ),
              const SizedBox(height: 16),

              // Event fields
              if (_postType == 'event') ...[
                _fieldLabel('Informasi Event'),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tanggal Event
                      GestureDetector(
                        onTap: _selectEventDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 14,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _selectedEventDate != null
                                      ? '${_selectedEventDate!.day}/${_selectedEventDate!.month}/${_selectedEventDate!.year}'
                                      : 'Pilih Tanggal Event *',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: _selectedEventDate != null
                                        ? Colors.black87
                                        : Colors.grey.shade400,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_drop_down,
                                color: Colors.grey.shade400,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Waktu Mulai & Selesai
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _selectStartTime,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 14,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _selectedStartTime != null
                                            ? _selectedStartTime!.format(
                                                context,
                                              )
                                            : 'Mulai',
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: _selectedStartTime != null
                                              ? Colors.black87
                                              : Colors.grey.shade400,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: _selectEndTime,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 14,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _selectedEndTime != null
                                            ? _selectedEndTime!.format(context)
                                            : 'Selesai',
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: _selectedEndTime != null
                                              ? Colors.black87
                                              : Colors.grey.shade400,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Lokasi
                      _textField(
                        controller: _eventLocationController,
                        hint: 'Lokasi event',
                        prefixIcon: Icons.location_on_outlined,
                      ),
                      const SizedBox(height: 10),

                      // Latitude & Longitude
                      Row(
                        children: [
                          Expanded(
                            child: _textField(
                              controller: _eventLatitudeController,
                              hint: 'Latitude',
                              prefixIcon: Icons.gps_fixed,
                              keyboardType: TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _textField(
                              controller: _eventLongitudeController,
                              hint: 'Longitude',
                              prefixIcon: Icons.gps_fixed,
                              keyboardType: TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Kuota
                      _textField(
                        controller: _eventQuotaController,
                        hint: 'Kuota peserta (kosongkan jika tidak terbatas)',
                        prefixIcon: Icons.people_outline,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 10),

                      // Link Pendaftaran
                      _textField(
                        controller: _eventRegistrationLinkController,
                        hint: 'Link pendaftaran eksternal (opsional)',
                        prefixIcon: Icons.link_outlined,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Upload File
              _fieldLabel('Media (Opsional)'),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    if (_selectedFiles.isNotEmpty)
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                        itemCount: _selectedFiles.length,
                        itemBuilder: (context, index) {
                          final file = _selectedFiles[index];
                          final isVideo =
                              file.path.toLowerCase().endsWith('.mp4') ||
                              file.path.toLowerCase().endsWith('.webm');
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: isVideo
                                    ? Container(
                                        color: Colors.black,
                                        child: Center(
                                          child: Icon(
                                            Icons.play_circle_outline,
                                            size: 40,
                                            color: Colors.white.withOpacity(
                                              0.7,
                                            ),
                                          ),
                                        ),
                                      )
                                    : Image.file(file, fit: BoxFit.cover),
                              ),
                              if (isVideo)
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Video',
                                      style: GoogleFonts.poppins(
                                        fontSize: 8,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _removeFile(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    if (_selectedFiles.isEmpty) ...[
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 40,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tambahkan gambar atau video',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _selectedFiles.length >= 10
                            ? null
                            : _pickFiles,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          _selectedFiles.isEmpty
                              ? 'Pilih Media'
                              : 'Tambah Media Lagi',
                          style: GoogleFonts.poppins(),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    if (_selectedFiles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${_selectedFiles.length} file dipilih (max 10)',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _postType == 'event' ? 'Buat Event' : 'Posting',
                          style: GoogleFonts.poppins(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade700,
      ),
    ),
  );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    String? Function(String?)? validator,
    IconData? prefixIcon,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(fontSize: 13.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: Colors.grey.shade400,
        ),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 18, color: Colors.grey.shade500)
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade400),
        ),
      ),
    );
  }
}
