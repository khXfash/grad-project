import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../models/mood_log.dart';
import '../models/stress_reading.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;

  bool _isSaving = false;
  bool _isSendingReport = false;
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppProvider>();
    _nameCtrl = TextEditingController(text: p.profileName);
    _emailCtrl = TextEditingController(text: p.reportEmail);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    try {
      await context.read<AppProvider>().saveProfile(
            name: _nameCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
          );
      if (mounted) {
        setState(() => _editMode = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile saved!',
                style: GoogleFonts.plusJakartaSans()),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _sendReport() async {
    final provider = context.read<AppProvider>();
    final recipientEmail = provider.reportEmail;
    final name =
        provider.profileName.isNotEmpty ? provider.profileName : 'User';

    if (recipientEmail.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please save a report email first.',
                style: GoogleFonts.plusJakartaSans()),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    setState(() => _isSendingReport = true);
    try {
      final (readings, moods) = await provider.getWeeklyReport();
      final body =
          _buildReportBody(name: name, readings: readings, moods: moods);
      final subject =
          'EmoHealth Weekly Report - ${DateFormat('MMM d, yyyy').format(DateTime.now())}';

      // Android Intent has a ~1MB hard limit. Percent-encoding triples each
      // character, so cap the *raw* body at 1200 chars before encoding.
      const maxBodyChars = 1200;
      final safeBody = body.length > maxBodyChars
          ? '${body.substring(0, maxBodyChars)}\n...[truncated, ${readings.length} readings, ${moods.length} moods total]'
          : body;

      final encodedSubject = Uri.encodeComponent(subject);
      final encodedBody = Uri.encodeComponent(safeBody);
      final mailtoUrl =
          'mailto:$recipientEmail?subject=$encodedSubject&body=$encodedBody';

      final launched = await launchUrlString(
        mailtoUrl,
        mode: LaunchMode.platformDefault,
      );

      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No email app found. Please install Gmail or Outlook.',
              style: GoogleFonts.plusJakartaSans(),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        final msg = e.toString().contains('PlatformException')
            ? 'Could not open mail app. Please install Gmail or Outlook.'
            : 'Error: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, style: GoogleFonts.plusJakartaSans()),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingReport = false);
    }
  }

  String _buildReportBody({
    required String name,
    required List<StressReading> readings,
    required List<MoodLog> moods,
  }) {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final fmt = DateFormat('MMM d');
    final fmtFull = DateFormat('MMM d, HH:mm');

    final sb = StringBuffer();
    sb.writeln('EmoHealth – Weekly Health Report');
    sb.writeln('Name: $name');
    sb.writeln('Period: ${fmt.format(weekAgo)} – ${fmt.format(now)}');
    sb.writeln('Generated: ${DateFormat('MMM d, yyyy HH:mm').format(now)}');
    sb.writeln('');
    sb.writeln('═══════════════════════════════════════');
    sb.writeln('STRESS READINGS SUMMARY (${readings.length} readings)');
    sb.writeln('═══════════════════════════════════════');

    if (readings.isEmpty) {
      sb.writeln('No stress readings recorded this week.');
    } else {
      final stressedCount = readings.where((r) => r.stressScore >= 50).length;
      final calmCount = readings.length - stressedCount;
      final percentStressed = readings.isEmpty ? 0 : ((stressedCount / readings.length) * 100).round();
      final avgHR =
          readings.map((r) => r.heartRate).reduce((a, b) => a + b) /
              readings.length;

      sb.writeln('Stressed Period      : $percentStressed% of the time');
      sb.writeln('Calm Period          : ${100 - percentStressed}% of the time');
      sb.writeln('Total Calm Readings  : $calmCount');
      sb.writeln('Total Stressed Readings: $stressedCount');
      sb.writeln('Avg Heart Rate       : ${avgHR.toStringAsFixed(0)} bpm');
      sb.writeln('');
      sb.writeln('── Detailed Readings ──');
      for (final r in readings) {
        final status = r.stressScore >= 50 ? 'Stressed' : 'Calm';
        sb.writeln(
            '${fmtFull.format(r.timestamp)}  Status: $status  HR: ${r.heartRate} bpm  Temp: ${r.skinTemp.toStringAsFixed(1)}°C');
      }
    }

    sb.writeln('');
    sb.writeln('═══════════════════════════════════════');
    sb.writeln('MOOD LOGS (${moods.length} entries)');
    sb.writeln('═══════════════════════════════════════');

    if (moods.isEmpty) {
      sb.writeln('No mood logs recorded this week.');
    } else {
      // Count by emotion
      final counts = <String, int>{};
      for (final m in moods) {
        counts[m.emotion] = (counts[m.emotion] ?? 0) + 1;
      }
      sb.writeln('Emotion Breakdown:');
      counts.forEach((e, c) {
        sb.writeln('  ${e[0].toUpperCase()}${e.substring(1)}: $c time(s)');
      });
      sb.writeln('');
      sb.writeln('── Detailed Mood Log ──');
      for (final m in moods) {
        final src = m.source == 'camera'
            ? '[Camera${m.confidence != null ? " ${m.confidence}%" : ""}]'
            : '[Manual]';
        final note = m.notes.isNotEmpty ? '  Note: ${m.notes}' : '';
        final status = m.stressScore >= 50 ? 'Stressed' : 'Calm';
        sb.writeln(
            '${fmtFull.format(m.timestamp)}  ${m.emotion[0].toUpperCase()}${m.emotion.substring(1)} $src  Status@time: $status$note');
      }
    }

    sb.writeln('');
    sb.writeln('───────────────────────────────────────');
    sb.writeln('This report was automatically generated by EmoHealth.');
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.currentUser;
    final isAnon = user?.isAnonymous ?? true;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            // ── Header ───────────────────────────────────────────────
            Text(
              'Profile',
              style: GoogleFonts.manrope(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isAnon ? 'Guest account' : (user?.email ?? ''),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // ── Avatar ───────────────────────────────────────────────
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primary.withAlpha(160),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        provider.profileName.isNotEmpty
                            ? provider.profileName[0].toUpperCase()
                            : (user?.email?.isNotEmpty == true
                                ? user!.email![0].toUpperCase()
                                : '?'),
                        style: GoogleFonts.manrope(
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Profile Form ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.onSurface.withAlpha(8),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Personal Info',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const Spacer(),
                        if (!_editMode)
                          TextButton.icon(
                            onPressed: () => setState(() => _editMode = true),
                            icon: const Icon(Icons.edit_rounded, size: 16),
                            label: const Text('Edit'),
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.primary),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _FieldLabel('Your Name'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nameCtrl,
                      enabled: _editMode,
                      decoration: _inputDeco(
                        hint: 'e.g. Ahmed Ali',
                        icon: Icons.person_outline_rounded,
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 16),
                    _FieldLabel('Report Email'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _emailCtrl,
                      enabled: _editMode,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _inputDeco(
                        hint: 'e.g. doctor@hospital.com',
                        icon: Icons.email_outlined,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Email is required';
                        }
                        final emailRegex =
                            RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                        if (!emailRegex.hasMatch(v.trim())) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    if (_editMode) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _editMode = false;
                                  _nameCtrl.text = provider.profileName;
                                  _emailCtrl.text = provider.reportEmail;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.onSurfaceVariant,
                                side: BorderSide(
                                    color: AppColors.onSurfaceVariant
                                        .withAlpha(80)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text('Cancel',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: _isSaving ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : Text('Save Profile',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Weekly Report Card ────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withAlpha(30),
                    AppColors.primary.withAlpha(12),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withAlpha(60),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(25),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.summarize_rounded,
                            color: AppColors.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Weekly Health Report',
                              style: GoogleFonts.manrope(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface,
                              ),
                            ),
                            Text(
                              'Last 7 days of readings & moods',
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
                  const SizedBox(height: 8),
                  if (provider.reportEmail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          const Icon(Icons.send_rounded,
                              size: 13, color: AppColors.primary),
                          const SizedBox(width: 5),
                          Text(
                            'To: ${provider.reportEmail}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSendingReport ? null : _sendReport,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _isSendingReport
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.mail_rounded,
                              color: Colors.white, size: 18),
                      label: Text(
                        _isSendingReport ? 'Preparing…' : 'Send Report via Email',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),



            // ── Account Section ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.onSurface.withAlpha(8),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account',
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.badge_outlined,
                    label: 'Account Type',
                    value: isAnon ? 'Guest (Anonymous)' : 'Registered',
                  ),
                  if (!isAnon) ...[
                    const SizedBox(height: 8),
                    _InfoRow(
                      icon: Icons.alternate_email_rounded,
                      label: 'Login Email',
                      value: user?.email ?? '—',
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showSignOutDialog(context),
                      icon: const Icon(Icons.logout_rounded,
                          size: 16, color: AppColors.error),
                      label: Text('Sign Out',
                          style: GoogleFonts.plusJakartaSans(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: AppColors.error.withAlpha(80)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 18, color: AppColors.onSurfaceVariant),
      hintStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.onSurfaceVariant.withAlpha(120), fontSize: 14),
      filled: true,
      fillColor: AppColors.surfaceContainer,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.onSurface.withAlpha(15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: Text('Sign Out',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to sign out?',
            style: GoogleFonts.plusJakartaSans()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AppProvider>().signOut();
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurfaceVariant,
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
