import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

void showBLEConnectSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const BLEConnectSheet(),
  );
}

class BLEConnectSheet extends StatefulWidget {
  const BLEConnectSheet({super.key});

  @override
  State<BLEConnectSheet> createState() => _BLEConnectSheetState();
}

class _BLEConnectSheetState extends State<BLEConnectSheet> {
  bool _connecting = false;
  String? _connectingDeviceName;

  @override
  void initState() {
    super.initState();
    // Auto-start scan on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().startScan();
    });
  }

  @override
  void dispose() {
    // Stop scanning when sheet is dismissed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        context.read<AppProvider>().stopScan();
      } catch (_) {}
    });
    super.dispose();
  }

  Future<void> _handleConnect(BuildContext context, ScanResult result) async {
    setState(() {
      _connecting = true;
      _connectingDeviceName = result.device.platformName.isNotEmpty
          ? result.device.platformName
          : 'Unknown Device';
    });

    final provider = context.read<AppProvider>();
    try {
      await provider.connectToDevice(result.device);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${result.device.platformName}! 🔗'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        setState(() {
          _connecting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed. Please try again or use Demo Mode.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isScanning = provider.isScanning;
    final scanResults = provider.scanResults;

    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withAlpha(100),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sensors_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect stress tracker',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      _connecting
                          ? 'Linking to $_connectingDeviceName...'
                          : (isScanning ? 'Searching for devices nearby...' : 'Bluetooth scan paused'),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Core content area
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _connecting
                ? _buildConnectingState()
                : _buildScannerListState(isScanning, scanResults),
          ),

          const SizedBox(height: 24),

          // Demo Mode fallback launcher
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No physical bracelet?',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        'Simulate high-fidelity biometrics to test all app functions.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _connecting
                      ? null
                      : () {
                          provider.startSimulationMode();
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Simulation Mode activated! 🧪'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    textStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  icon: const Icon(Icons.science_rounded, size: 14),
                  label: const Text('Demo Mode'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingState() {
    return Container(
      key: const ValueKey('connecting_state'),
      height: 200,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 4,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Negotiating Connection...',
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Discovering services & configuring biometrics pipelines...',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerListState(bool isScanning, List<dynamic> scanResults) {
    return SizedBox(
      key: const ValueKey('scanner_list_state'),
      height: 250,
      child: Column(
        children: [
          // Scanning Radar / Button header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Discovered Devices (${scanResults.length})',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              if (isScanning)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const RadarWidget(),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => context.read<AppProvider>().stopScan(),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Stop',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                )
              else
                TextButton.icon(
                  onPressed: () => context.read<AppProvider>().startScan(),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.primary),
                  label: Text(
                    'Scan Again',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Scrollable device listing
          Expanded(
            child: scanResults.isEmpty
                ? _buildEmptyState(isScanning)
                : ListView.builder(
                    itemCount: scanResults.length,
                    padding: EdgeInsets.zero,
                    itemBuilder: (context, index) {
                      final result = scanResults[index] as ScanResult;
                      final name = result.device.platformName.isNotEmpty
                          ? result.device.platformName
                          : 'Unknown Device';
                      final isBracelet = name.toLowerCase().contains('esp32') ||
                          name.toLowerCase().contains('biometrics') ||
                          name.toLowerCase().contains('uart') ||
                          name.toLowerCase().contains('bracelet');

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isBracelet
                              ? AppColors.primaryContainer.withAlpha(20)
                              : AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: isBracelet
                              ? Border.all(color: AppColors.primary.withAlpha(80), width: 1.5)
                              : null,
                        ),
                        child: ListTile(
                          onTap: () => _handleConnect(context, result),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isBracelet
                                  ? AppColors.primaryContainer.withAlpha(150)
                                  : AppColors.surfaceContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isBracelet ? Icons.favorite_rounded : Icons.bluetooth_rounded,
                              color: isBracelet ? AppColors.primary : AppColors.outline,
                              size: 18,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: isBracelet ? FontWeight.bold : FontWeight.w600,
                                    color: AppColors.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isBracelet) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [AppColors.primary, Color(0xFF005B5D)],
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Bracelet Detected',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            'Signal: ${result.rssi} dBm  |  ${result.device.remoteId}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.onSurfaceVariant.withAlpha(150),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isScanning) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isScanning ? Icons.bluetooth_searching_rounded : Icons.bluetooth_disabled_rounded,
          size: 40,
          color: AppColors.outlineVariant,
        ),
        const SizedBox(height: 12),
        Text(
          isScanning ? 'Listening for Bluetooth signals...' : 'Bluetooth scan stopped',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
        Text(
          isScanning ? 'Make sure your ESP32 device is powered on.' : 'Tap "Scan Again" to refresh the nearby devices list.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── Concentric Radar Waves Painter ──────────────────────────────────────────

class RadarWidget extends StatefulWidget {
  const RadarWidget({super.key});

  @override
  State<RadarWidget> createState() => _RadarWidgetState();
}

class _RadarWidgetState extends State<RadarWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _RadarPainter(_controller.value),
          size: const Size(18, 18),
        );
      },
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double value;
  _RadarPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 2; i++) {
      final t = (value + i / 2.0) % 1.0;
      final radius = maxRadius * t;
      final opacity = (1.0 - t).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = AppColors.primary.withAlpha((opacity * 150).toInt())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawCircle(center, radius, paint);
    }

    final centerPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3.0, centerPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => true;
}
