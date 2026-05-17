import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kelayakan Panen Sawit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: UploadPage(),
    );
  }
}

class KelayakanResult {
  final String status;
  final double skorKelayakan;
  final String rekomendasi;
  final List<String> konflik;
  final List<String> peringatan;
  final Map<String, dynamic> detailSkor;
  final Map<String, dynamic> prediksiGambar;

  KelayakanResult({
    required this.status,
    required this.skorKelayakan,
    required this.rekomendasi,
    required this.konflik,
    required this.peringatan,
    required this.detailSkor,
    required this.prediksiGambar,
  });

  factory KelayakanResult.fromJson(Map<String, dynamic> json) {
    return KelayakanResult(
      status: json['kelayakan']['status'] ?? '',
      skorKelayakan: (json['kelayakan']['skor_kelayakan'] ?? 0.0).toDouble(),
      rekomendasi: json['kelayakan']['rekomendasi'] ?? '',
      konflik: List<String>.from(json['kelayakan']['konflik'] ?? []),
      peringatan: List<String>.from(json['kelayakan']['peringatan'] ?? []),
      detailSkor: json['kelayakan']['detail_skor'] ?? {},
      prediksiGambar: json['prediksi_gambar'] ?? {},
    );
  }
}

class UploadPage extends StatefulWidget {
  @override
  _UploadPageState createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  File? _image;
  Uint8List? _webImage;
  final picker = ImagePicker();

  bool _isPanenPertama = true;
  final TextEditingController _jarakPanenController = TextEditingController();
  String? _teksturBuah;
  KelayakanResult? _hasilAnalisis;
  bool _isLoading = false;

  Future<void> getImage(ImageSource source) async {
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _webImage = bytes;
          _image = null;
          _hasilAnalisis = null; // Reset hasil saat ganti gambar
        });
      } else {
        setState(() {
          _image = File(pickedFile.path);
          _webImage = null;
          _hasilAnalisis = null; // Reset hasil saat ganti gambar
        });
      }
    }
  }

  // untuk menampilkan opsi ganti gambar
  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: Icon(Icons.camera_alt, color: Colors.green),
                  title: Text('Ambil dari Kamera'),
                  onTap: () {
                    Navigator.pop(context);
                    getImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.photo_library, color: Colors.green),
                  title: Text('Pilih dari Galeri'),
                  onTap: () {
                    Navigator.pop(context);
                    getImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.cancel, color: Colors.red),
                  title: Text('Batal'),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
    );
  }

  //  untuk menghapus gambar
  void _removeImage() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Hapus Foto'),
            content: Text('Apakah Anda yakin ingin menghapus foto ini?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Batal'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _image = null;
                    _webImage = null;
                    _hasilAnalisis = null; // Reset hasil juga
                  });
                  Navigator.pop(context);
                },
                child: Text('Hapus', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
  }

  Future<void> uploadData() async {
    setState(() {
      _isLoading = true;
      _hasilAnalisis = null;
    });

    var uri = Uri.parse('http://127.0.0.1:8000/predict');
    var request = http.MultipartRequest('POST', uri);

    // Validasi input
    if (_image == null && _webImage == null) {
      showSnackbar("Harap unggah foto terlebih dahulu");
      setState(() => _isLoading = false);
      return;
    }

    if (_isPanenPertama) {
      if (_teksturBuah == null) {
        showSnackbar("Harap pilih tekstur buah");
        setState(() => _isLoading = false);
        return;
      }
      request.fields['tekstur'] = _teksturBuah!;
    } else {
      if (_jarakPanenController.text.isEmpty) {
        showSnackbar("Harap isi jarak panen");
        setState(() => _isLoading = false);
        return;
      }
      request.fields['jarak_panen'] = _jarakPanenController.text;

      // Tambahkan tekstur jika dipilih (opsional untuk panen kedua)
      if (_teksturBuah != null) {
        request.fields['tekstur'] = _teksturBuah!;
      }
    }

    // Upload file
    if (kIsWeb && _webImage != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          _webImage!,
          filename: 'image.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    } else if (_image != null) {
      request.files.add(
        await http.MultipartFile.fromPath('file', _image!.path),
      );
    }

    try {
      final response = await request.send();
      final respStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final responseData = jsonDecode(respStr);
        setState(() {
          _hasilAnalisis = KelayakanResult.fromJson(responseData);
          _isLoading = false;
        });
      } else {
        showSnackbar("Gagal mengirim data ke server: ${response.statusCode}");
        setState(() => _isLoading = false);
      }
    } catch (e) {
      showSnackbar("Error: $e");
      setState(() => _isLoading = false);
    }
  }

  void showSnackbar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade600),
    );
  }

  void _showPanduanDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.green),
                SizedBox(width: 8),
                Text("Panduan Penggunaan"),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPanduanItem(
                    "📸",
                    "Unggah foto buah sawit dengan jelas (Pastikan foto tidak buram dan kondisi pencahayaan yang bagus )",
                  ),
                  _buildPanduanItem("🧪", "Pilih tekstur buah saat ditekan"),
                  _buildPanduanItem(
                    "📅",
                    "Masukkan jarak panen (jika bukan panen pertama)",
                  ),
                  _buildPanduanItem(
                    "🔍",
                    "Aplikasi akan menganalisis semua parameter",
                  ),
                  _buildPanduanItem(
                    "⚠️",
                    "Perhatikan konflik antar parameter jika ada (Aplikasi hanya mengenali citra buah sawit pastikan tidak mengunakan foto selain buah sawit)",
                  ),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Status Kelayakan:",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text("🟢 LAYAK PANEN - Siap dipanen"),
                        Text("🟡 PERLU VERIFIKASI - Cek manual"),
                        Text("🔴 BELUM LAYAK - Tunggu lebih lama"),
                        Text("⚠️ PERIKSA ULANG - Data tidak konsisten"),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Tutup"),
              ),
            ],
          ),
    );
  }

  Widget _buildPanduanItem(String icon, String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: TextStyle(fontSize: 16)),
          SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'LAYAK PANEN':
        return Colors.green;
      case 'PERLU VERIFIKASI':
        return Colors.orange;
      case 'BELUM LAYAK':
        return Colors.red;
      case 'PERIKSA ULANG':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'LAYAK PANEN':
        return Icons.check_circle;
      case 'PERLU VERIFIKASI':
        return Icons.warning;
      case 'BELUM LAYAK':
        return Icons.cancel;
      case 'PERIKSA ULANG':
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: Text(
          "SawitGenZ",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline, color: Colors.white),
            onPressed: _showPanduanDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // Image Upload Section
            if (_image == null && _webImage == null)
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Text(
                      "Unggah Foto Buah Sawit",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          onPressed: () => getImage(ImageSource.camera),
                          icon: Icon(Icons.camera_alt),
                          label: Text("Kamera"),
                        ),
                        SizedBox(width: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          onPressed: () => getImage(ImageSource.gallery),
                          icon: Icon(Icons.photo_library),
                          label: Text("Galeri"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // Image Preview with Edit/Delete options
            if (_image != null || _webImage != null) ...[
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 2,
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Header with title and actions
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(11),
                          topRight: Radius.circular(11),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Foto Berhasil Diupload",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => _showImageOptions(),
                                icon: Icon(Icons.edit, color: Colors.blue),
                                tooltip: "Ganti Foto",
                                padding: EdgeInsets.all(4),
                                constraints: BoxConstraints(),
                              ),
                              SizedBox(width: 4),
                              IconButton(
                                onPressed: () => _removeImage(),
                                icon: Icon(Icons.delete, color: Colors.red),
                                tooltip: "Hapus Foto",
                                padding: EdgeInsets.all(4),
                                constraints: BoxConstraints(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Image preview
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child:
                            kIsWeb
                                ? Image.memory(
                                  _webImage!,
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                )
                                : Image.file(
                                  _image!,
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 24),

            // Parameters Section
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Parameter Fisik",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _teksturBuah,
                    decoration: InputDecoration(
                      labelText: 'Tekstur Buah (saat ditekan)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.touch_app),
                    ),
                    items:
                        ['Keras', 'Lunak(Kulit buah mengkilap)']
                            .map(
                              (val) => DropdownMenuItem(
                                value: val,
                                child: Text(val),
                              ),
                            )
                            .toList(),
                    onChanged: (val) => setState(() => _teksturBuah = val),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: _jarakPanenController,
                    enabled: !_isPanenPertama,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Jarak Panen (hari)',
                      border: OutlineInputBorder(),
                      hintText: 'Contoh: 12',
                      prefixIcon: Icon(Icons.calendar_today),
                      helperText:
                          _isPanenPertama
                              ? 'Tidak diperlukan untuk panen pertama'
                              : 'Masukkan jarak dari panen sebelumnya',
                    ),
                  ),
                  SizedBox(height: 16),
                  CheckboxListTile(
                    title: Text("Panen Pertama"),
                    subtitle: Text("Centang jika ini adalah panen pertama"),
                    value: _isPanenPertama,
                    onChanged:
                        (val) => setState(() {
                          _isPanenPertama = val!;
                          if (_isPanenPertama) {
                            _jarakPanenController.clear();
                          }
                        }),
                    activeColor: Colors.green,
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),

            // Analyze Button
            ElevatedButton(
              onPressed: _isLoading ? null : uploadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child:
                  _isLoading
                      ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            "Sedang Menganalisis...",
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      )
                      : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.analytics),
                          SizedBox(width: 8),
                          Text(
                            "Analisis Kelayakan",
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
            ),
            SizedBox(height: 24),

            // Results Section
            if (_hasilAnalisis != null) _buildResultSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildResultSection() {
    final result = _hasilAnalisis!;
    final statusColor = _getStatusColor(result.status);
    final statusIcon = _getStatusIcon(result.status);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.1),
            spreadRadius: 2,
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.status,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Prediksi Gambar
                _buildSectionTitle("Hasil Deteksi Foto"),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.image, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        "Prediksi: ${result.prediksiGambar['label']} (${result.prediksiGambar['kepercayaan']})",
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),

                // Detail Skor
                _buildSectionTitle("Detail Skor Parameter"),
                _buildScoreDetails(result.detailSkor),
                SizedBox(height: 16),

                // Rekomendasi
                _buildSectionTitle("Rekomendasi"),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb, color: Colors.blue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          result.rekomendasi,
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),

                // Konflik (jika ada)
                if (result.konflik.isNotEmpty) ...[
                  SizedBox(height: 16),
                  _buildSectionTitle("⚠️ Konflik Parameter"),
                  ...result.konflik.map(
                    (konflik) => Container(
                      margin: EdgeInsets.only(bottom: 8),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning, color: Colors.orange, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              konflik,
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Peringatan (jika ada)
                if (result.peringatan.isNotEmpty) ...[
                  SizedBox(height: 16),
                  _buildSectionTitle("💡 Peringatan"),
                  ...result.peringatan.map(
                    (peringatan) => Container(
                      margin: EdgeInsets.only(bottom: 8),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.yellow.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.yellow.shade300),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info,
                            color: Colors.amber.shade700,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              peringatan,
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildScoreDetails(Map<String, dynamic> detailSkor) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          if (detailSkor['foto'] != null)
            _buildScoreRow("Foto", detailSkor['foto'], Icons.image),
          if (detailSkor['tekstur'] != null)
            _buildScoreRow("Tekstur", detailSkor['tekstur'], Icons.touch_app),
          if (detailSkor['jarak_panen'] != null)
            _buildScoreRow(
              "Jarak Panen",
              detailSkor['jarak_panen'],
              Icons.calendar_today,
            ),
        ],
      ),
    );
  }

  Widget _buildScoreRow(String label, double score, IconData icon) {
    Color scoreColor;
    if (score >= 80) {
      scoreColor = Colors.green;
    } else if (score >= 60) {
      scoreColor = Colors.orange;
    } else if (score >= 40) {
      scoreColor = Colors.amber;
    } else {
      scoreColor = Colors.red;
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(fontSize: 13))),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scoreColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scoreColor.withOpacity(0.3)),
            ),
            child: Text(
              "${score.toStringAsFixed(1)}%",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: scoreColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
