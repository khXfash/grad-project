import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../models/stress_reading.dart';
import '../widgets/sensor_card.dart';
import '../widgets/stress_chart.dart';
import '../widgets/bracelet_status.dart';
import '../widgets/ble_connect_sheet.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Consumer<AppProvider>(
          builder: (context, provider, _) {
            final reading = provider.latestReading;
            final readings = provider.recentReadings;

            return CustomScrollView(
              slivers: [
                // ── Header ──────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _greeting(),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    'How are you feeling?',
                                    style: GoogleFonts.manrope(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: AppColors.primaryContainer,
                              child: const Icon(
                                Icons.person_outline_rounded,
                                color: AppColors.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Bracelet connection card
                        BraceletStatusCard(
                          isConnected: provider.isConnected,
                          onConnect: () => showBLEConnectSheet(context),
                          onDisconnect: provider.disconnectBracelet,
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Sensor Empty Warning Banner ──────────────────────────
                if (provider.isConnected && !provider.isFingerDetected)
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.error.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.error.withAlpha(100), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.warning_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sensor Empty',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.error,
                                  ),
                                ),
                                Text(
                                  'Please place your finger on the biometric sensor. Ensure full contact with the red-light reader to stream metrics.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Critical Stress Warning Banner ───────────────────────
                if (provider.isCriticalStress)
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.error.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.error, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.error.withAlpha(15),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.bolt_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'CRITICAL STRESS DETECTED',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.error,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  provider.reportEmail.isNotEmpty
                                      ? 'An emergency alert email has been sent automatically to your doctor (${provider.reportEmail}). Please take deep breaths.'
                                      : 'No doctor\'s email is set. Go to your Profile tab to configure it so alerts can be sent automatically.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.onSurface,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Stress Score Hero ────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: _StressHeroCard(reading: reading),
                  ),
                ),

                // ── Sensor Cards ─────────────────────────────────────────
                if (provider.isConnected && reading != null) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Text(
                        'Live Sensors',
                        style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: SensorCard(
                              icon: Icons.favorite_rounded,
                              label: 'Heart Rate',
                              value: '${reading.heartRate}',
                              unit: 'bpm',
                              color: const Color(0xFFE91E63),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SensorCard(
                              icon: Icons.thermostat_rounded,
                              label: 'Skin Temp',
                              value: reading.skinTemp.toStringAsFixed(1),
                              unit: '°C',
                              color: AppColors.tertiary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SensorCard(
                              icon: Icons.vibration_rounded,
                              label: 'Movement',
                              value: reading.accelMagnitude.toStringAsFixed(1),
                              unit: 'm/s²',
                              color: AppColors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // ── Stress Chart ─────────────────────────────────────────
                if (readings.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Row(
                        children: [
                          Text(
                            'Stress Trend',
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Last ${readings.length} readings',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: StressChartWidget(readings: readings),
                    ),
                  ),
                ],


              ],
            );
          },
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning 🌅';
    if (hour < 17) return 'Good afternoon ☀️';
    return 'Good evening 🌙';
  }
}

// ── Stress Hero Card ────────────────────────────────────────────────────────

class _StressHeroCard extends StatelessWidget {
  final StressReading? reading;
  const _StressHeroCard({required this.reading});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final hasData = reading != null;
    final isStressed = provider.isStressed;

    // Define colors and gradient based on stress status
    final List<Color> gradientColors;
    if (!hasData) {
      gradientColors = [AppColors.primary, const Color(0xFF005D5F)];
    } else if (isStressed) {
      gradientColors = [AppColors.stressHigh, const Color(0xFFC62828)];
    } else {
      gradientColors = [const Color(0xFF2E7D32), AppColors.stressLow];
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (hasData && isStressed ? AppColors.stressHigh : AppColors.primary).withAlpha(50),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Stress Status',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.onPrimary.withAlpha(200),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                hasData ? (isStressed ? 'Stressed 😤' : 'Calm 😌') : '--',
                style: GoogleFonts.manrope(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (hasData) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Biometrics: ${reading!.stressScore >= 50 ? "Stressed" : "Calm"}  •  Face: ${provider.detectedEmotion}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              'Connect your bracelet to start monitoring',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: Colors.white70,
              ),
            ),
          ],
        ],
      ),
    );
  }
}


